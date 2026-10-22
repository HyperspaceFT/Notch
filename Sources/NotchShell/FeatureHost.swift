import NotchKit
import SwiftUI

/// Owns the feature instances: activates them with a per-feature context,
/// collects their expanded-panel tabs, and routes their activities to the view model.
@MainActor
final class FeatureHost {
    private let model: NotchViewModel
    private var features: [any NotchFeature] = []
    private var contexts: [FeatureContext] = []

    init(model: NotchViewModel) {
        self.model = model
    }

    func start(features: [any NotchFeature]) {
        stop()

        var seenIDs = Set<String>()
        for feature in features {
            // Ids key activities and tabs; a duplicate would make them collide.
            assert(seenIDs.insert(feature.id).inserted, "Duplicate NotchFeature id: \(feature.id)")
            let context = FeatureContext(featureID: feature.id, model: model)
            contexts.append(context)
            feature.activate(context: context)
        }
        self.features = features

        model.setTabs(features.compactMap { feature in
            feature.makeExpandedView().map { view in
                NotchViewModel.Tab(id: feature.id, title: feature.title, symbol: feature.symbol, content: view)
            }
        })
    }

    func stop() {
        for feature in features {
            feature.deactivate()
        }
        for context in contexts {
            context.invalidate()
        }
        features = []
        contexts = []
        model.setTabs([])
    }
}

/// The `NotchContext` handed to one feature. Stamps that feature's id onto
/// everything it presents and stops forwarding once the feature is deactivated.
@MainActor
private final class FeatureContext: NotchContext {
    private let featureID: String
    private weak var model: NotchViewModel?

    init(featureID: String, model: NotchViewModel) {
        self.featureID = featureID
        self.model = model
    }

    func invalidate() {
        model = nil
    }

    func present(_ activity: NotchActivity) {
        var activity = activity
        activity.featureID = featureID
        model?.present(activity)
    }

    func dismiss(activityID: String) {
        model?.dismiss(activityID: activityID, featureID: featureID)
    }

    func requestExpand() {
        model?.requestExpand(tabID: featureID)
    }
}
