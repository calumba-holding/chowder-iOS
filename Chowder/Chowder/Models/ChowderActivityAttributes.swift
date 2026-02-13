import ActivityKit
import Foundation

/// ActivityAttributes for the agent thinking steps Live Activity.
/// This file must be added to both the main app target and the widget extension target.
struct ChowderActivityAttributes: ActivityAttributes {
    /// Static context set when the activity starts (does not change).
    var agentName: String
    var userTask: String

    /// Dynamic state that updates as the agent works.
    struct ContentState: Codable, Hashable {
        /// The step currently in progress, e.g. "Reading IDENTITY.md..."
        var currentStep: String
        /// Labels of all completed steps, in order.
        var completedSteps: [String]
        /// Whether the agent has finished and the activity should dismiss.
        var isFinished: Bool
    }
}
