import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Connection
    @State private var gatewayURL: String = ""
    @State private var token: String = ""
    @State private var sessionKey: String = ""

    // Agent Avatar
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?

    // Bot Identity (synced with IDENTITY.md)
    @State private var botName: String = ""
    @State private var botCreature: String = ""
    @State private var botVibe: String = ""
    @State private var botEmoji: String = ""

    // User Profile (synced with USER.md)
    @State private var userName: String = ""
    @State private var userCallName: String = ""
    @State private var userPronouns: String = ""
    @State private var userTimezone: String = ""
    @State private var userNotes: String = ""
    @State private var userContext: String = ""

    var currentIdentity: BotIdentity = BotIdentity()
    var currentProfile: UserProfile = UserProfile()
    var onSave: ((BotIdentity, UserProfile) -> Void)?
    var onClearHistory: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Connection

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

                // MARK: - Agent Identity (IDENTITY.md)

                Section {
                    TextField("Name", text: $botName)
                    TextField("Creature (AI, robot, familiar...)", text: $botCreature)
                    TextField("Vibe (warm, sharp, chaotic...)", text: $botVibe)
                    TextField("Emoji", text: $botEmoji)
                } header: {
                    Text("Agent Identity")
                } footer: {
                    Text("Synced with IDENTITY.md on the gateway.")
                }

                // MARK: - Agent Avatar

                Section("Agent Avatar") {
                    HStack {
                        if let avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(red: 219/255, green: 84/255, blue: 75/255))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "camera")
                                        .foregroundStyle(.white)
                                )
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                Text("Choose Photo")
                            }

                            if avatarImage != nil {
                                Button("Remove", role: .destructive) {
                                    avatarImage = nil
                                    avatarItem = nil
                                    LocalStorage.deleteAvatar()
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - About You (USER.md)

                Section {
                    TextField("Name", text: $userName)
                        .textContentType(.name)
                    TextField("What to call you", text: $userCallName)
                    TextField("Pronouns", text: $userPronouns)
                    TextField("Timezone", text: $userTimezone)
                    TextField("Notes", text: $userNotes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("About You")
                } footer: {
                    Text("Synced with USER.md on the gateway. OpenClaw uses this to personalize responses.")
                }

                Section {
                    TextField("Context, preferences, interests...", text: $userContext, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Context")
                } footer: {
                    Text("What do you care about? What projects are you working on? Build this over time.")
                }

                // MARK: - Data

                Section("Data") {
                    Button("Clear Chat History", role: .destructive) {
                        onClearHistory?()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Save connection config
                        var config = ConnectionConfig()
                        config.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        config.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        config.sessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Save avatar locally
                        if let avatarImage {
                            LocalStorage.saveAvatar(avatarImage)
                        }

                        // Build updated identity and profile, write to gateway
                        let identity = BotIdentity(
                            name: botName.trimmingCharacters(in: .whitespacesAndNewlines),
                            creature: botCreature.trimmingCharacters(in: .whitespacesAndNewlines),
                            vibe: botVibe.trimmingCharacters(in: .whitespacesAndNewlines),
                            emoji: botEmoji.trimmingCharacters(in: .whitespacesAndNewlines),
                            avatar: currentIdentity.avatar  // preserve existing avatar path
                        )

                        let profile = UserProfile(
                            name: userName.trimmingCharacters(in: .whitespacesAndNewlines),
                            callName: userCallName.trimmingCharacters(in: .whitespacesAndNewlines),
                            pronouns: userPronouns.trimmingCharacters(in: .whitespacesAndNewlines),
                            timezone: userTimezone.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: userNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                            context: userContext.trimmingCharacters(in: .whitespacesAndNewlines)
                        )

                        onSave?(identity, profile)
                        dismiss()
                    }
                    .disabled(gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: avatarItem) {
                Task {
                    if let data = try? await avatarItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatarImage = image
                    }
                }
            }
            .onAppear {
                // Load connection config
                let config = ConnectionConfig()
                gatewayURL = config.gatewayURL
                token = config.token
                sessionKey = config.sessionKey

                // Load avatar
                avatarImage = LocalStorage.loadAvatar()

                // Load bot identity (from gateway-synced cache)
                botName = currentIdentity.name
                botCreature = currentIdentity.creature
                botVibe = currentIdentity.vibe
                botEmoji = currentIdentity.emoji

                // Load user profile (from gateway-synced cache)
                userName = currentProfile.name
                userCallName = currentProfile.callName
                userPronouns = currentProfile.pronouns
                userTimezone = currentProfile.timezone
                userNotes = currentProfile.notes
                userContext = currentProfile.context
            }
        }
    }
}
