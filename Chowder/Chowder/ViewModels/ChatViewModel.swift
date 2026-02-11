import SwiftUI

@Observable
final class ChatViewModel: ChatServiceDelegate {

    var messages: [Message] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var isConnected: Bool = false
    var showSettings: Bool = false
    var debugLog: [String] = []
    var showDebugLog: Bool = false

    private var chatService: ChatService?

    var isConfigured: Bool {
        ConnectionConfig().isConfigured
    }

    private func log(_ msg: String) {
        let entry = "[\(Date().formatted(.dateTime.hour().minute().second()))] \(msg)"
        print(entry)
        DispatchQueue.main.async {
            self.debugLog.append(entry)
        }
    }

    // MARK: - Actions

    func connect() {
        log("connect() called")
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

        messages.append(Message(role: .user, content: text))
        inputText = ""
        isLoading = true

        messages.append(Message(role: .assistant, content: ""))

        chatService?.send(text: text)
        log("chatService.send() called")
    }

    // MARK: - ChatServiceDelegate

    func chatServiceDidConnect() {
        log("CONNECTED")
        isConnected = true
    }

    func chatServiceDidDisconnect() {
        log("DISCONNECTED")
        isConnected = false
    }

    func chatServiceDidReceiveDelta(_ text: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }
        messages[lastIndex].content += text
    }

    func chatServiceDidFinishMessage() {
        log("message.done")
        isLoading = false
    }

    func chatServiceDidReceiveError(_ error: Error) {
        log("ERROR: \(error.localizedDescription)")
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].content.isEmpty {
            messages[lastIndex].content = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func chatServiceDidLog(_ message: String) {
        log("WS: \(message)")
    }
}
