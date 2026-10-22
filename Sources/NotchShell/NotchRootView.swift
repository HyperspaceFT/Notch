import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// Root of the panel: the island, pinned to the top center of the fixed-size panel.
struct NotchRootView: View {
    let model: NotchViewModel

    var body: some View {
        let shape = NotchShape(
            topCornerRadius: model.topCornerRadius,
            bottomCornerRadius: model.bottomCornerRadius
        )
        let isExpanded = model.state == .expanded

        ZStack(alignment: .top) {
            switch model.state {
            case .collapsed:
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
            case .expanded:
                ExpandedIslandView(model: model)
                    .transition(.blurReplace(.upUp))
            }
        }
        .frame(width: model.islandSize.width, height: model.islandSize.height, alignment: .top)
        .background { shape.fill(NotchTheme.islandColor) }
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
            // Placeholder: there is no settings panel yet.
            Button("Settings…", systemImage: "gearshape") {}
            Divider()
            Button("Quit", systemImage: "power") {
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

    private func animation(for state: NotchViewModel.State) -> Animation {
        switch state {
        case .expanded: NotchTheme.expandAnimation
        case .collapsed: NotchTheme.collapseAnimation
        case .activity: NotchTheme.activityAnimation
        }
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

    var body: some View {
        VStack(spacing: 10) {
            header
            Group {
                if let tab = model.selectedTab {
                    tab.content
                        .id(tab.id)
                        .transition(.blurReplace)
                } else {
                    Text("没有可显示的内容")
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(NotchTheme.activityAnimation, value: model.selectedTabID)
        }
        .foregroundStyle(NotchTheme.primaryText)
        .padding(.horizontal, model.topCornerRadius + NotchTheme.contentPadding)
        .padding(.bottom, 14)
    }

    /// Sits in the same band as the hardware notch, so the tab buttons stay left of it.
    private var header: some View {
        HStack(spacing: 0) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(model.tabs) { tab in
                        GlassIconButton(
                            symbol: tab.symbol,
                            isSelected: tab.id == model.selectedTab?.id,
                            help: tab.title
                        ) {
                            model.selectedTabID = tab.id
                        }
                    }
                }
            }
            Spacer(minLength: model.geometry.notchRect.width)
        }
        .frame(height: max(model.geometry.notchRect.height, 30))
    }
}
