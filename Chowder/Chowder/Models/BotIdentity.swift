import Foundation

/// Maps to the agent's IDENTITY.md workspace file.
struct BotIdentity: Codable {
    var name: String = ""
    var creature: String = ""
    var vibe: String = ""
    var emoji: String = ""
    var avatar: String = ""       // workspace-relative path, URL, or data URI

    // MARK: - Markdown parsing

    /// Parse IDENTITY.md content into a BotIdentity.
    static func from(markdown: String) -> BotIdentity {
        var identity = BotIdentity()
        for line in markdown.components(separatedBy: .newlines) {
            if let value = extractValue(line, key: "Name") {
                identity.name = value
            } else if let value = extractValue(line, key: "Creature") {
                identity.creature = value
            } else if let value = extractValue(line, key: "Vibe") {
                identity.vibe = value
            } else if let value = extractValue(line, key: "Emoji") {
                identity.emoji = value
            } else if let value = extractValue(line, key: "Avatar") {
                identity.avatar = value
            }
        }
        return identity
    }

    /// Serialize back to IDENTITY.md format.
    func toMarkdown() -> String {
        """
        # IDENTITY.md - Who Am I?

        - **Name:** \(name)
        - **Creature:** \(creature)
        - **Vibe:** \(vibe)
        - **Emoji:** \(emoji)
        - **Avatar:** \(avatar)

        This isn't just metadata. It's the start of figuring out who you are.
        """
    }

    // MARK: - Helpers

    /// Extract value from a line like `- **Key:** Value` or `* **Key:** Value`.
    private static func extractValue(_ line: String, key: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Match patterns: "- **Key:** value" or "* **Key:** value" or "**Key:** value"
        let patterns = [
            "- **\(key):**",
            "* **\(key):**",
            "**\(key):**"
        ]
        for pattern in patterns {
            if trimmed.hasPrefix(pattern) {
                let value = trimmed.dropFirst(pattern.count).trimmingCharacters(in: .whitespaces)
                return value
            }
        }
        return nil
    }
}
