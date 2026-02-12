import SwiftUI
import UIKit

@Observable
final class ChatViewModel: ChatServiceDelegate {

    var messages: [Message] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var isConnected: Bool = false
    var showSettings: Bool = false
    var debugLog: [String] = []
    var showDebugLog: Bool = false

    // Workspace-synced data from the gateway
    var botIdentity: BotIdentity = LocalStorage.loadBotIdentity()
    var userProfile: UserProfile = LocalStorage.loadUserProfile()

    /// The bot's display name — uses IDENTITY.md name, falls back to "Chowder".
    var botName: String {
        botIdentity.name.isEmpty ? "Chowder" : botIdentity.name
    }

    /// Tracks the agent's current turn activity (thinking, tool calls) for the shimmer display.
    /// Set to a new instance when a turn starts; nil when the turn ends.
    var currentActivity: AgentActivity?

    /// Snapshot of the last completed activity, kept around so the user can still
    /// tap to view it after the shimmer disappears.
    var lastCompletedActivity: AgentActivity?

    /// Controls presentation of the activity detail card.
    var showActivityCard: Bool = false

    /// Minimum time (seconds) the shimmer should remain visible so it doesn't flash.
    private let shimmerMinDuration: TimeInterval = 0.8
    private var shimmerStartTime: Date?

    /// Light haptic fired once when the assistant's response starts streaming.
    @ObservationIgnored private let responseHaptic = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private var hasPlayedResponseHaptic = false

    private var chatService: ChatService?

    /// Tracks whether an invisible sync request is in flight on the main session.
    private enum SyncState { case none, reading, writing }
    private var syncState: SyncState = .none

    var isConfigured: Bool {
        ConnectionConfig().isConfigured
    }

    // MARK: - Buffered Debug Logging

    /// Buffer for log entries — not observed by SwiftUI, so appends here are free.
    @ObservationIgnored private var logBuffer: [String] = []
    /// Whether a flush is already scheduled.
    @ObservationIgnored private var logFlushScheduled = false
    /// Interval between buffer flushes (seconds).
    @ObservationIgnored private let logFlushInterval: TimeInterval = 0.5

    private func log(_ msg: String) {
        let entry = "[\(Date().formatted(.dateTime.hour().minute().second()))] \(msg)"
        print(entry)
        logBuffer.append(entry)
        scheduleLogFlush()
    }

