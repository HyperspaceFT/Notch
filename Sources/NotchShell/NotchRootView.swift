import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// Root of the panel: the island, pinned to the top center of the fixed-size panel.
struct NotchRootView: View {
    let model: NotchViewModel
    /// Opens the settings window; the app owns it.
    let openSettings: () -> Void

    var body: some View {
        let shape = NotchShape(
            topCornerRadius: model.topCornerRadius,
            bottomCornerRadius: model.bottomCornerRadius
        )
        let isExpanded = model.state == .expanded

        ZStack(alignment: .top) {
            switch model.state {
            case .collapsed, .expanded:
                // The expanded panel is the overlay below, which outlives the state.
                Color.clear
            case .activity:
                if let activity = model.currentActivity {
                    ActivityWingsView(
                        activity: activity,
                        notchSize: model.geometry.notchRect.size,
                        earInset: model.topCornerRadius
                    )
                    // A new activity replaces the old one with a blur instead of a cut.
                    .id("\(activity.featureID).\(activity.id)")
                    .transition(.blurReplace)
                }
            }
        }
        .frame(width: model.islandSize.width, height: model.islandSize.height, alignment: .top)
        .overlay(alignment: .top) {
            if model.isExpandedContentMounted {
                ExpandedIslandView(model: model)
                    // Laid out at the expanded size even while the outline is
                    // smaller, so nothing reflows as the island opens or closes.
                    .frame(width: Self.expandedIslandWidth, height: NotchTheme.expandedSize.height)
                    // Collapsing, and expanding again before that has finished,
                    // turn the content around with the state's animation.
                    .modifier(DropEffect(isDropped: model.isExpandedContentDropped))
                    // While it rises, clicks belong to the collapsed island.
                    .allowsHitTesting(model.isExpanded)
                    // Mounted raised and unmounted out of sight.
                    .transition(.identity)
                    .onAppear {
                        // The first drop sets off after the outline and trails it.
                        withAnimation(NotchTheme.expandDropAnimation.delay(NotchTheme.expandDropDelay)) {
                            model.expandedContentDidAppear()
                        }
                    }
            }
        }
        .background {
            shape.fill(NotchTheme.islandColor)
            // Under the content: it lights the island, not the cards on it.
            IslandRim(topCornerRadius: model.topCornerRadius, bottomCornerRadius: model.bottomCornerRadius)
                .opacity(isExpanded && NotchAppearance.shared.isLightAndColorEnabled ? 1 : 0)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        // The hovered ring casts a lighter, tighter shadow than the expanded panel.
        .shadow(
            color: .black.opacity(isExpanded ? 0.5 : model.isHovered ? 0.35 : 0),
            radius: isExpanded ? NotchTheme.expandedShadowRadius : 8,
            y: isExpanded ? NotchTheme.expandedShadowOffset : 4
        )
        // The whole outline takes clicks, including the empty collapsed body.
        // The panel only passes them on while the island is hovered or expanded.
        .contentShape(shape)
        .gesture(
            TapGesture().onEnded { model.setExpanded(true) },
            // Expanded: clicks belong to the controls inside.
            including: isExpanded ? .subviews : .all
        )
        .contextMenu {
            Button(localized(en: "Settings…", zh: "设置…"), systemImage: "gearshape", action: openSettings)
            Divider()
            Button(localized(en: "Quit", zh: "退出"), systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        // Inner animations win when several values change at once, so expanding
        // the hovered island (which also clears the hover) uses `expandAnimation`.
        .animation(animation(for: model.state), value: model.state)
        .animation(NotchTheme.activityAnimation, value: model.currentActivity.map { "\($0.featureID).\($0.id)" })
        .animation(model.isHovered ? NotchTheme.hoverAnimation : NotchTheme.collapseAnimation, value: model.isHovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The panel overlaps the notch; without this SwiftUI would push content below it.
        .ignoresSafeArea()
    }

    /// Frame width of the expanded island, ears included.
    private static let expandedIslandWidth = NotchShape.frameWidth(
        bodyWidth: NotchTheme.expandedSize.width,
        topCornerRadius: NotchTheme.expandedTopRadius
    )

    private func animation(for state: NotchViewModel.State) -> Animation {
        switch state {
        case .expanded: NotchTheme.expandAnimation
        case .collapsed: NotchTheme.collapseAnimation
        case .activity: NotchTheme.activityAnimation
        }
    }
}

/// The expanded content in place, or raised into the notch: shifted up, narrowed
/// toward the top, blurred, and faded. The island's outline clips it, so dropping
/// looks like falling out of the notch, and rising like retracting into it.
private struct DropEffect: ViewModifier {
    let isDropped: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isDropped ? 1 : 0.94, anchor: .top)
            .offset(y: isDropped ? 0 : -NotchTheme.expandDropDistance)
            .blur(radius: isDropped ? 0 : 6)
            .opacity(isDropped ? 1 : 0)
    }
}

/// The expanded island's edge, lit by the sky (`SkyLight`): an even rim along the
/// sides and bottom with a soft halo inside it, and the sun as a band of light
/// moving along it. Clear toward the top, so the band beside the hardware notch
/// stays pure black. The island's clip keeps only the inner half of each stroke.
private struct IslandRim: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    /// Where the sun's path meets the sides, as a share of the island's height:
    /// below the tab buttons.
    private static let horizon: CGFloat = 0.3

    /// The sun's band, widest and faintest first; stacked, they fade out along
    /// the edge. `length` is a share of the sun's path.
    private static let sunLayers: [(length: Double, lineWidth: CGFloat, blur: CGFloat, opacity: Double)] = [
        (0.4, 26, 18, 0.45),
        (0.22, 10, 7, 0.6),
        (0.1, 3, 1.5, 0.9),
    ]

    var body: some View {
        // Redrawn every minute; the light moves too little in a minute to see a step.
        TimelineView(.everyMinute) { context in
            let light = SkyLight.at(context.date, sunTimes: Daylight.shared.sunTimes)
            ZStack {
                rim(light.rim)
                if light.sun.strength > 0 {
                    sun(light.sun)
                }
            }
            // New sun times ease in rather than jump.
            .animation(.smooth(duration: 1), value: light)
        }
    }

    private func rim(_ rim: SkyLight.Rim) -> some View {
        let shape = NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
        let color = Color(rim.color)
        let gradient = LinearGradient(
            stops: [
                .init(color: color.opacity(0), location: 1 - rim.reach),
                .init(color: color.opacity(rim.intensity), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        return ZStack {
            if rim.halo > 0 {
                shape
                    .stroke(gradient, lineWidth: 18)
                    .blur(radius: 12)
                    .opacity(rim.halo)
            }
            shape.stroke(gradient, lineWidth: 2)
        }
    }

    private func sun(_ sun: SkyLight.Sun) -> some View {
        let edge = NotchEdge(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            horizon: Self.horizon
        )
        let color = Color(sun.color)
        return ZStack {
            ForEach(Self.sunLayers.indices, id: \.self) { index in
                let layer = Self.sunLayers[index]
                let from = min(max(sun.position - layer.length / 2, 0), 1)
                let to = min(max(sun.position + layer.length / 2, 0), 1)
                // Past the end of the edge, where a round cap would still draw a dot.
                if to > from {
                    edge
                        .trim(from: from, to: to)
                        .stroke(color, style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round))
                        .blur(radius: layer.blur)
                        .opacity(layer.opacity * sun.strength)
                }
            }
        }
    }
}

private extension Color {
    init(_ rgb: SkyLight.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Leading and trailing activity content on either side of the hardware notch.
private struct ActivityWingsView: View {
    let activity: NotchActivity
    let notchSize: CGSize
    let earInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            activity.leading
                .frame(width: NotchTheme.activityWingWidth, alignment: .center)
            // Nothing is visible behind the camera housing.
            Color.clear
                .frame(width: notchSize.width)
            activity.trailing
                .frame(width: NotchTheme.activityWingWidth, alignment: .center)
        }
        .frame(height: notchSize.height)
        .foregroundStyle(NotchTheme.primaryText)
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, earInset)
    }
}

/// The expanded panel: a header row with tab buttons, and the selected feature's
/// view below. Quitting lives in the island's right-click menu.
private struct ExpandedIslandView: View {
    let model: NotchViewModel
    /// Shared by the tab buttons and the selection highlight that slides between them.
    @Namespace private var tabSelection

    /// Visible tabs in header order, left to right.
    private var orderedTabs: [NotchViewModel.Tab] {
        let tabs = model.visibleTabs
        return tabs.filter { $0.placement == .leading } + tabs.filter { $0.placement == .trailing }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            content
        }
        .foregroundStyle(NotchTheme.primaryText)
        // The expanded radius, not the current one: the content stays on screen
        // while the island collapses.
        .padding(.horizontal, NotchTheme.expandedTopRadius + NotchTheme.contentPadding)
        .padding(.bottom, 14)
    }

    /// Sits in the same band as the hardware notch, so the tab buttons stay clear
    /// of it: leading tabs to its left, trailing tabs to its right.
    private var header: some View {
        HStack(spacing: 0) {
            tabButtons(.leading)
            Spacer(minLength: model.geometry.notchRect.width)
            tabButtons(.trailing)
        }
        .frame(height: max(model.geometry.notchRect.height, 30))
    }

    /// One side's buttons. Only the selected button has a glass background: one
    /// view per side that slides between that side's buttons, and fades out on one
    /// side and in on the other when the selection crosses the notch.
    private func tabButtons(_ placement: NotchTabPlacement) -> some View {
        let tabs = model.visibleTabs.filter { $0.placement == placement }
        let selectedID = model.selectedTab?.id
        return HStack(spacing: 6) {
            ForEach(tabs) { tab in
                TabButton(
                    symbol: tab.symbol(),
                    isSelected: tab.id == selectedID,
                    help: tab.title()
                ) {
                    withAnimation(NotchTheme.tabSwitchAnimation) {
                        model.selectedTabID = tab.id
                    }
                }
                .matchedGeometryEffect(id: tab.id, in: tabSelection)
            }
        }
        // Not inside a GlassEffectContainer: there this glass was drawn over the icons.
        .background {
            if let selectedID, tabs.contains(where: { $0.id == selectedID }) {
                Color.clear
                    .glassEffect(.regular.tint(.white.opacity(0.18)), in: .circle)
                    .matchedGeometryEffect(id: selectedID, in: tabSelection, isSource: false)
                    .transition(.opacity)
            }
        }
    }

    /// Every tab's view stays in place and only the selected one shows, so on a
    /// switch each view slides toward its own side of the newly selected tab.
    @ViewBuilder
    private var content: some View {
        let tabs = orderedTabs
        if tabs.isEmpty {
            Text(localized(en: "Nothing to show", zh: "没有可显示的内容"))
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let selectedIndex = tabs.firstIndex { $0.id == model.selectedTab?.id } ?? 0
            ZStack {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let isSelected = index == selectedIndex
                    tab.content
                        .offset(x: CGFloat((index - selectedIndex).signum()) * NotchTheme.tabSwitchOffset)
                        .opacity(isSelected ? 1 : 0)
                        .blur(radius: isSelected ? 0 : 6)
                        // Hidden tabs must not take clicks or drops meant for the visible one.
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A tab's icon. It draws no background of its own; the selected tab's glass
/// highlight belongs to the header.
private struct TabButton: View {
    let symbol: String
    let isSelected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
