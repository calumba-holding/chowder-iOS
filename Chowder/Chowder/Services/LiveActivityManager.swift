import ActivityKit
import Foundation

/// Manages the Live Activity that shows agent thinking steps on the Lock Screen.
final class LiveActivityManager: @unchecked Sendable {

    static let shared = LiveActivityManager()

    private var currentActivity: Activity<ChowderActivityAttributes>?
    /// When the current intent started (reset when intent text changes).
    private var intentStartDate: Date = Date()
    /// Last known current intent (tracked to know when it changes for the timer).
    private var lastIntentText: String = ""
    /// Last known state for use in endActivity.
    private var lastState: ChowderActivityAttributes.ContentState?
    /// Latched subject -- set from the first thinking summary, never overwritten.
    private var latchedSubject: String?

    private init() {}

    // MARK: - Public API

    /// Start a new Live Activity when the user sends a message.
    func startActivity(agentName: String, userTask: String) {
        if currentActivity != nil {
            endActivity()
        }

        intentStartDate = Date()
        lastIntentText = ""
        lastState = nil
        latchedSubject = nil

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚡ Live Activities not enabled — skipping")
            return
        }

        let truncatedTask = userTask.count > 60
            ? String(userTask.prefix(57)) + "..."
            : userTask

        let attributes = ChowderActivityAttributes(
            agentName: agentName,
            userTask: truncatedTask
        )
        let initialState = ChowderActivityAttributes.ContentState(
            subject: nil,
            currentIntent: "Thinking...",
            previousIntent: "Thinking...",
            secondPreviousIntent: "Message received",
            intentStartDate: Date(),
            stepNumber: 1,
            costTotal: nil,
            isFinished: false
        )
        lastState = initialState
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

    /// Update the Live Activity with new intent data.
    func update(
        subject: String?,
        currentIntent: String,
        previousIntent: String?,
        secondPreviousIntent: String?,
        stepNumber: Int,
        costTotal: String?
    ) {
        guard let _ = currentActivity else { return }

        // Latch subject on first non-nil value
        if latchedSubject == nil, let subject {
            latchedSubject = subject
        }

        // Reset the timer when the intent text changes
        if currentIntent != lastIntentText {
            lastIntentText = currentIntent
            intentStartDate = Date()
        }

        let state = ChowderActivityAttributes.ContentState(
            subject: latchedSubject,
            currentIntent: currentIntent,
            previousIntent: previousIntent,
            secondPreviousIntent: secondPreviousIntent,
            intentStartDate: intentStartDate,
            stepNumber: stepNumber,
            costTotal: costTotal,
            isFinished: false
        )
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await currentActivity?.update(content)
        }
    }

    /// End the Live Activity. Shows a brief "Done" state before dismissing.
    func endActivity() {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        let finalState = ChowderActivityAttributes.ContentState(
            subject: latchedSubject,
            currentIntent: "Done",
            previousIntent: lastState?.currentIntent,
            secondPreviousIntent: lastState?.previousIntent,
            intentStartDate: lastState?.intentStartDate ?? Date(),
            stepNumber: lastState?.stepNumber ?? 0,
            costTotal: lastState?.costTotal,
            isFinished: true
        )
        lastState = nil
        lastIntentText = ""
        latchedSubject = nil
        let content = ActivityContent(state: finalState, staleDate: nil)

        Task {
            await activity.end(content, dismissalPolicy: .after(.now + 8))
            print("⚡ Live Activity ended")
        }
    }
}
