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
        var events: [ExtractedEvent] = []
        for try await event in stream(from: context) { events.append(event) }
        return events
    }

    /// Yields each event as soon as the model has finished writing it, so a long list
    /// (a syllabus, a schedule) starts showing up after the first few seconds.
    public func stream(from context: CaptureContext) -> AsyncThrowingStream<ExtractedEvent, Error> {
        let prompt = PromptBuilder.prompt(for: context)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // A fresh session per request: nothing from a previous selection leaks into this one.
                    let session = LanguageModelSession(instructions: PromptBuilder.instructions)
                    let response = session.streamResponse(
                        to: prompt, generating: ExtractionResult.self, options: GenerationOptions(samplingMode: .greedy)
                    )
                    var emitted = 0
                    var latest: [GeneratedContent] = []
                    for try await snapshot in response {
                        latest = Self.events(in: snapshot.rawContent)
                        // An element is complete once the model has moved past it.
                        while emitted < latest.count, latest[emitted].isComplete,
                              let event = try? ExtractedEvent(latest[emitted]) {
                            continuation.yield(event)
                            emitted += 1
                        }
                    }
                    for element in latest.dropFirst(emitted) {
                        if let event = try? ExtractedEvent(element) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func events(in content: GeneratedContent) -> [GeneratedContent] {
        guard case .structure(let properties, _) = content.kind,
              let events = properties["events"], case .array(let elements) = events.kind else { return [] }
        return elements
    }
}
