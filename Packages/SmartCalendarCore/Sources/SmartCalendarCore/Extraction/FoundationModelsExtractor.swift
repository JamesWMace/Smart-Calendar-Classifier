import Foundation
import FoundationModels

public enum ModelAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public static var current: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is turned off in System Settings.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Apple Intelligence is still downloading.")
        case .unavailable(let other):
            return .unavailable(reason: "Apple Intelligence is unavailable (\(other)).")
        }
    }
}

/// Extracts events with Apple's on-device model using guided generation.
public struct FoundationModelsExtractor: Sendable {
    public init() {}

    /// Starts loading the model so the first extraction after a hotkey press is quicker.
    public static func prewarm() {
        LanguageModelSession(instructions: PromptBuilder.instructions).prewarm()
    }

    /// The model's raw structured output, before any date resolution.
    public func extractRaw(from context: CaptureContext) async throws -> [ExtractedEvent] {
        // A fresh session per request: nothing from a previous selection leaks into this one.
        let session = LanguageModelSession(instructions: PromptBuilder.instructions)
        let response = try await session.respond(
            to: PromptBuilder.prompt(for: context),
            generating: ExtractionResult.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content.events
    }
}
