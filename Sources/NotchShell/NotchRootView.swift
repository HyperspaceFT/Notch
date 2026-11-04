import AppKit
import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Root of the panel: the island, pinned to the top center of the fixed-size panel.
struct NotchRootView: View {
    let model: NotchViewModel
    /// Opens the settings window; the app owns it.
    let openSettings: () -> Void
    /// Shared by an activity's wings and the tabs, for views that fly between
    /// them (`notchMorphHero`).
    @Namespace private var activityMorph
    /// Kept here, for the panel's lifetime, rather than in `@State`, which needs a
    /// macro plugin the Command Line Tools do not ship.
    private let trailingTabRowScroll = TrailingTabRowScroll()

    var body: some View {
        let shape = NotchShape(
            topCornerRadius: model.topCornerRadius,
            bottomCornerRadii: model.bottomCornerRadii
        )
        let isExpanded = model.state == .expanded
        let wingsActivity: NotchActivity? = if isExpanded && model.detail != nil {
            // A detail covers the tab buttons' band and has no tab for heroes to
            // fly into, so they leave with their wings. Once it collapses, the
            // current activity's wings return over the rising detail, as they do
            // over the rising tabs.
            nil
        } else {
            switch model.state {
            case .collapsed: nil
            // A band has an overlay of its own.
            case .activity: model.currentActivity.flatMap { $0.rim == nil ? $0 : nil }
            // Kept over the open panel only for the heroes that fly into its tab,
            // even while another activity is current (it draws nothing there).
            case .expanded: model.morphingActivity
            }
        }
        let rimActivity = model.rimActivity
        // Shown only while it is the current activity on the closed island; else
        // retracted into its right end.
        let isRimRetracted = isExpanded || rimActivity.map { rim in
            model.currentActivity.map { $0.featureID == rim.featureID && $0.id == rim.id } != true
        } ?? true
        let morph = NotchActivityMorph(
            namespace: activityMorph,
            state: NotchMorphState(
                isExpanded: isExpanded,
                wingFeatureID: wingsActivity.flatMap { $0.morphsIntoTab ? $0.featureID : nil },
                shownTabID: model.detail == nil ? model.selectedTab?.id : nil
            )
        )

        // The expanded panel is the overlay below, which outlives the state; the
        // activity's wings are the overlay above it.
        Color.clear
        .frame(width: model.islandSize.width, height: model.islandSize.height, alignment: .top)
        .overlay(alignment: .top) {
            if model.isExpandedContentMounted {
                ExpandedIslandView(model: model, activityMorph: morph, trailingTabRowScroll: trailingTabRowScroll)
                    // Laid out at the expanded size even while the outline is
                    // smaller, so nothing reflows as the island opens or closes.
                    // Its width follows the selected tab, which opening and
                    // closing leave alone.
                    .frame(width: expandedIslandWidth, height: NotchTheme.expandedSize.height)
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
        // The band, over the expanded panel and kept while it is open (retracted),
        // so it moves with the outline as the island opens and closes.
        .overlay(alignment: .top) {
            if let activity = rimActivity, let rim = activity.rim {
                ActivityRimView(
                    rim: rim,
                    isRetracted: isRimRetracted,
                    topCornerRadius: model.topCornerRadius,
                    bottomCornerRadii: model.bottomCornerRadii
                )
                // Clicks go to the island beneath, which expands.
                .allowsHitTesting(false)
                .id("\(activity.featureID).\(activity.id)")
                .transition(.blurReplace)
            }
        }
        // Over the expanded panel and outside its drop, so heroes kept while it
        // opens fly above it without rising, blurring, or fading with it; still
        // inside the outline's clip.
        .overlay(alignment: .top) {
            if let activity = wingsActivity {
                ActivityWingsView(
                    activity: activity,
                    notchSize: model.geometry.notchRect.size,
                    earInset: model.topCornerRadius,
                    islandOffset: model.islandOffset
                )
                .environment(\.notchIsHovered, model.isHovered)
                .environment(\.notchActivityMorph, morph)
                // A new activity replaces the old one with a blur instead of a cut.
                .id("\(activity.featureID).\(activity.id)")
                .transition(.blurReplace)
            }
        }
        .background {
            shape.fill(NotchTheme.islandColor)
            // Under the content: it lights the island, not the cards on it.
            // Mounted only while it shows, so its minute timer and blurs do not
            // redraw the collapsed or hovered island.
            if isExpanded && NotchAppearance.shared.isLightAndColorEnabled {
                IslandGlow(topCornerRadius: model.topCornerRadius, bottomCornerRadius: model.bottomCornerRadius)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        // Cast by the outline alone, under the island, not by the content: on
        // macOS 26 a shadow derived from the content was partly erased and then
        // cut off as the glow, clock, or glass redrew.
        .background {
            // The hovered ring casts a lighter, tighter shadow than the expanded panel.
            shape
                .fill(NotchTheme.islandColor)
                .shadow(
                    color: .black.opacity(isExpanded ? 0.5 : model.isHovered ? 0.35 : 0),
                    radius: isExpanded ? NotchTheme.expandedShadowRadius : 8,
                    y: isExpanded ? NotchTheme.expandedShadowOffset : 4
                )
        }
        // The whole outline takes clicks, including the empty collapsed body.
        // The panel only passes them on while the island is hovered or expanded.
        .contentShape(shape)
        .gesture(
            TapGesture().onEnded { model.setExpanded(true) },
            // Expanded: clicks belong to the controls inside.
            including: isExpanded ? .subviews : .all
        )
        .contextMenu {
            // Read inside the menu's builder, so the entries follow the features'
            // state and the interface language.
            let groups = model.menuGroups
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                FeatureMenuEntries(items: groups[index])
            }
            if !groups.isEmpty {
                Divider()
            }
            Button(localized(en: "Settings…", zh: "设置…"), systemImage: "gearshape", action: openSettings)
            Divider()
            Button(localized(en: "Quit", zh: "退出"), systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        // Off the notch's center while the current activity's wings are unequal,
        // so the notch stays between them; the animations below carry the move.
        .offset(x: model.islandOffset)
        // Inner animations win when several values change at once, so expanding
        // the hovered island (which also clears the hover) uses `expandAnimation`.
        .animation(animation(for: model.state), value: model.state)
        .animation(NotchTheme.activityAnimation, value: model.currentActivity.map(ActivityLayoutKey.init))
        .animation(model.isHovered ? NotchTheme.hoverAnimation : NotchTheme.collapseAnimation, value: model.isHovered)
        // A tab switch animates the width with its own transaction; this covers
        // the selected tab asking for another width, e.g. Home gaining a module
        // in the settings window while the island is open.
        .animation(NotchTheme.tabSwitchAnimation, value: model.expandedBodyWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The panel overlaps the notch; without this SwiftUI would push content below it.
        .ignoresSafeArea()
    }

    /// Frame width of the expanded island, ears included, at the selected tab's width.
    private var expandedIslandWidth: CGFloat {
        NotchShape.frameWidth(bodyWidth: model.expandedBodyWidth, topCornerRadius: NotchTheme.expandedTopRadius)
    }

    private func animation(for state: NotchViewModel.State) -> Animation {
        switch state {
        case .expanded: NotchTheme.expandAnimation
        case .collapsed: NotchTheme.collapseAnimation
        case .activity: NotchTheme.activityAnimation
        }
    }
}

/// What the island's activity animation follows: which activity is current, and
/// its wings' widths, which also change when an activity is presented again under
/// its id (a notification with shorter text replacing one still showing).
private struct ActivityLayoutKey: Equatable {
    let id: String
    let leadingWingWidth: CGFloat
    let trailingWingWidth: CGFloat

    @MainActor
    init(_ activity: NotchActivity) {
        id = "\(activity.featureID).\(activity.id)"
        let wings = NotchViewModel.wingWidths(of: activity)
        leadingWingWidth = wings.leading
        trailingWingWidth = wings.trailing
    }
}

/// Entries a feature adds to the right-click menu, submenus drawn recursively.
private struct FeatureMenuEntries: View {
    let items: [NotchMenuItem]

    var body: some View {
        ForEach(items.indices, id: \.self) { index in
            FeatureMenuEntry(item: items[index])
        }
    }
}

private struct FeatureMenuEntry: View {
    let item: NotchMenuItem

    var body: some View {
        switch item.kind {
        case .action(let action):
            if let symbol = item.symbol {
                Button(item.title, systemImage: symbol, action: action)
            } else {
                Button(item.title, action: action)
            }
        case .submenu(let items):
            Menu {
                FeatureMenuEntries(items: items)
            } label: {
                if let symbol = item.symbol {
                    Label(item.title, systemImage: symbol)
                } else {
                    Text(item.title)
                }
            }
        case .divider:
            Divider()
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

/// The expanded island's edge, lit by the sky (`SkyLight`): a soft halo for the
/// sun along the sides and bottom, and one for the moon along the top. The
/// island's clip keeps only the part of each halo inside the edge.
private struct IslandGlow: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    /// Where the sun's path meets the moon's on either side, as a share of the
    /// island's height: below the tab buttons.
    private static let horizon: CGFloat = 0.3

    /// A halo's layers, widest and faintest first; stacked, they fade out along
    /// and away from the edge. `spread` is a share of the path on either side of
    /// the halo's position; it and `lineWidth` scale with the halo's size.
    private static let layers: [(spread: Double, lineWidth: CGFloat, blur: CGFloat, opacity: Double)] = [
        (0.16, 56, 36, 0.3),
        (0.07, 36, 22, 0.3),
    ]

    var body: some View {
        // Redrawn every minute; the light moves too little in a minute to see a step.
        TimelineView(.everyMinute) { context in
            let light = SkyLight.at(context.date, sunTimes: Daylight.shared.sunTimes)
            ZStack {
                halo(light.sun, along: .lower)
                halo(light.moon, along: .upper)
            }
            // New sun times ease in rather than jump.
            .animation(.smooth(duration: 1), value: light)
        }
    }

    @ViewBuilder
    private func halo(_ halo: SkyLight.Halo, along arc: NotchEdge.Arc) -> some View {
        if halo.strength > 0 {
            let edge = NotchEdge(
                arc: arc,
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                horizon: Self.horizon
            )
            let color = Color(halo.color)
            ZStack {
                ForEach(Self.layers.indices, id: \.self) { index in
                    let layer = Self.layers[index]
                    let spread = layer.spread * halo.size
                    edge
                        .trim(
                            from: min(max(halo.position - spread, 0), 1),
                            to: min(max(halo.position + spread, 0), 1)
                        )
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: layer.lineWidth * CGFloat(halo.size), lineCap: .round)
                        )
                        .blur(radius: layer.blur)
                        .opacity(layer.opacity * halo.strength)
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
    /// The island's own offset from the notch's center (`NotchViewModel.islandOffset`).
    let islandOffset: CGFloat

    var body: some View {
        let wings = NotchViewModel.wingWidths(of: activity)
        HStack(spacing: 0) {
            activity.leading
                .frame(width: wings.leading, alignment: .center)
            // Nothing is visible behind the camera housing. Never hit, either:
            // wings kept over the open panel sit where its tab buttons are.
            Color.clear
                .frame(width: notchSize.width)
                .allowsHitTesting(false)
            activity.trailing
                .frame(width: wings.trailing, alignment: .center)
        }
        .frame(height: notchSize.height)
        .foregroundStyle(NotchTheme.primaryText)
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, earInset)
        // Unequal wings, centered on the island, put the gap off the notch by half
        // their difference; the island's own offset makes up for that while it is
        // theirs, and this the rest (over the open panel, which is centered).
        .offset(x: (wings.trailing - wings.leading) / 2 - islandOffset)
    }
}

/// An activity's band of light (`NotchActivityRim`): the lower arc of the island's
/// outline, just inside the edge and following its current corners, showing the
/// rim's fraction of it. Redrawn on every whole second, each step easing linearly
/// over the second toward where the band will be at its end, so the band retracts
/// smoothly; steps too small to see are drawn without animation, so a long timer
/// does not keep the island redrawing at display rate. The island's clip keeps
/// the glow inside.
///
/// Retracted, the band shrinks into its right end, just below the right ear, as
/// it does over time, and fades as it gets there; the outline's own animation
/// (opening, closing, another activity's wings) carries the move.
private struct ActivityRimView: View {
    let rim: NotchActivityRim
    let isRetracted: Bool
    let topCornerRadius: CGFloat
    let bottomCornerRadii: CGSize

    private static let lineWidth: CGFloat = 3
    /// The least change in the band's length, in points, that a step animates.
    private static let animatedStep: CGFloat = 1
    /// Retracting, the band fades late, near its end, where its round cap would
    /// otherwise stay as a dot; returning, it shows at once.
    private static let retractFade = Animation.easeIn(duration: 0.3)
    private static let returnFade = Animation.easeOut(duration: 0.12)
    /// Ticks on whole seconds whenever the view appears, so redraws that are not
    /// ticks (a hover changing the corners) see the same date and the same fraction.
    private static let schedule = PeriodicTimelineSchedule(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)

    var body: some View {
        // Insetting the path by half the stroke keeps the whole band inside the
        // outline; the corners shrink by as much, so they stay concentric with it.
        let inset = Self.lineWidth / 2
        let edge = NotchEdge(
            arc: .lower,
            topCornerRadius: topCornerRadius,
            bottomCornerRadii: CGSize(
                width: max(bottomCornerRadii.width - inset, 0),
                height: max(bottomCornerRadii.height - inset, 0)
            ),
            horizon: 0
        )
        GeometryReader { proxy in
            TimelineView(Self.schedule) { context in
                // Aimed at the end of the second this tick starts, which the step
                // reaches as the next tick arrives.
                let fraction = clamped(rim.fraction(context.date.addingTimeInterval(1)))
                let previous = clamped(rim.fraction(context.date))
                // About the arc's length: down both sides and across the bottom.
                let arcLength = proxy.size.height * 2 + proxy.size.width
                let animates = abs(fraction - previous) * arcLength >= Self.animatedStep
                let band = edge.trim(from: isRetracted ? 1 : 1 - fraction, to: 1)
                ZStack {
                    if NotchAppearance.shared.isLightAndColorEnabled {
                        band
                            .stroke(rim.color, style: StrokeStyle(lineWidth: Self.lineWidth * 3, lineCap: .round))
                            .blur(radius: 6)
                            .opacity(0.6)
                    }
                    band
                        .stroke(rim.color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                }
                .padding(.horizontal, inset)
                .padding(.bottom, inset)
                .animation(isRetracted ? Self.retractFade : Self.returnFade) {
                    $0.opacity(isRetracted ? 0 : 1)
                }
                .opacity(rim.isDimmed() ? 0.45 : 1)
                .animation(animates ? .linear(duration: 1) : nil, value: fraction)
            }
        }
    }

    private func clamped(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}

/// The expanded panel: a header row with tab buttons, and the selected feature's
/// view below; or, with a detail, that view alone below an empty header band.
/// Quitting lives in the island's right-click menu.
private struct ExpandedIslandView: View {
    let model: NotchViewModel
    /// Set on every tab's content, so a tab can leave its places to the heroes
    /// that fly in from an activity's wings.
    let activityMorph: NotchActivityMorph
    let trailingTabRowScroll: TrailingTabRowScroll
    /// Shared by the tab buttons and the selection highlight that slides between them.
    @Namespace private var tabSelection
    /// Shared by the views in different tabs that grow into one another (`notchTabMorph`).
    @Namespace private var tabMorph

    /// The most right-side tab buttons the open row shows at once; it scrolls
    /// sideways to the others. At the standard width, more would reach under the
    /// hardware notch, which hides the leftmost one's selection.
    static let maximumVisibleTrailingTabs = 4
    private static let tabButtonSpacing: CGFloat = 6
    /// Room around the right-side buttons inside their scroll view, so its clip
    /// never cuts into a button at rest or into the selection's glass.
    private static let trailingRowMargin: CGFloat = 8
    /// Between the right-side buttons and the scroll indicator below them.
    private static let scrollIndicatorGap: CGFloat = 4

    /// Visible tabs in header order, left to right.
    private var orderedTabs: [NotchViewModel.Tab] {
        let tabs = model.visibleTabs
        return tabs.filter { $0.placement == .leading } + tabs.filter { $0.placement == .trailing }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let detail = model.detail {
                // Keeps the detail clear of the hardware notch, where the tab buttons would be.
                Color.clear
                    .frame(height: headerHeight)
                detail.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A new detail replaces the old one's views rather than updating them.
                    .id(detail.sequence)
            } else {
                header
                content
            }
        }
        .foregroundStyle(NotchTheme.primaryText)
        // The expanded radius, not the current one: the content stays on screen
        // while the island collapses.
        .padding(.horizontal, NotchTheme.expandedTopRadius + NotchTheme.contentPadding)
        .padding(.bottom, NotchTheme.contentPadding)
        // Also catches a tab's availability putting another tab in the selected
        // one's place, which leaves `selectedTabID` alone.
        .onChange(of: model.selectedTab?.id) {
            model.shownTabDidChange()
        }
    }

    /// Sits in the same band as the hardware notch, so the tab buttons stay clear
    /// of it: leading tabs to its left, trailing tabs to its right. The trailing
    /// tabs are one button at the header's right end (`trailingRepresentative`),
    /// spread into a row to its left while the pointer is on it, which shows at
    /// most `maximumVisibleTrailingTabs` of them and scrolls to the rest.
    private var header: some View {
        HStack(spacing: 0) {
            tabButtons(model.visibleTabs.filter { $0.placement == .leading })
            Spacer(minLength: model.geometry.notchRect.width)
            trailingTabGroup
        }
        .frame(height: headerHeight)
    }

    /// Always in a scroll view, open or folded, so opening and closing only change
    /// its width and buttons; it scrolls only while the open row has more buttons
    /// than it shows. A scroll comes to rest on whole buttons, and the indicator
    /// below shows that the row scrolls and where it is.
    private var trailingTabGroup: some View {
        let isOpen = model.isTrailingTabGroupOpen
        let tabs = isOpen ? model.trailingTabRow : model.trailingRepresentative.map { [$0] } ?? []
        let overflows = tabs.count > Self.maximumVisibleTrailingTabs
        let margin = Self.trailingRowMargin
        let width = Self.rowWidth(buttons: min(tabs.count, Self.maximumVisibleTrailingTabs))
        let scroll = trailingTabRowScroll
        return ScrollView(.horizontal) {
            tabButtons(tabs, transition: .opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
                .padding(margin)
        }
        // On the row's right end, where the representative is, when it opens; and
        // that end stays put as the row widens, narrows, or gains a tab at its left.
        .defaultScrollAnchor(.trailing)
        .scrollTargetBehavior(TabSlotScrollBehavior(slot: TabButton.size + Self.tabButtonSpacing))
        .scrollIndicators(.never)
        .scrollDisabled(!overflows)
        .onScrollGeometryChange(for: CGFloat.self, of: Self.scrolledFraction) { _, fraction in
            scroll.fraction = fraction
        }
        .frame(width: width + margin * 2, height: TabButton.size + margin * 2)
        // Laid out as the buttons alone, so they keep their places in the header.
        .padding(-margin)
        .overlay(alignment: .bottom) {
            if overflows {
                TrailingRowScrollIndicator(
                    scroll: scroll,
                    visibleShare: CGFloat(Self.maximumVisibleTrailingTabs) / CGFloat(tabs.count)
                )
                .offset(y: Self.scrollIndicatorGap + TrailingRowScrollIndicator.height)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onHover { model.setTrailingTabGroupHovered($0) }
        // Spreads out like the hovered island grows, and folds back as it shrinks.
        .animation(isOpen ? NotchTheme.hoverAnimation : NotchTheme.collapseAnimation, value: isOpen)
    }

    /// Width of `buttons` tab buttons side by side.
    private static func rowWidth(buttons: Int) -> CGFloat {
        guard buttons > 0 else { return 0 }
        return CGFloat(buttons) * TabButton.size + CGFloat(buttons - 1) * tabButtonSpacing
    }

    /// How far the right-side row is scrolled: 0 at its left end, 1 at its right
    /// end, and 1 while it does not scroll.
    nonisolated private static func scrolledFraction(_ geometry: ScrollGeometry) -> CGFloat {
        let insets = geometry.contentInsets
        let range = geometry.contentSize.width + insets.leading + insets.trailing - geometry.containerSize.width
        guard range > 0 else { return 1 }
        return min(max((geometry.contentOffset.x + insets.leading) / range, 0), 1)
    }

    private var headerHeight: CGFloat {
        max(model.geometry.notchRect.height, 30)
    }

    /// One side's buttons. Only the selected button has a glass background: one
    /// view per side that slides between that side's buttons, and fades out on one
    /// side and in on the other when the selection crosses the notch.
    /// `transition` brings buttons in and out as the right-side row opens and closes.
    private func tabButtons(_ tabs: [NotchViewModel.Tab], transition: AnyTransition = .opacity) -> some View {
        let selectedID = model.selectedTab?.id
        return HStack(spacing: Self.tabButtonSpacing) {
            ForEach(tabs) { tab in
                TabButton(
                    symbol: tab.symbol(),
                    icon: tab.icon,
                    isSelected: tab.id == selectedID,
                    help: tab.title()
                ) {
                    withAnimation(NotchTheme.tabSwitchAnimation) {
                        model.selectedTabID = tab.id
                    }
                }
                // In the scrolling right-side row, a button shrinks and fades as it
                // slides out past the row's ends. The buttons left of the notch are
                // in no scroll view and stay as they are.
                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                    content
                        .opacity(1 - abs(phase.value) * 0.7)
                        .scaleEffect(1 - abs(phase.value) * 0.3)
                }
                .matchedGeometryEffect(id: tab.id, in: tabSelection)
                .transition(transition)
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
    /// switch each view slides toward its own side of the newly selected tab;
    /// views tied with `notchTabMorph` grow into one another instead.
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
                        .environment(
                            \.notchTabMorph,
                            NotchTabMorph(namespace: tabMorph, tabID: tab.id, shownTabID: tabs[selectedIndex].id)
                        )
                        .environment(\.notchActivityMorph, activityMorph)
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

/// A tab's icon: the feature's own view when it draws one, else its symbol. It
/// draws no background of its own; the selected tab's glass highlight belongs to
/// the header.
private struct TabButton: View {
    let symbol: String
    let icon: AnyView?
    let isSelected: Bool
    let help: String
    let action: () -> Void

    /// Width and height, which the selection's glass circle takes too.
    static let size: CGFloat = 28

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    icon.environment(\.notchTabIsSelected, isSelected)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// How far the header's right-side row is scrolled, for its scroll indicator.
@MainActor
@Observable
final class TrailingTabRowScroll {
    /// 0 with the row at its left end; 1 at its right end, or while it does not scroll.
    var fraction: CGFloat = 1
}

/// Brings a scroll of the right-side row to rest with whole buttons in view: on
/// a multiple of `slot`, one button and the gap after it.
private struct TabSlotScrollBehavior: ScrollTargetBehavior {
    let slot: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let range = max(context.contentSize.width - context.containerSize.width, 0)
        let resting = (target.rect.minX / slot).rounded() * slot
        target.rect.origin.x = min(max(resting, 0), range)
    }
}

/// Under the right-side row while it has more buttons than it shows: a short
/// track with a thumb as long as the share of the buttons in view, which moves
/// along with the scroll as a scroll bar's would. Faint, so it reads as a hint
/// rather than a control.
private struct TrailingRowScrollIndicator: View {
    let scroll: TrailingTabRowScroll
    /// The share of the row's buttons in view, below 1.
    let visibleShare: CGFloat

    static let height: CGFloat = 3
    private static let trackWidth: CGFloat = 32

    var body: some View {
        let thumbWidth = Self.trackWidth * visibleShare
        Capsule()
            .fill(Color.white.opacity(0.15))
            .frame(width: Self.trackWidth, height: Self.height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(NotchTheme.secondaryText)
                    .frame(width: thumbWidth)
                    .offset(x: (Self.trackWidth - thumbWidth) * scroll.fraction)
            }
    }
}