    /// Schedule a single coalesced flush of buffered log entries to the observable `debugLog`.
    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + logFlushInterval) { [weak self] in
            self?.flushLogBuffer()
        }
    }

    /// Move all buffered entries into the observable `debugLog` in one batch.
    func flushLogBuffer() {
        logFlushScheduled = false
        guard !logBuffer.isEmpty else { return }
        debugLog.append(contentsOf: logBuffer)
        logBuffer.removeAll()
    }

    // MARK: - Actions

    func connect() {
        log("connect() called")

        // Restore chat history from disk on first launch
        if messages.isEmpty {
            messages = LocalStorage.loadMessages()
            if !messages.isEmpty {
                log("Restored \(messages.count) messages from disk")
            }
        }

        let config = ConnectionConfig()
        log("config — url=\(config.gatewayURL) tokenLen=\(config.token.count) session=\(config.sessionKey) configured=\(config.isConfigured)")
        guard config.isConfigured else {
            log("Not configured — showing settings")
            showSettings = true
            return
        }

        chatService?.disconnect()

        let service = ChatService(
            gatewayURL: config.gatewayURL,
            token: config.token,
            sessionKey: config.sessionKey
        )
        service.delegate = self
        self.chatService = service
        service.connect()
        log("ChatService.connect() called")
    }

    func reconnect() {
        log("reconnect()")
        chatService?.disconnect()
        chatService = nil
        isConnected = false
        connect()
    }

    func send() {
        log("send() — isConnected=\(isConnected) isLoading=\(isLoading)")
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        hasPlayedResponseHaptic = false
        responseHaptic.prepare()

        messages.append(Message(role: .user, content: text))
        inputText = ""
        isLoading = true

        // Start a fresh activity tracker for this agent turn
        currentActivity = AgentActivity()
        currentActivity?.currentLabel = "Thinking..."
        shimmerStartTime = Date()
        log("shimmer started — label=\"Thinking...\"")

        messages.append(Message(role: .assistant, content: ""))

        LocalStorage.saveMessages(messages)

        chatService?.send(text: text)
        log("chatService.send() called")
    }

    func clearMessages() {
        messages.removeAll()
        LocalStorage.deleteMessages()
        log("Chat history cleared")
    }

    // MARK: - ChatServiceDelegate (main chat session)

    func chatServiceDidConnect() {
        log("CONNECTED")
        isConnected = true
        enableVerboseMode()
    }

    /// Send `/verbose on` to enable tool call summaries in the chat stream,
    /// then chain into the workspace sync.
    private func enableVerboseMode() {
        guard chatService != nil, syncState == .none else {
            requestWorkspaceSync()
            return
        }
        syncState = .writing  // suppress the confirmation message from appearing
        pendingWorkspaceSync = true
        chatService?.send(text: "/verbose on")
        log("[SYNC] Sent /verbose on")
    }

    func chatServiceDidDisconnect() {
        log("DISCONNECTED")
        isConnected = false
    }

    func chatServiceDidReceiveDelta(_ text: String) {
        // Suppress deltas during invisible sync requests
        if syncState != .none { return }

        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }
        messages[lastIndex].content += text

        // Light haptic on the first streaming delta of a response
        if !hasPlayedResponseHaptic {
            hasPlayedResponseHaptic = true
            responseHaptic.impactOccurred()
        }

        // Hide the shimmer once text starts streaming — but respect minimum display time
        if currentActivity != nil, !(currentActivity?.currentLabel.isEmpty ?? true) {
            let elapsed = Date().timeIntervalSince(shimmerStartTime ?? .distantPast)
            if elapsed >= shimmerMinDuration {
                log("shimmer cleared — first delta received (after \(String(format: "%.2f", elapsed))s)")
                currentActivity?.currentLabel = ""
            } else {
                // Schedule clearing after the remaining minimum time
                let remaining = shimmerMinDuration - elapsed
                log("shimmer deferred — will clear in \(String(format: "%.2f", remaining))s")
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    guard let self, self.currentActivity != nil else { return }
                    self.log("shimmer cleared — min duration reached")
                    self.currentActivity?.currentLabel = ""
                }
            }
        }
    }

    func chatServiceDidFinishMessage() {
        // During sync, the lifecycle end fires before chat.final delivers the response.
        // Just log and let chatServiceDidReceiveFinalContent handle the rest.
        if syncState != .none {
            log("message.done (sync — suppressed)")
            return
        }

        log("message.done")
        isLoading = false

        // Preserve the activity for the detail card, then clear the shimmer
        if let activity = currentActivity {
            lastCompletedActivity = activity
        }
        currentActivity = nil
        shimmerStartTime = nil

        LocalStorage.saveMessages(messages)
    }

    func chatServiceDidReceiveError(_ error: Error) {
        log("ERROR: \(error.localizedDescription)")
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].content.isEmpty {
            messages[lastIndex].content = "Error: \(error.localizedDescription)"
        }
        isLoading = false
        currentActivity = nil
        LocalStorage.saveMessages(messages)
    }

    func chatServiceDidLog(_ message: String) {
        log("WS: \(message)")
    }

    func chatServiceDidReceiveThinkingDelta(_ text: String) {
        if currentActivity == nil { currentActivity = AgentActivity() }
        currentActivity?.thinkingText += text
        currentActivity?.currentLabel = "Thinking..."

        // Add or update the thinking step
        if let lastStep = currentActivity?.steps.last, lastStep.type == .thinking {
            currentActivity?.steps[currentActivity!.steps.count - 1].detail += text
        } else {
            currentActivity?.steps.append(
                ActivityStep(type: .thinking, label: "Thinking", detail: text)
            )
        }
    }

    func chatServiceDidReceiveToolEvent(name: String, path: String?) {
        if currentActivity == nil { currentActivity = AgentActivity() }

        // Build a human-readable label
        let label: String
        if let path {
            let fileName = (path as NSString).lastPathComponent
            switch name {
            case "write":  label = "Writing \(fileName)..."
            case "read":   label = "Reading \(fileName)..."
            case "search": label = "Searching..."
            case "bash":   label = "Running command..."
            default:       label = "\(name) \(fileName)..."
            }
        } else {
            switch name {
            case "bash":   label = "Running command..."
            case "search": label = "Searching..."
            default:       label = "Using \(name)..."
            }
        }

        currentActivity?.currentLabel = label
        currentActivity?.steps.append(
            ActivityStep(type: .toolCall, label: label, detail: path ?? "")
        )
    }

    /// Tracks whether we still need to run the workspace sync after /verbose on completes.
    private var pendingWorkspaceSync = false

    func chatServiceDidReceiveFinalContent(_ text: String) {
        switch syncState {
        case .reading:
            log("[SYNC] Final content received (\(text.count) chars)")
            syncState = .none
            handleSyncResponse(text)
        case .writing:
            log("[SYNC] Write/directive complete: \(String(text.prefix(80)))")
            syncState = .none
            // If this was the /verbose on confirmation, chain into workspace sync
            if pendingWorkspaceSync {
                pendingWorkspaceSync = false
                requestWorkspaceSync()
            }
        case .none:
            break // Normal chat — no-op (we use agent stream deltas)
        }
    }

    func chatServiceDidUpdateBotIdentity(_ identity: BotIdentity) {
        log("Bot identity updated via tool event — name=\(identity.name)")
        self.botIdentity = identity
        LocalStorage.saveBotIdentity(identity)
    }

    func chatServiceDidUpdateUserProfile(_ profile: UserProfile) {
        log("User profile updated via tool event — name=\(profile.name)")
        self.userProfile = profile
        LocalStorage.saveUserProfile(profile)
    }

    // MARK: - Workspace Sync (invisible requests on the main session)

    /// Ask the bot to read IDENTITY.md and USER.md on the main session.
    /// The request and response are invisible to the user (suppressed from the chat UI).
    func requestWorkspaceSync() {
        guard chatService != nil, syncState == .none else { return }

        syncState = .reading
        let prompt = """
        Read the files IDENTITY.md and USER.md from your workspace. \
        Return their raw contents in this exact format — no other commentary, no markdown fences:

        ---IDENTITY---
        [paste raw IDENTITY.md contents here]
        ---USER---
        [paste raw USER.md contents here]
        ---END---
        """
        chatService?.send(text: prompt)
        log("[SYNC] Sent read request on main session")
    }

    /// Send a workspace update on the main session (used by Settings save).
    func saveWorkspaceData(identity: BotIdentity, profile: UserProfile) {
        // Cache locally immediately
        self.botIdentity = identity
        self.userProfile = profile
        LocalStorage.saveBotIdentity(identity)
        LocalStorage.saveUserProfile(profile)

        guard chatService != nil, syncState == .none else { return }

        syncState = .writing
        let identityMd = identity.toMarkdown()
        let profileMd = profile.toMarkdown()
        let prompt = """
        Please update your workspace files with the following content:

        1. Write this to IDENTITY.md:
        ```
        \(identityMd)
        ```

        2. Write this to USER.md:
        ```
        \(profileMd)
        ```

        Just write the files, no other commentary needed.
        """
        chatService?.send(text: prompt)
        log("[SYNC] Sent write request on main session")
    }

    /// Parse the bot's sync response and update identity / profile caches.
    private func handleSyncResponse(_ text: String) {
        log("Sync response received (\(text.count) chars)")
        log("Sync response preview: \(String(text.prefix(300)))")

        // Strategy 1: Try delimiter-based format (---IDENTITY--- / ---USER--- / ---END---)
        if let identityRange = text.range(of: "---IDENTITY---"),
           let userRange = text.range(of: "---USER---") {
            let identityMd = String(text[identityRange.upperBound..<userRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let userEndIndex = text.range(of: "---END---")?.lowerBound ?? text.endIndex
            let userMd = String(text[userRange.upperBound..<userEndIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !identityMd.isEmpty {
                self.botIdentity = BotIdentity.from(markdown: identityMd)
                LocalStorage.saveBotIdentity(self.botIdentity)
                log("Synced IDENTITY.md via delimiters — name=\(self.botIdentity.name)")
            }
            if !userMd.isEmpty {
                self.userProfile = UserProfile.from(markdown: userMd)
                LocalStorage.saveUserProfile(self.userProfile)
                log("Synced USER.md via delimiters — name=\(self.userProfile.name)")
            }
            return
        }

        // Strategy 2: Try JSON format (legacy / fallback)
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let identityMd = json["identity"] as? String {
                self.botIdentity = BotIdentity.from(markdown: identityMd)
                LocalStorage.saveBotIdentity(self.botIdentity)
                log("Synced IDENTITY.md via JSON — name=\(self.botIdentity.name)")
            }
            if let userMd = json["user"] as? String {
                self.userProfile = UserProfile.from(markdown: userMd)
                LocalStorage.saveUserProfile(self.userProfile)
                log("Synced USER.md via JSON — name=\(self.userProfile.name)")
            }
            return
        }

        log("Sync response could not be parsed (neither delimiters nor JSON found)")
    }
}
