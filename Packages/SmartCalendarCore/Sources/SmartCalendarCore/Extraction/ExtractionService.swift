import Foundation
import FoundationModels

/// The single entry point the app calls: picks Apple Intelligence when it's available and
/// falls back to `NSDataDetector` otherwise.
public struct ExtractionService: Sendable {
    public enum Engine: Sendable, Equatable {
        case appleIntelligence
        case dataDetector(reason: String)
    }

    public struct Outcome: Sendable {
        public var candidates: [EventCandidate]
        public var engine: Engine
        /// The model's structured output, for debugging in the Try It window.
        public var rawEvents: [ExtractedEvent]
    }

    public var options: ResolutionOptions

    public init(options: ResolutionOptions = .init()) {
        self.options = options
    }

    public func extract(from context: CaptureContext) async -> Outcome {
        guard case .available = ModelAvailability.current else {
            if case .unavailable(let reason) = ModelAvailability.current {
                return fallback(context, reason: reason)
            }
            return fallback(context, reason: "Apple Intelligence is unavailable.")
        }
        do {
            let raw = try await FoundationModelsExtractor().extractRaw(from: context)
            let resolver = EventResolver(context: context, options: options)
            return Outcome(candidates: resolver.resolveAll(raw), engine: .appleIntelligence, rawEvents: raw)
        } catch let error as LanguageModelSession.GenerationError {
            return fallback(context, reason: Self.describe(error))
        } catch {
            return fallback(context, reason: error.localizedDescription)
        }
    }

    private func fallback(_ context: CaptureContext, reason: String) -> Outcome {
        Outcome(
            candidates: DataDetectorExtractor().extract(from: context, options: options),
            engine: .dataDetector(reason: reason),
            rawEvents: []
        )
    }

    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize: "The selection was too long for Apple Intelligence."
        case .guardrailViolation: "Apple Intelligence declined to process this text."
        case .unsupportedLanguageOrLocale: "Apple Intelligence doesn't support this language yet."
        default: "Apple Intelligence failed: \(error.localizedDescription)"
        }
    }
}
