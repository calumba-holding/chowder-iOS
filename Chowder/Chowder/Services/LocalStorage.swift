import UIKit

/// Lightweight file-based persistence for user data.
/// All files live in the app's Documents directory.
/// When migrating to a backend, replace the implementations here.
enum LocalStorage {

    // MARK: - Directories

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Chat History

    private static var chatHistoryURL: URL {
        documentsURL.appendingPathComponent("chat_history.json")
    }

    static func saveMessages(_ messages: [Message]) {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: chatHistoryURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save messages: \(error)")
        }
    }

    static func loadMessages() -> [Message] {
        guard FileManager.default.fileExists(atPath: chatHistoryURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: chatHistoryURL)
            return try JSONDecoder().decode([Message].self, from: data)
        } catch {
            print("[LocalStorage] Failed to load messages: \(error)")
            return []
        }
    }

    static func deleteMessages() {
        try? FileManager.default.removeItem(at: chatHistoryURL)
    }

    // MARK: - Agent Avatar

    private static var avatarURL: URL {
        documentsURL.appendingPathComponent("agent_avatar.jpg")
    }

    static func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: avatarURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save avatar: \(error)")
        }
    }

    static func loadAvatar() -> UIImage? {
        guard FileManager.default.fileExists(atPath: avatarURL.path) else { return nil }
        return UIImage(contentsOfFile: avatarURL.path)
    }

    static func deleteAvatar() {
        try? FileManager.default.removeItem(at: avatarURL)
    }

    // MARK: - User Context (legacy local-only)

    private static var userContextURL: URL {
        documentsURL.appendingPathComponent("user_context.json")
    }

    static func saveUserContext(_ context: UserContext) {
        do {
            let data = try JSONEncoder().encode(context)
            try data.write(to: userContextURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save user context: \(error)")
        }
    }

    static func loadUserContext() -> UserContext {
        guard FileManager.default.fileExists(atPath: userContextURL.path) else { return UserContext() }
        do {
            let data = try Data(contentsOf: userContextURL)
            return try JSONDecoder().decode(UserContext.self, from: data)
        } catch {
            print("[LocalStorage] Failed to load user context: \(error)")
            return UserContext()
        }
    }

    static func deleteUserContext() {
        try? FileManager.default.removeItem(at: userContextURL)
    }

    // MARK: - Bot Identity (cache of IDENTITY.md)

    private static var botIdentityURL: URL {
        documentsURL.appendingPathComponent("bot_identity.json")
    }

    static func saveBotIdentity(_ identity: BotIdentity) {
        do {
            let data = try JSONEncoder().encode(identity)
            try data.write(to: botIdentityURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save bot identity: \(error)")
        }
    }

    static func loadBotIdentity() -> BotIdentity {
        guard FileManager.default.fileExists(atPath: botIdentityURL.path) else { return BotIdentity() }
        do {
            let data = try Data(contentsOf: botIdentityURL)
            return try JSONDecoder().decode(BotIdentity.self, from: data)
        } catch {
            print("[LocalStorage] Failed to load bot identity: \(error)")
            return BotIdentity()
        }
    }

    // MARK: - User Profile (cache of USER.md)

    private static var userProfileURL: URL {
        documentsURL.appendingPathComponent("user_profile.json")
    }

    static func saveUserProfile(_ profile: UserProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: userProfileURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save user profile: \(error)")
        }
    }

    static func loadUserProfile() -> UserProfile {
        guard FileManager.default.fileExists(atPath: userProfileURL.path) else { return UserProfile() }
        do {
            let data = try Data(contentsOf: userProfileURL)
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            print("[LocalStorage] Failed to load user profile: \(error)")
            return UserProfile()
        }
    }
}
