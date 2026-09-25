import SmartCalendarCore
import SwiftUI

enum SettingsKey {
    static let defaultDurationMinutes = "defaultDurationMinutes"
    /// Empty means "the system default calendar".
    static let defaultCalendarID = "defaultCalendarID"
    /// Minutes before the start; -1 means no alert.
    static let defaultAlertMinutes = "defaultAlertMinutes"
    /// Add events without the preview when nothing is missing (decision #12).
    static let trustMode = "trustMode"
    static let onboardingCompleted = "onboardingCompleted"
}

extension Int {
    /// The alerts to add for the stored `defaultAlertMinutes` value.
    var alertMinutesSetting: [Int] { self < 0 ? [] : [self] }
}

struct SettingsView: View {
    @Environment(CalendarService.self) private var calendars
    @AppStorage(SettingsKey.defaultDurationMinutes) private var defaultDurationMinutes = 60
    @AppStorage(SettingsKey.defaultCalendarID) private var defaultCalendarID = ""
    @AppStorage(SettingsKey.defaultAlertMinutes) private var defaultAlertMinutes = -1
    @AppStorage(SettingsKey.trustMode) private var trustMode = false
    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                if let error = launchAtLogin.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Add events without previewing", isOn: $trustMode)
                Text("Events are added as soon as they’re read. The panel still lists them with Undo, and waits for you when something like a date is missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shortcut") {
                LabeledContent("Add selected text") { ShortcutRecorder() }
                Text("Also available: right-click selected text → Services → Add Event to Calendar, and “Add Event from Text” in Shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                AppleIntelligenceStatusView()
                CalendarAccessView()
                AccessibilityAccessView()
            }
            Section("Calendar") {
                Picker("Add events to", selection: $defaultCalendarID) {
                    Text("System default").tag("")
                    CalendarPickerItems(calendars: calendars.calendars)
                }
                .disabled(!calendars.hasFullAccess)
                Text("A calendar named in the event, or one the text clearly belongs to (like “School” for a syllabus), is chosen instead when it matches one of yours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Events") {
                Picker("Default length when no end time is given", selection: $defaultDurationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text(Self.durationLabel(minutes)).tag(minutes)
                    }
                }
                Picker("Alert", selection: $defaultAlertMinutes) {
                    Text("None").tag(-1)
                    Text("At time of event").tag(0)
                    ForEach([5, 10, 15, 30, 60, 120, 1_440], id: \.self) { minutes in
                        Text("\(Self.durationLabel(minutes)) before").tag(minutes)
                    }
                }
                Text("Used when the text doesn’t ask for a reminder itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func durationLabel(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide))
    }
}

/// Whether the on-device model can be used, and where to turn it on if not.
struct AppleIntelligenceStatusView: View {
    private let availability = ModelAvailability.current

    var body: some View {
        switch availability {
        case .available:
            Label("Apple Intelligence ready", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .unavailable(let reason):
            HStack {
                Label(reason + " A basic date reader is used instead.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                }
            }
        }
    }
}

/// Accessibility status, needed to read selections and their surroundings in other apps.
struct AccessibilityAccessView: View {
    private let accessibility = AccessibilityPermission.shared

    var body: some View {
        if accessibility.isTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            HStack {
                Label("Accessibility access is needed to read selected text.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open System Settings") { accessibility.openSettings() }
            }
            .onAppear { accessibility.refresh() }
        }
    }
}

/// Calendar choices grouped by account, for use inside a `Picker` whose tag type is `String`.
struct CalendarPickerItems: View {
    let calendars: [CalendarInfo]

    var body: some View {
        ForEach(Dictionary(grouping: calendars, by: \.sourceTitle).sorted { $0.key < $1.key }, id: \.key) { source, group in
            Section(source) {
                ForEach(group) { calendar in
                    Label {
                        Text(calendar.title)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color(red: calendar.red, green: calendar.green, blue: calendar.blue))
                    }
                    .tag(calendar.id)
                }
            }
        }
    }
}
