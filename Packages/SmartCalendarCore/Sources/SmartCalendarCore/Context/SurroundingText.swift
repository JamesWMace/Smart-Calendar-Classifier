import Foundation

/// Cuts the text around a selection out of a document, as the capture layer sees it:
/// Accessibility reports selections as UTF-16 ranges into the element's whole value.
public enum SurroundingText {
    public struct Slice: Sendable, Equatable {
        public var before: String
        public var selected: String
        public var after: String
    }

    /// - Parameters:
    ///   - range: the selection, in UTF-16 units (`NSRange`/`CFRange` from Accessibility).
    ///   - maxBefore/maxAfter: how much context to keep, trimmed back to a word boundary.
    public static func slice(_ text: String, selection range: NSRange, maxBefore: Int = 2_000, maxAfter: Int = 1_000) -> Slice? {
        let whole = text as NSString
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= whole.length else { return nil }

        let beforeStart = max(0, range.location - maxBefore)
        let afterEnd = min(whole.length, NSMaxRange(range) + maxAfter)
        var before = whole.substring(with: safe(whole, NSRange(location: beforeStart, length: range.location - beforeStart)))
        var after = whole.substring(with: safe(whole, NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range))))

        // Don't start or end the context mid-word.
        if beforeStart > 0, let space = before.firstIndex(where: \.isWhitespace) {
            before = String(before[before.index(after: space)...])
        }
        if afterEnd < whole.length, let space = after.lastIndex(where: \.isWhitespace) {
            after = String(after[..<space])
        }
        return Slice(before: before, selected: whole.substring(with: range), after: after)
    }

    /// Finds `selection` inside `document`, tolerating different whitespace (a copied
    /// selection and an app's accessibility text rarely break lines the same way). Used when
    /// the selection arrived without a position, e.g. by ⌘C or the Services menu.
    public static func locate(_ selection: String, in document: String) -> NSRange? {
        let words = selection.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let pattern = { (words: ArraySlice<String>) in
            words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\\s+")
        }
        let whole = NSRange(location: 0, length: (document as NSString).length)
        // Long selections: anchor on the first and last words instead of one giant pattern.
        guard words.count > 40 else {
            return try? NSRegularExpression(pattern: pattern(words[...])).firstMatch(in: document, range: whole)?.range
        }
        guard let head = try? NSRegularExpression(pattern: pattern(words.prefix(15))).firstMatch(in: document, range: whole)?.range
        else { return nil }
        let rest = NSRange(location: head.location, length: whole.length - head.location)
        guard let tail = try? NSRegularExpression(pattern: pattern(words.suffix(15))).firstMatch(in: document, range: rest)?.range
        else { return nil }
        return NSRange(location: head.location, length: NSMaxRange(tail) - head.location)
    }

    /// Widens a UTF-16 range so it never splits a surrogate pair or composed character.
    private static func safe(_ string: NSString, _ range: NSRange) -> NSRange {
        guard range.length > 0 else { return range }
        let start = string.rangeOfComposedCharacterSequence(at: range.location)
        let end = string.rangeOfComposedCharacterSequence(at: NSMaxRange(range) - 1)
        return NSRange(location: start.location, length: NSMaxRange(end) - start.location)
    }
}
