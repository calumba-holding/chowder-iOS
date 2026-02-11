import Foundation

/// Represents one step the agent performed during a turn.
struct ActivityStep: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let type: StepType
    let label: String       // "Thinking", "Reading IDENTITY.md...", etc.
    var detail: String       // Full thinking text or tool path/args summary

    enum StepType {
        case thinking
        case toolCall
    }
}

/// Tracks all activity (thinking + tool calls) for a single agent turn.
/// Ephemeral — not persisted to disk.
struct AgentActivity {
    /// The label currently shown on the shimmer line.
    var currentLabel: String = ""

    /// Accumulated full thinking content from the turn.
    var thinkingText: String = ""

    /// Ordered history of all steps for the detail card.
    var steps: [ActivityStep] = []
}
