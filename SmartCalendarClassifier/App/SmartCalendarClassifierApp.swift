import SwiftUI

@main
struct SmartCalendarClassifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and windows are AppKit (see AppDelegate). A scene is still
        // required; this one only routes ⌘, to the app's own Settings window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.windows.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}
