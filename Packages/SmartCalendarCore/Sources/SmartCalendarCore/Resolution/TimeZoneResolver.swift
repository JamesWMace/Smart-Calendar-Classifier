import Foundation

/// Turns time zones as people write them ("ET", "PST", "UTC+2", "London time") into `TimeZone`s.
///
/// Region abbreviations map to region identifiers rather than fixed offsets, so "PST" written
/// in July still means Pacific time with daylight saving — which is what the writer meant.
public enum TimeZoneResolver {
    private static let aliases: [String: String] = [
        "ET": "America/New_York", "EST": "America/New_York", "EDT": "America/New_York", "EASTERN": "America/New_York",
        "CT": "America/Chicago", "CST": "America/Chicago", "CDT": "America/Chicago", "CENTRAL": "America/Chicago",
        "MT": "America/Denver", "MST": "America/Denver", "MDT": "America/Denver", "MOUNTAIN": "America/Denver",
        "PT": "America/Los_Angeles", "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles", "PACIFIC": "America/Los_Angeles",
        "AKT": "America/Anchorage", "AKST": "America/Anchorage", "AKDT": "America/Anchorage",
        "HT": "Pacific/Honolulu", "HST": "Pacific/Honolulu",
        "GMT": "GMT", "UTC": "UTC", "Z": "UTC", "ZULU": "UTC",
        "BST": "Europe/London", "UK": "Europe/London", "LONDON": "Europe/London",
        "CET": "Europe/Paris", "CEST": "Europe/Paris", "PARIS": "Europe/Paris", "BERLIN": "Europe/Berlin",
        "IST": "Asia/Kolkata", "INDIA": "Asia/Kolkata",
        "JST": "Asia/Tokyo", "TOKYO": "Asia/Tokyo",
        "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney", "SYDNEY": "Australia/Sydney",
        "NEW YORK": "America/New_York", "NYC": "America/New_York",
        "LOS ANGELES": "America/Los_Angeles", "LA": "America/Los_Angeles", "SF": "America/Los_Angeles",
        "CHICAGO": "America/Chicago", "DENVER": "America/Denver",
    ]

    public static func resolve(_ text: String?) -> TimeZone? {
        guard var key = text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !key.isEmpty else {
            return nil
        }
        for suffix in [" TIME", " STANDARD", " DAYLIGHT"] where key.hasSuffix(suffix) {
            key = String(key.dropLast(suffix.count))
        }
        if let identifier = aliases[key] { return TimeZone(identifier: identifier) }
        if let offset = parseOffset(key) { return TimeZone(secondsFromGMT: offset) }
        if let zone = TimeZone(identifier: text!.trimmingCharacters(in: .whitespaces)) { return zone }
        return TimeZone(abbreviation: key)
    }

    /// "UTC+2", "GMT-05:30", "+0530", "UTC +5"
    private static func parseOffset(_ key: String) -> Int? {
        let pattern = /^(?:UTC|GMT)?\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?$/
        guard let match = key.wholeMatch(of: pattern),
              let hours = Int(match.2), hours <= 14 else { return nil }
        let minutes = match.3.flatMap { Int($0) } ?? 0
        let sign = match.1 == "-" ? -1 : 1
        return sign * (hours * 3600 + minutes * 60)
    }
}
