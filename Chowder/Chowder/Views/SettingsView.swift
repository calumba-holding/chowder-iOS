import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var gatewayURL: String = ""
    @State private var token: String = ""
    @State private var sessionKey: String = ""

    var onSave: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    TextField("ws://100.x.y.z:18789", text: $gatewayURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Authentication") {
                    SecureField("Token", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Session") {
                    TextField("agent:main:main", text: $sessionKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var config = ConnectionConfig()
                        config.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        config.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        config.sessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave?()
                        dismiss()
                    }
                    .disabled(gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                let config = ConnectionConfig()
                gatewayURL = config.gatewayURL
                token = config.token
                sessionKey = config.sessionKey
            }
        }
    }
}
