import Foundation
import UIKit

protocol ChatServiceDelegate: AnyObject {
    func chatServiceDidConnect()
    func chatServiceDidDisconnect()
    func chatServiceDidReceiveDelta(_ text: String)
    func chatServiceDidFinishMessage()
    func chatServiceDidReceiveError(_ error: Error)
    func chatServiceDidLog(_ message: String)
    func chatServiceDidReceiveThinkingDelta(_ text: String)
    func chatServiceDidReceiveToolEvent(name: String, path: String?)
    func chatServiceDidUpdateBotIdentity(_ identity: BotIdentity)
    func chatServiceDidUpdateUserProfile(_ profile: UserProfile)
    func chatServiceDidReceiveFinalContent(_ text: String)
}

final class ChatService: NSObject {

    weak var delegate: ChatServiceDelegate?

    private let gatewayURL: String
    private let token: String
    private let sessionKey: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var shouldReconnect = true
    private var isReconnecting = false
    private var hasSentConnectRequest = false

    /// Stable device identifier persisted across launches (used for device pairing).
    private let deviceId: String

    /// Monotonically increasing request ID counter.
    private var nextRequestId: Int = 1

    init(gatewayURL: String, token: String, sessionKey: String = "agent:main:main") {
        self.gatewayURL = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.sessionKey = sessionKey

        // Use identifierForVendor when available; fall back to a UUID persisted in UserDefaults.
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            self.deviceId = vendorId
        } else {
            let key = "com.chowder.deviceId"
            if let stored = UserDefaults.standard.string(forKey: key) {
                self.deviceId = stored
            } else {
                let generated = UUID().uuidString
                UserDefaults.standard.set(generated, forKey: key)
                self.deviceId = generated
            }
        }

