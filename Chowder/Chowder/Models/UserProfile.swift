import Foundation

/// Maps to the agent's USER.md workspace file.
struct UserProfile: Codable {
    var name: String = ""
    var callName: String = ""     // "What to call them"
    var pronouns: String = ""
    var timezone: String = ""
    var notes: String = ""
    var context: String = ""      // Free-form context section

    // MARK: - Markdown parsing

    /// Parse USER.md content into a UserProfile.
    static func from(markdown: String) -> UserProfile {
        var profile = UserProfile()
        var inContext = false
        var contextLines: [String] = []

        for line in markdown.components(separatedBy: .newlines) {
            // Check if we've entered the Context section
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("## Context") ||
               line.trimmingCharacters(in: .whitespaces).hasPrefix("# Context") {
                inContext = true
                continue
            }

            if inContext {
                contextLines.append(line)
                continue
            }

            if let value = extractValue(line, key: "Name") {
                profile.name = value
            } else if let value = extractValue(line, key: "What to call them") {
                profile.callName = value
            } else if let value = extractValue(line, key: "Pronouns") {
                profile.pronouns = value
            } else if let value = extractValue(line, key: "Timezone") {
                profile.timezone = value
            } else if let value = extractValue(line, key: "Notes") {
                profile.notes = value
            }
        }

        profile.context = contextLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return profile
    }

    /// Serialize back to USER.md format.
    func toMarkdown() -> String {
        var md = """
        # USER.md - About Your Human

        - **Name:** \(name)
        - **What to call them:** \(callName)
        - **Pronouns:** \(pronouns)
        - **Timezone:** \(timezone)
        - **Notes:** \(notes)

        ## Context

        """
        if !context.isEmpty {
            md += "\(context)\n"
        }
        return md
    }

    // MARK: - Helpers

    private static func extractValue(_ line: String, key: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
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
