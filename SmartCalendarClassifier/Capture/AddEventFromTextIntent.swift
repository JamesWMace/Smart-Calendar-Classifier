import AppIntents

/// "Add Event from Text" in Shortcuts and Spotlight: pass any text (clipboard, a note, a
/// webpage's selection) and the app extracts events from it.
struct AddEventFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Event from Text"
    static let description = IntentDescription("Finds the events in some text and opens them in Smart Calendar Classifier.")
    static let openAppWhenRun = true

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureCoordinator.shared.deliver(CapturedText(selection: text, method: .shortcut))
        return .result()
    }
}

struct SmartCalendarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddEventFromTextIntent(),
            phrases: ["Add event from text with \(.applicationName)"],
            shortTitle: "Add Event from Text",
            systemImageName: "calendar.badge.plus"
        )
    }
}
