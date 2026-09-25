import SmartCalendarCore
import SwiftUI

enum SettingsKey {
    static let defaultDurationMinutes = "defaultDurationMinutes"
    /// Empty means "the system default calendar".
    static let defaultCalendarID = "defaultCalendarID"
    /// Minutes before the start; -1 means no alert.
    static let defaultAlertMinutes = "defaultAlertMinutes"
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

    var body: some View {
        Form {
            Section("Calendar") {
                CalendarAccessView()
                Picker("Add events to", selection: $defaultCalendarID) {
                    Text("System default").tag("")
                    CalendarPickerItems(calendars: calendars.calendars)
                }
                .disabled(!calendars.hasFullAccess)
                Text("A calendar the text clearly belongs to (like “School” for a syllabus) is suggested instead when it matches one of yours.")
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
            Section {
                Text("Hotkey and trust mode arrive with the capture phase.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func durationLabel(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide))
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
