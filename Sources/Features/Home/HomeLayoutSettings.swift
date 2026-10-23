import Foundation
import NotchKit
import NotchUI
import Observation

/// The Home tab's layout, as the settings window edits it, and the modules it can
/// hold. Saved on every change; until the user changes it, Home shows the
/// standard layout of whatever modules exist (see `HomeLayout.standard`).
@MainActor
@Observable
public final class HomeLayoutSettings {
    public static let shared = HomeLayoutSettings(defaults: .standard)

    static let layoutKey = "NotchHomeLayout"

    /// The most modules Home shows at once.
    public nonisolated static let maximumModuleCount = HomeLayout.maximumCount
    /// Gap between modules in Home's row.
    public nonisolated static let spacing: CGFloat = 10
    /// How much wider the island grows for each module past the first, in order:
    /// the second and the third add the same, the fourth less, so a full row does
    /// not stretch the island too far. One entry per module up to `maximumModuleCount`.
    public nonisolated static let extraWidths: [CGFloat] = [120, 120, 80]

    /// Body width of the expanded island while Home shows `count` modules: the
    /// standard width for one module or none, plus `extraWidths` for each further
    /// one, up to `maximumModuleCount`.
    public nonisolated static func bodyWidth(forModuleCount count: Int) -> CGFloat {
        let extraModules = max(min(count, maximumModuleCount) - 1, 0)
        return NotchTheme.expandedSize.width + extraWidths.prefix(extraModules).reduce(0, +)
    }

    /// Home's row with `count` modules under a 32-point notch: as wide as the body at
    /// `bodyWidth(forModuleCount:)` less the top corner radius and the content padding
    /// on each side (so a little narrower than the island's content), as tall as the panel's
    /// header and margins leave. Layouts are edited against the row for their own
    /// count; Home draws them in the row it actually gets, whose height follows the notch.
    public nonisolated static func referenceRow(forModuleCount count: Int) -> HomeRowMetrics {
        HomeRowMetrics(
            width: bodyWidth(forModuleCount: count) - 2 * (NotchTheme.expandedTopRadius + NotchTheme.contentPadding),
            height: 134,
            spacing: spacing
        )
    }

    /// A module in the layout, with its width as a share of `currentRow`.
    public struct Placement: Identifiable {
        public let module: NotchHomeModule
        public let width: Double
        /// The shares the module can be set to now (see `HomeLayout.widthRange`); a
        /// single value when it cannot be resized or the others leave no room.
        public let range: ClosedRange<Double>
        public var id: String { module.id }
    }

    /// A module at its width in points in a given row.
    public struct PlacedModule: Identifiable {
        public let module: NotchHomeModule
        public let width: CGFloat
        public var id: String { module.id }
    }

    /// Every module Home can show, in the order Home registered them.
    public private(set) var modules: [NotchHomeModule] = []
    private(set) var layout: HomeLayout

    @ObservationIgnored private let defaults: UserDefaults
    /// False until the user first changes the layout; until then it follows
    /// `HomeLayout.standard` for the registered modules.
    @ObservationIgnored private var isCustomized: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.layoutKey),
           let items = try? JSONDecoder().decode([HomeLayout.Item].self, from: data) {
            layout = HomeLayout(items: items)
            isCustomized = true
        } else {
            layout = HomeLayout()
            isCustomized = false
        }
    }

    /// Called by `HomeFeature` once every module is known.
    func register(_ modules: [NotchHomeModule]) {
        // Ids key the saved layout; a duplicate would make two modules collide.
        assert(Set(modules.map(\.id)).count == modules.count, "Duplicate NotchHomeModule id")
        self.modules = modules
        if isCustomized {
            layout.normalize(sizings: sizings, rows: Self.referenceRow(forModuleCount:))
        } else {
            layout = .standard(moduleIDs: modules.map(\.id), sizings: sizings, rows: Self.referenceRow(forModuleCount:))
        }
    }

    // MARK: Reading

    /// The row the layout is edited against: the reference row for its module count.
    public var currentRow: HomeRowMetrics {
        Self.referenceRow(forModuleCount: layout.items.count)
    }

    /// Body width of the expanded island for the modules Home shows now.
    public var expandedWidth: CGFloat {
        Self.bodyWidth(forModuleCount: layout.items.count)
    }

    public var placements: [Placement] {
        let sizings = sizings
        let row = currentRow
        return layout.items.indices.compactMap { index in
            let item = layout.items[index]
            guard let module = module(item.moduleID),
                  let range = layout.widthRange(at: index, sizings: sizings, row: row)
            else { return nil }
            return Placement(module: module, width: item.width, range: range)
        }
    }

    /// The modules in the layout and their widths in `row`.
    public func placedModules(in row: HomeRowMetrics) -> [PlacedModule] {
        let widths = layout.resolvedWidths(in: row, sizings: sizings)
        return zip(layout.items, widths).compactMap { item, width in
            module(item.moduleID).map { PlacedModule(module: $0, width: width) }
        }
    }

    /// Registered modules not in the layout yet.
    public var modulesNotShown: [NotchHomeModule] {
        modules.filter { module in !layout.items.contains { $0.moduleID == module.id } }
    }

    /// Whether `moduleID` can join the layout now (see `HomeLayout.canAdd`).
    public func canAdd(_ moduleID: String) -> Bool {
        layout.canAdd(moduleID, sizings: sizings, rows: Self.referenceRow(forModuleCount:))
    }

    // MARK: Editing

    public func add(_ moduleID: String) {
        edit { $0.add(moduleID, sizings: sizings, rows: Self.referenceRow(forModuleCount:)) }
    }

    public func remove(at index: Int) {
        edit { $0.remove(at: index, sizings: sizings, rows: Self.referenceRow(forModuleCount:)) }
    }

    public func move(from source: Int, to destination: Int) {
        edit { $0.move(from: source, to: destination) }
    }

    /// `width` is a share of `currentRow` (see `HomeLayout.setWidth`).
    public func setWidth(_ width: Double, at index: Int) {
        edit { $0.setWidth(width, at: index, sizings: sizings, row: currentRow) }
    }

    private func edit(_ change: (inout HomeLayout) -> Void) {
        var layout = layout
        change(&layout)
        guard layout != self.layout else { return }
        self.layout = layout
        isCustomized = true
        if let data = try? JSONEncoder().encode(layout.items) {
            defaults.set(data, forKey: Self.layoutKey)
        }
    }

    private var sizings: [String: HomeModuleSizing] {
        Dictionary(modules.map { ($0.id, $0.sizing) }, uniquingKeysWith: { first, _ in first })
    }

    private func module(_ id: String) -> NotchHomeModule? {
        modules.first { $0.id == id }
    }
}
