import SmartCalendarCore
import SwiftUI

/// Shows calendar permission status and the one action that moves it forward.
struct CalendarAccessView: View {
    @Environment(CalendarService.self) private var calendars

    var body: some View {
        switch calendars.authorization {
        case .fullAccess:
            Label("Calendar access granted", systemImage: "calendar.badge.checkmark")
                .foregroundStyle(.green)
        case .notDetermined:
            Button {
                Task { await calendars.requestAccess() }
            } label: {
                Label("Allow Calendar Access…", systemImage: "calendar.badge.plus")
            }
        case .writeOnly:
            settingsButton("Full calendar access is needed to pick calendars and check conflicts.")
        case .denied:
            settingsButton("Calendar access is turned off.")
        case .restricted:
            Label("Calendar access is restricted on this Mac.", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func settingsButton(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
        }
    }
}
