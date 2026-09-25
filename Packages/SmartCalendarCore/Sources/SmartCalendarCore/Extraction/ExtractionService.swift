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

    /// - Parameter onCandidate: called with each event as soon as it's resolved, before the
    ///   whole extraction finishes (duplicates are skipped).
    public func extract(
        from context: CaptureContext,
        onCandidate: @escaping @MainActor @Sendable (EventCandidate) -> Void = { _ in }
    ) async -> Outcome {
        if case .unavailable(let reason) = ModelAvailability.current {
            return await fallback(context, reason: reason, onCandidate: onCandidate)
        }
        let resolver = EventResolver(context: context, options: options)
        var raw: [ExtractedEvent] = []
        var candidates: [EventCandidate] = []
        do {
            for try await event in FoundationModelsExtractor().stream(from: context) {
                raw.append(event)
                let candidate = resolver.resolve(event)
                guard !EventResolver.isDuplicate(candidate, of: candidates) else { continue }
                candidates.append(candidate)
                await onCandidate(candidate)
            }
            return Outcome(candidates: candidates, engine: .appleIntelligence, rawEvents: raw)
        } catch {
            // Keep whatever already arrived; only fall back when nothing did.
            if !candidates.isEmpty {
                return Outcome(candidates: candidates, engine: .appleIntelligence, rawEvents: raw)
            }
            let reason = (error as? LanguageModelSession.GenerationError).map(Self.describe) ?? error.localizedDescription
            return await fallback(context, reason: reason, onCandidate: onCandidate)
        }
    }

    private func fallback(
        _ context: CaptureContext, reason: String, onCandidate: @MainActor @Sendable (EventCandidate) -> Void
    ) async -> Outcome {
        let candidates = DataDetectorExtractor().extract(from: context, options: options)
        for candidate in candidates { await onCandidate(candidate) }
        return Outcome(candidates: candidates, engine: .dataDetector(reason: reason), rawEvents: [])
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
