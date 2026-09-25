import SmartCalendarCore
import SwiftUI

@main
struct SmartCalendarClassifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var calendars = CalendarService()

    var body: some Scene {
        MenuBarExtra("Smart Calendar Classifier", systemImage: "calendar.badge.plus") {
            MenuBarMenu()
        }
        .menuBarExtraStyle(.menu)

        Window("Try It", id: AppDelegate.tryItWindowID) {
            TryItView()
                .environment(calendars)
        }
        .defaultSize(width: 760, height: 620)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(calendars)
        }
    }
}

/// The menu shown from the menu bar icon.
private struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Try It…") {
            WindowPresenter.present(titled: "Try It") { openWindow(id: AppDelegate.tryItWindowID) }
        }
        Button("Settings…") {
            WindowPresenter.present(titled: "Settings") { openSettings() }
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Smart Calendar Classifier") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
