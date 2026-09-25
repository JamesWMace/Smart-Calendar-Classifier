import SwiftUI

enum SettingsKey {
    static let defaultDurationMinutes = "defaultDurationMinutes"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.defaultDurationMinutes) private var defaultDurationMinutes = 60

    var body: some View {
        Form {
            Section("Events") {
                Picker("Default length when no end time is given", selection: $defaultDurationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60)\(minutes % 60 == 0 ? "" : ".5") hour\(minutes == 60 ? "" : "s")")
                            .tag(minutes)
                    }
                }
            }
            Section {
                Text("Hotkey, default calendar, alerts and trust mode arrive with the capture and calendar phases.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
