import ActivityKit
import Foundation

/// Manages the Live Activity that shows agent thinking steps on the Lock Screen.
final class LiveActivityManager: @unchecked Sendable {

    static let shared = LiveActivityManager()

    private var currentActivity: Activity<ChowderActivityAttributes>?
    /// Accumulated completed step labels for the current run.
    private var completedStepLabels: [String] = []

    private init() {}

    // MARK: - Public API

    /// Start a new Live Activity when the user sends a message.
    /// - Parameters:
    ///   - agentName: The bot/agent display name.
    ///   - userTask: The message the user sent (truncated for display).
    func startActivity(agentName: String, userTask: String) {
        // End any stale activity from a previous run
        if currentActivity != nil {
            endActivity()
        }

        completedStepLabels = []

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚡ Live Activities not enabled — skipping")
            return
        }

        // Truncate the user task for the Lock Screen
        let truncatedTask = userTask.count > 60
            ? String(userTask.prefix(57)) + "..."
            : userTask

        let attributes = ChowderActivityAttributes(
            agentName: agentName,
            userTask: truncatedTask
        )
        let initialState = ChowderActivityAttributes.ContentState(
            currentStep: "Thinking...",
            completedSteps: [],
            isFinished: false
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("⚡ Live Activity started: \(currentActivity?.id ?? "?")")
        } catch {
            print("⚡ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    /// Update the Live Activity with a new current step and the latest completed steps.
    /// - Parameters:
    ///   - currentStep: Label of the step now in progress.
    ///   - completedSteps: Labels of all completed steps so far.
    func updateStep(_ currentStep: String, completedSteps: [String]) {
        guard let activity = currentActivity else { return }

        completedStepLabels = completedSteps

        let state = ChowderActivityAttributes.ContentState(
            currentStep: currentStep,
            completedSteps: completedSteps,
            isFinished: false
        )
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.update(content)
        }
    }

    /// End the Live Activity. Shows a brief "Done" state before dismissing.
    func endActivity() {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        let finalState = ChowderActivityAttributes.ContentState(
            currentStep: "Done",
            completedSteps: completedStepLabels,
            isFinished: true
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        completedStepLabels = []

        Task {
            await activity.end(content, dismissalPolicy: .after(.now + 8))
            print("⚡ Live Activity ended")
        }
    }
}
