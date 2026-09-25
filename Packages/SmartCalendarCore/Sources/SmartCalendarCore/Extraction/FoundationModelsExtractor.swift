import Foundation
import FoundationModels
import Synchronization

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

    /// A session loaded ahead of time, used (once) by the next extraction.
    private static let warmSession = Mutex<LanguageModelSession?>(nil)

    /// Starts loading the model while the selection is still being read, so the first event
    /// appears sooner. Cheap to call repeatedly.
    public static func prewarm() {
        guard case .available = ModelAvailability.current else { return }
        let session = LanguageModelSession(instructions: PromptBuilder.instructions)
        session.prewarm()
        warmSession.withLock { $0 = session }
    }

    /// A fresh session per request, so nothing from a previous selection leaks into this one.
    private static func takeSession() -> LanguageModelSession {
        let warm = warmSession.withLock { session in
            defer { session = nil }
            return session
        }
        return warm ?? LanguageModelSession(instructions: PromptBuilder.instructions)
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
                    let session = Self.takeSession()
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
