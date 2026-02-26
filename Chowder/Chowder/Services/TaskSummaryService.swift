import FoundationModels

/// Generates short task titles from user messages using Apple's on-device Foundation Models.
actor TaskSummaryService {
    static let shared = TaskSummaryService()

    private init() {}

    /// Generate a 2-4 word title for the task represented by the latest user message.
    /// Returns nil if Foundation Models is unavailable or generation fails.
    func generateTitle(from latestUserMessage: String) async -> String? {
        let message = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            print("📝 TaskSummaryService: No latest user message provided")
            return nil
        }
        
        let availability = SystemLanguageModel.default.availability
        guard availability == .available else {
            print("📝 TaskSummaryService: Model not available - \(availability)")
            return nil
        }

        let session = LanguageModelSession(model: .init(useCase: .general, guardrails: .permissiveContentTransformations))
        
        let prompt = """
        You are generating a very short UI task title.

        Use ONLY this latest user message:
        "\(message)"

        Rules:
        - Infer the task the assistant should do from this message alone
        - Return a concise 2-4 word imperative-style title
        - Prefer specific nouns and proper nouns from the message
        - Avoid generic words
        - Do not add punctuation at the end

        It is crucial that the title is succinct because it will be used in UI. Only output the title, nothing else.
        """

        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Convert an intent string from present/progressive tense to past tense.
    /// e.g. "Searching for files..." -> "Searched for files"
    /// Returns nil if Foundation Models is unavailable or generation fails.
    func convertToPastTense(_ intent: String) async -> String? {
        let cleaned = intent.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let availability = SystemLanguageModel.default.availability
        guard availability == .available else { return nil }

        let session = LanguageModelSession(model: .init(useCase: .general, guardrails: .permissiveContentTransformations))

        let prompt = """
        Convert this action description to past tense. Keep the same level of detail and specificity.

        Input: "\(cleaned)"

        Rules:
        - Convert progressive/present tense to simple past tense
        - Keep proper nouns, filenames, and quoted strings unchanged
        - Keep it the same length or shorter
        - Do not add punctuation at the end

        Examples:
        - "Searching for files" → "Searched for files"
        - "Reading config.json" → "Read config.json"
        - "Browsing api.example.com" → "Browsed api.example.com"
        - "Running a command" → "Ran a command"
        - "Comparing departure times and prices" → "Compared departure times and prices"
        - "Entering passenger details" → "Entered passenger details"
        - "Writing helpers.swift" → "Wrote helpers.swift"
        - "Using browser" → "Used browser"
        - "Fetching data" → "Fetched data"
        - "Thinking" → "Thought about the task"

        Only output the converted text, nothing else.
        """

        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Generate a completion message from the assistant's final response text.
    /// Returns nil if Foundation Models is unavailable or generation fails.
    func generateCompletionMessage(fromAssistantResponse assistantResponse: String) async -> String? {
        let finalResponse = assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalResponse.isEmpty else {
            print("📝 TaskSummaryService: No assistant response provided")
            return nil
        }

        let availability = SystemLanguageModel.default.availability
        guard availability == .available else {
            print("📝 TaskSummaryService: Model not available - \(availability)")
            return nil
        }

        let session = LanguageModelSession(model: .init(useCase: .general, guardrails: .permissiveContentTransformations))

        let prompt = """
        You are generating a completion summary for a finished task.
        
        Use ONLY this final assistant response:
        "\(finalResponse)"

        Rules:
        - Summarize the actual outcome or result achieved
        - Use past-tense, notification style
        - Keep it concise (under 8 words)
        - Be specific to what was actually completed
        - Do not use exclamation marks

        Only output the completion message, nothing else.
        """

        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("📝 TaskSummaryService: Completion message generation failed - \(error)")
            return nil
        }
    }
}
