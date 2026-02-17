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
        /// Short subject line summarizing the task (latched from first thinking summary).
        var subject: String?
        /// The latest intent -- shown ALL CAPS at the bottom left.
        var currentIntent: String
        /// The previous intent -- shown with the yellow arrow + "..."
        var previousIntent: String?
        /// The 2nd most previous intent -- shown with grey checkmark, fading out.
        var secondPreviousIntent: String?
        /// When the current intent started -- used for the live timer.
        var intentStartDate: Date
        /// Total step number (completed + current).
        var stepNumber: Int
        /// Formatted cost string (e.g. "$0.0012"), nil until first usage event.
        var costTotal: String?
        /// Whether the agent has finished and the activity should dismiss.
        var isFinished: Bool
    }
}
