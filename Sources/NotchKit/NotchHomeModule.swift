import CoreGraphics
import SwiftUI

/// A block on the Home tab of the expanded panel. Features offer modules through
/// `NotchFeature.makeHomeModules()`; in the settings window the user picks which
/// ones Home shows, in what order, and how wide each one is.
///
/// Home lays its modules out in one row, left to right; "width" here is a
/// module's length along that row.
public struct NotchHomeModule: Identifiable {
    /// Stable identifier, e.g. "weather". The saved Home layout refers to modules by it.
    public let id: String
    /// Name in the settings window, e.g. `localized(en: "Weather", zh: "天气")`.
    /// Read while the window draws, so it follows the interface language.
    public let title: @MainActor () -> String
    /// SF Symbol shown next to the name in the settings window.
    public let symbol: String
    /// An optional line under the name in the settings window, such as where the
    /// module's data comes from. Read while the window draws.
    public let detail: (@MainActor () -> String)?
    /// How wide the module may be. Home reads it whenever it lays the row out,
    /// so it may follow observable state: a module whose width follows its own
    /// state (such as how many items it shows) returns `.fixed`, and when that
    /// width changes Home gives the difference to its neighbours, or takes it
    /// from them (see `HomeLayout.followFixedWidths`).
    @MainActor public var sizing: HomeModuleSizing {
        sizingProvider()
    }
    private let sizingProvider: @MainActor () -> HomeModuleSizing
    /// The module at the size Home gives it: its width along the row by the row's
    /// height. It draws its own background, usually a `NotchCard`, and may switch
    /// to a different arrangement as the width grows.
    public let content: @MainActor (CGSize) -> AnyView

    /// A module whose sizing never changes.
    public init(
        id: String,
        title: @escaping @MainActor () -> String,
        symbol: String,
        detail: (@MainActor () -> String)? = nil,
        sizing: HomeModuleSizing,
        content: @escaping @MainActor (CGSize) -> AnyView
    ) {
        self.init(id: id, title: title, symbol: symbol, detail: detail, sizing: { sizing }, content: content)
    }

    /// A module whose sizing follows observable state: `sizing` is read each
    /// time Home lays the row out.
    public init(
        id: String,
        title: @escaping @MainActor () -> String,
        symbol: String,
        detail: (@MainActor () -> String)? = nil,
        sizing: @escaping @MainActor () -> HomeModuleSizing,
        content: @escaping @MainActor (CGSize) -> AnyView
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.sizingProvider = sizing
        self.content = content
    }
}

/// How wide a Home module may be.
public enum HomeModuleSizing: Equatable, Sendable {
    /// Always this wide; the settings window offers no width control.
    case fixed(HomeModuleLength)
    /// As wide as the user sets it, from `minimum` to `maximum`; with no maximum,
    /// up to the whole row.
    case resizable(minimum: HomeModuleLength, maximum: HomeModuleLength? = nil)

    public var isResizable: Bool {
        if case .resizable = self { return true }
        return false
    }

    /// The narrowest the module may be in `row`, in points, never wider than the row.
    public func minimumWidth(in row: HomeRowMetrics) -> CGFloat {
        switch self {
        case .fixed(let length), .resizable(let length, _):
            min(max(length.width(in: row), 0), row.width)
        }
    }

    /// The widest the module may be in `row`, in points: at least its minimum, and
    /// never wider than the row.
    public func maximumWidth(in row: HomeRowMetrics) -> CGFloat {
        let minimum = minimumWidth(in: row)
        switch self {
        case .fixed:
            return minimum
        case .resizable(_, let maximum?):
            return min(max(maximum.width(in: row), minimum), row.width)
        case .resizable(_, nil):
            return row.width
        }
    }
}

/// A width along Home's row.
public enum HomeModuleLength: Equatable, Sendable {
    /// A number of points.
    case points(CGFloat)
    /// A share of the row that counts the gap after the module, so `n` modules of
    /// `1/n` fill the row exactly, gaps included (see `HomeRowMetrics`).
    case fraction(Double)
    /// A multiple of the row's height; `1` makes a square.
    case height(Double)

    public func width(in row: HomeRowMetrics) -> CGFloat {
        switch self {
        case .points(let points): points
        case .fraction(let fraction): row.width(forFraction: fraction)
        case .height(let multiple): row.height * CGFloat(multiple)
        }
    }
}

/// The size of Home's row and the gap between its modules.
public struct HomeRowMetrics: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var spacing: CGFloat

    public init(width: CGFloat, height: CGFloat, spacing: CGFloat) {
        self.width = width
        self.height = height
        self.spacing = spacing
    }

    /// The width of a module that takes `fraction` of the row, its gap included.
    public func width(forFraction fraction: Double) -> CGFloat {
        CGFloat(fraction) * (width + spacing) - spacing
    }

    /// The share of the row a module `width` points wide takes, its gap included.
    /// Modules fit in the row when their shares add up to at most 1.
    public func fraction(forWidth width: CGFloat) -> Double {
        guard self.width + spacing > 0 else { return 0 }
        return Double((width + spacing) / (self.width + spacing))
    }
}