        super.init()
        log("[INIT] gatewayURL=\(self.gatewayURL) sessionKey=\(self.sessionKey) tokenLength=\(token.count) deviceId=\(deviceId)")
    }

    private func log(_ msg: String) {
        print("🔌 \(msg)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.chatServiceDidLog(msg)
        }
    }

    /// Produce a one-line summary for incoming WebSocket frames instead of dumping raw JSON.
    /// Example: "[RECV] event agent/assistant seq=12" or "[RECV] res ok id=req-1"
    private func logCompactRecv(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("[RECV] (unparseable \(text.count) chars)")
            return
        }
        let frameType = json["type"] as? String ?? "?"
        switch frameType {
        case "event":
            let event = json["event"] as? String ?? "?"
            let payload = json["payload"] as? [String: Any]
            let stream = (payload?["stream"] as? String).map { "/\($0)" } ?? ""
            let state = (payload?["state"] as? String).map { "/\($0)" } ?? ""
            let seq = payload?["seq"] as? Int
            let seqStr = seq.map { " seq=\($0)" } ?? ""
            // Skip tick/health entirely — pure noise
            if event == "tick" || event == "health" { return }
            log("[RECV] event \(event)\(stream)\(state)\(seqStr)")
        case "res":
            let id = json["id"] as? String ?? "?"
            let ok = json["ok"] as? Bool ?? false
            log("[RECV] res \(ok ? "ok" : "err") id=\(id)")
        default:
            log("[RECV] \(frameType) (\(text.count) chars)")
        }
    }

    /// Generate a unique request ID for outbound `type:"req"` frames.
    private func makeRequestId() -> String {
        let id = nextRequestId
        nextRequestId += 1
        return "req-\(id)"
    }

    // MARK: - Connection

    func connect() {
        guard webSocketTask == nil else {
            log("[CONNECT] Skipped — webSocketTask already exists")
            return
        }
        shouldReconnect = true
        hasSentConnectRequest = false
        nextRequestId = 1

        // Build URL — only append ?client= if not already present
        let urlString: String
        if gatewayURL.contains("?") {
            urlString = gatewayURL
        } else {
            urlString = "\(gatewayURL)/?client=chowder-ios"
        }
        log("[CONNECT] Building URL from: \(urlString)")

        guard let url = URL(string: urlString) else {
            log("[CONNECT] ❌ Failed to create URL from: \(urlString)")
            delegate?.chatServiceDidReceiveError(ChatServiceError.invalidURL)
            return
        }

        log("[CONNECT] URL scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil") port=\(url.port ?? -1)")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        log("[CONNECT] Calling task.resume() ...")
        task.resume()
        log("[CONNECT] task.resume() called — waiting for didOpen")
    }

    func disconnect() {
        log("[DISCONNECT] Manual disconnect")
        shouldReconnect = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
    }

    // MARK: - Sending Messages

    func send(text: String) {
        guard isConnected else {
            log("[SEND] ⚠️ Not connected — dropping message")
            return
        }

        let requestId = makeRequestId()
        let idempotencyKey = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.send",
            "params": [
                "message": text,
                "sessionKey": sessionKey,
                "idempotencyKey": idempotencyKey
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        log("[SEND] Sending chat.send id=\(requestId) (\(text.count) chars)")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                self?.log("[SEND] ❌ Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.delegate?.chatServiceDidReceiveError(error)
                }
            } else {
                self?.log("[SEND] ✅ chat.send sent OK")
            }
        }
    }

    // MARK: - Private: Connect Handshake

    /// Send the `connect` request after receiving the gateway's challenge nonce.
    /// Protocol: https://docs.openclaw.ai/gateway/protocol
    private func sendConnectRequest(nonce: String) {
        let requestId = makeRequestId()
        // Valid client IDs: webchat-ui, openclaw-control-ui, webchat, cli,
        //   gateway-client, openclaw-macos, openclaw-ios, openclaw-android, node-host, test
        // Valid client modes: webchat, cli, ui, backend, node, probe, test
        // Device identity is schema-optional; omit until we implement keypair signing.
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "openclaw-ios",
                    "version": "1.0.0",
                    "platform": "ios",
                    "mode": "ui"
                ],
                "role": "operator",
                "scopes": ["operator.read", "operator.write"],
                "auth": [
                    "token": token
                ],
                "locale": Locale.current.identifier,
                "userAgent": "chowder-ios/1.0.0"
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let jsonString = String(data: data, encoding: .utf8) else {
            log("[AUTH] ❌ Failed to serialize connect request")
            return
        }

        log("[AUTH] Sending connect request: \(jsonString)")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                self?.log("[AUTH] ❌ Error sending connect: \(error.localizedDescription)")
            } else {
                self?.log("[AUTH] ✅ Connect request sent — waiting for hello-ok")
            }
        }
    }

    // MARK: - Private: Receive Loop

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // Compact log: just event type + stream (full payload available in Xcode console)
                    self.logCompactRecv(text)
                    self.handleIncomingMessage(text)
                case .data(let data):
                    self.log("[RECV] Data frame (\(data.count) bytes)")
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingMessage(text)
                    }
                @unknown default:
                    self.log("[RECV] ⚠️ Unknown frame type")
                }
                self.listenForMessages()

            case .failure(let error):
                let nsError = error as NSError
                self.log("[RECV] ❌ Error: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.chatServiceDidDisconnect()
                    self.delegate?.chatServiceDidReceiveError(error)
                }
                // didCloseWith may not fire after some errors (e.g. code 53 connection abort),
                // so trigger reconnect here as a safety net.
                self.attemptReconnect()
            }
        }
    }

    // MARK: - Private: Message Routing

    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("[PARSE] ⚠️ Could not parse: \(String(text.prefix(200)))")
            return
        }

        // OpenClaw Gateway protocol uses three frame types:
        //   "event"  — server push   {"type":"event","event":"...","payload":{...}}
        //   "res"    — response       {"type":"res","id":"...","ok":true/false,"payload/error":{...}}
        //   "req"    — (server->client, rare)
        let frameType = json["type"] as? String ?? "unknown"

        switch frameType {
        case "event":
            handleEvent(json)
        case "res":
            handleResponse(json)
        default:
            log("[HANDLE] Unhandled frame type: \(frameType)")
        }
    }

    /// Handle `type:"event"` frames from the gateway.
    private func handleEvent(_ json: [String: Any]) {
        let event = json["event"] as? String ?? "unknown"
        let payload = json["payload"] as? [String: Any]

        // connect.challenge must be handled immediately (not on main queue)
        if event == "connect.challenge" {
            guard !hasSentConnectRequest else {
                log("[AUTH] ⚠️ Ignoring duplicate connect.challenge")
                return
            }
            let nonce = payload?["nonce"] as? String
            if let nonce {
                log("[AUTH] Received connect.challenge — nonce=\(nonce.prefix(8))...")
                hasSentConnectRequest = true
                sendConnectRequest(nonce: nonce)
            } else {
                log("[AUTH] ⚠️ connect.challenge missing nonce")
            }
            return
        }

        // Filter session-scoped events BEFORE dispatching to main — the gateway
        // broadcasts to ALL connected WebSocket clients, so skip events whose
        // sessionKey doesn't match ours. This avoids unnecessary main-thread work.
        let eventSessionKey = payload?["sessionKey"] as? String
        if (event == "agent" || event == "chat"),
           let eventSessionKey,
           eventSessionKey != self.sessionKey {
            // This event belongs to a different session — ignore it silently.
            return
        }

        // Skip periodic keepalive and health events before touching the main thread.
        if event == "tick" || event == "health" {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch event {

            // ── Agent streaming events (primary source for text deltas) ──
            // payload.stream = "assistant" | "lifecycle" | "tool" | "thinking" | ...
            // For "assistant": data.delta = incremental text, data.text = cumulative text
            case "agent":
                let stream = payload?["stream"] as? String
                let agentData = payload?["data"] as? [String: Any]
                switch stream {
                case "assistant":
                    // Use data.delta (incremental) — NOT data.text (cumulative)
                    if let delta = agentData?["delta"] as? String, !delta.isEmpty {
                        self.delegate?.chatServiceDidReceiveDelta(delta)
                    }

                case "thinking":
                    if let delta = agentData?["delta"] as? String, !delta.isEmpty {
                        self.delegate?.chatServiceDidReceiveThinkingDelta(delta)
                    }

                case "tool":
                    // Log full payload for debugging the exact structure
                    self.log("[HANDLE] tool event data keys: \(Array((agentData ?? [:]).keys))")

                    // Try multiple possible field names for tool name and args
                    let toolName = agentData?["name"] as? String
                                ?? agentData?["toolName"] as? String
                                ?? agentData?["tool"] as? String
                                ?? "tool"
                    let args = agentData?["args"] as? [String: Any]
                             ?? agentData?["params"] as? [String: Any]
                             ?? agentData?["input"] as? [String: Any]
                    let path = args?["path"] as? String

                    // Notify delegate about tool usage (for shimmer display)
                    self.delegate?.chatServiceDidReceiveToolEvent(
                        name: toolName,
                        path: path
                    )

                    // Detect writes to identity/user files (for workspace sync)
                    if toolName == "write",
                       let filePath = path,
                       let content = args?["content"] as? String {
                        if filePath.hasSuffix("IDENTITY.md") {
                            let identity = BotIdentity.from(markdown: content)
                            self.log("[SYNC] Detected write to IDENTITY.md — name=\(identity.name)")
                            self.delegate?.chatServiceDidUpdateBotIdentity(identity)
                        } else if filePath.hasSuffix("USER.md") {
                            let profile = UserProfile.from(markdown: content)
                            self.log("[SYNC] Detected write to USER.md — name=\(profile.name)")
                            self.delegate?.chatServiceDidUpdateUserProfile(profile)
                        }
                    }

                case "lifecycle":
                    let phase = agentData?["phase"] as? String
                    if phase == "end" || phase == "done" {
                        self.log("[HANDLE] ✅ agent lifecycle: \(phase ?? "")")
                        self.delegate?.chatServiceDidFinishMessage()
                    }
                default:
                    break
                }

            // ── Chat events (used for error/abort only; deltas handled via agent events above) ──
            case "chat":
                let state = payload?["state"] as? String
                switch state {
                case "delta":
                    // Check if this delta contains a verbose tool summary
                    // (e.g. "📄 read: IDENTITY.md" sent by /verbose on).
                    // Tool summaries come as separate chat deltas, not agent deltas.
                    if let message = payload?["message"] as? [String: Any],
                       let text = self.extractText(from: message),
                       !text.isEmpty {
                        let parsed = Self.parseVerboseToolSummary(text)
                        if let (toolName, toolPath) = parsed {
                            self.log("[HANDLE] verbose tool: \(toolName) \(toolPath ?? "")")
                            self.delegate?.chatServiceDidReceiveToolEvent(name: toolName, path: toolPath)
                        }
                        // Don't deliver as a regular delta — agent/assistant handles that
                    }
                case "final":
                    // Extract full message text and deliver via delegate (used by sync session)
                    let message = payload?["message"] as? [String: Any]
                    self.log("[HANDLE] chat.final — message keys: \(Array((message ?? [:]).keys))")
                    if let message,
                       let fullText = self.extractText(from: message),
                       !fullText.isEmpty {
                        self.log("[HANDLE] chat.final — extracted \(fullText.count) chars: \(String(fullText.prefix(120)))...")
                        self.delegate?.chatServiceDidReceiveFinalContent(fullText)
                    } else {
                        self.log("[HANDLE] chat.final — ⚠️ could not extract text from message")
                    }
                case "aborted":
                    self.log("[HANDLE] ⚠️ chat aborted")
                    self.delegate?.chatServiceDidFinishMessage()
                case "error":
                    let msg = payload?["errorMessage"] as? String ?? "Chat error"
                    self.log("[HANDLE] ❌ Chat error: \(msg)")
                    self.delegate?.chatServiceDidReceiveError(ChatServiceError.gatewayError(msg))
                default:
                    break
                }

            case "error":
                let msg = payload?["message"] as? String ?? "Unknown gateway error"
                self.log("[HANDLE] ❌ Gateway error: \(msg)")
                self.delegate?.chatServiceDidReceiveError(ChatServiceError.gatewayError(msg))

            default:
                self.log("[HANDLE] Event: \(event)")
            }
        }
    }

    /// Handle `type:"res"` frames (responses to our requests).
    private func handleResponse(_ json: [String: Any]) {
        let id = json["id"] as? String ?? "?"
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any]
        let error = json["error"] as? [String: Any]

        if ok {
            let payloadType = payload?["type"] as? String

            if payloadType == "hello-ok" {
                let proto = payload?["protocol"] as? Int ?? 0
                log("[AUTH] ✅ hello-ok — protocol=\(proto) id=\(id)")

                DispatchQueue.main.async { [weak self] in
                    self?.isConnected = true
                    self?.delegate?.chatServiceDidConnect()
                }
                return
            }

            // Generic successful response (e.g. chat.send ack)
            log("[HANDLE] ✅ res ok id=\(id) payloadType=\(payloadType ?? "nil")")
        } else {
            // Error response
            let code = error?["code"] as? String ?? "unknown"
            let message = error?["message"] as? String ?? json["error"] as? String ?? "Request failed"
            log("[HANDLE] ❌ res error id=\(id) code=\(code) message=\(message)")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.chatServiceDidReceiveError(ChatServiceError.gatewayError("\(code): \(message)"))
            }
        }
    }

    // MARK: - Private: Text Extraction

    /// Extract displayable text from a message payload that could be:
    ///   - A plain String
    ///   - A dictionary with "text", "delta", or "content" key
    ///   - A structured message with content blocks [{type:"text", text:"..."}]
    private func extractText(from value: Any?) -> String? {
        if let str = value as? String, !str.isEmpty {
            return str
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String, !t.isEmpty { return t }
            if let d = dict["delta"] as? String, !d.isEmpty { return d }
            if let c = dict["content"] as? String, !c.isEmpty { return c }
            // Anthropic-style content blocks: [{type:"text", text:"..."}]
            if let blocks = dict["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                let joined = texts.joined()
                return joined.isEmpty ? nil : joined
            }
        }
        return nil
    }

    // MARK: - Private: Verbose Tool Summary Parsing

    /// Known tool names the agent can use (matched case-insensitively).
    private static let knownTools: Set<String> = [
        "read", "write", "edit", "apply_patch", "search",
        "bash", "exec", "browser", "web", "canvas",
        "llm_task", "agent_send", "sessions_list",
        "sessions_read", "message"
    ]

    /// Try to parse a verbose tool summary like "📄 read: IDENTITY.md" or "🔧 bash: ls -la".
    /// Returns (toolName, path/arg?) or nil if the text isn't a tool summary.
    static func parseVerboseToolSummary(_ text: String) -> (String, String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Verbose tool summaries follow the pattern: <emoji> <toolName>: <arg>
        // The emoji is optional (1–2 Unicode scalars), then a known tool name, then ": ".
        // Strategy: strip leading emoji characters, then look for "toolName: arg".
        var working = trimmed

        // Strip leading emoji (any character that is NOT alphanumeric or whitespace, up to 4 chars)
        while let first = working.unicodeScalars.first,
              !first.properties.isAlphabetic && !first.properties.isWhitespace,
              working.count > 1 {
            working = String(working.dropFirst())
        }
        working = working.trimmingCharacters(in: .whitespaces)

        // Now expect "toolName:" or "toolName: arg"
        guard let colonIndex = working.firstIndex(of: ":") else { return nil }
        let toolName = working[working.startIndex..<colonIndex]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        guard knownTools.contains(toolName) else { return nil }

        let arg = working[working.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)

        return (toolName, arg.isEmpty ? nil : arg)
    }

    // MARK: - Private: Reconnect

    private func attemptReconnect() {
        guard shouldReconnect, !isReconnecting else { return }
        isReconnecting = true
        log("[RECONNECT] Will retry in 3s ...")
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isReconnecting = false
            self?.log("[RECONNECT] Retrying now")
            self?.connect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ChatService: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("[SOCKET] ✅ didOpen — protocol=\(`protocol` ?? "none")")
        // Only listen — do NOT send anything. Wait for the gateway's connect.challenge event.
        listenForMessages()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        log("[SOCKET] ⚠️ didClose — code=\(closeCode.rawValue) reason=\(reasonStr)")
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.delegate?.chatServiceDidDisconnect()
        }
        attemptReconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let nsError = error as NSError
            log("[SOCKET] ❌ didCompleteWithError: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
        }
    }

    // Trust Tailscale's .ts.net TLS certificates
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let host = challenge.protectionSpace.host
        log("[TLS] Challenge for host=\(host) method=\(challenge.protectionSpace.authenticationMethod)")

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           host.hasSuffix(".ts.net"),
           let trust = challenge.protectionSpace.serverTrust {
            log("[TLS] Trusting .ts.net certificate for \(host)")
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

}

// MARK: - Errors

enum ChatServiceError: LocalizedError {
    case invalidURL
    case gatewayError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL."
        case .gatewayError(let msg): return msg
        }
    }
}
