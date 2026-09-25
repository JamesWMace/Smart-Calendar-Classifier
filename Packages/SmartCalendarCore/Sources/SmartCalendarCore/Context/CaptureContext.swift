import Foundation

/// Everything known about a piece of highlighted text at the moment the user asked to
/// turn it into an event. Built by the app's capture layer; consumed by the extractors.
public struct CaptureContext: Sendable, Equatable {
    /// The highlighted text. Events are extracted from this.
    public var selection: String
    /// Text immediately before the selection in the same document/field, if readable.
    public var textBefore: String?
    /// Text immediately after the selection in the same document/field, if readable.
    public var textAfter: String?
    /// e.g. "Mail", "Safari", "Slack".
    public var appName: String?
    /// Frontmost window title — for Mail this is usually the subject line.
    public var windowTitle: String?
    /// The page or document URL, when the source app exposes one.
    public var url: URL?
    /// "Now", from the point of view of the user. Relative dates resolve against this.
    public var referenceDate: Date
    /// The user's local time zone. Every resolved date is presented in this zone.
    public var timeZone: TimeZone
    /// Names of the user's writable calendars, so the model can suggest one.
    public var calendarNames: [String]

    public init(
        selection: String,
        textBefore: String? = nil,
        textAfter: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: URL? = nil,
        referenceDate: Date = .now,
        timeZone: TimeZone = .current,
        calendarNames: [String] = []
    ) {
        self.selection = selection
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.referenceDate = referenceDate
        self.timeZone = timeZone
        self.calendarNames = calendarNames
    }
}
