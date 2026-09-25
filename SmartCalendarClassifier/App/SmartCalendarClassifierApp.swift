import SmartCalendarCore
import SwiftUI

@main
struct SmartCalendarClassifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var calendars = CalendarService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)

        Window("Try It", id: AppDelegate.tryItWindowID) {
            TryItView()
                .environment(calendars)
        }
        .defaultSize(width: 760, height: 680)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(calendars)
        }
    }
}

/// The menu bar icon. It is always alive, so it is also where captures made from AppKit
/// (hotkey, Services, Shortcuts) get their window opened.
private struct MenuBarIcon: View {
    @Environment(\.openWindow) private var openWindow
    private let coordinator = CaptureCoordinator.shared

    var body: some View {
        Image(systemName: coordinator.isCapturing ? "calendar.badge.clock" : "calendar.badge.plus")
            .onChange(of: coordinator.presentationRequests) {
                WindowPresenter.present(titled: "Try It") { openWindow(id: AppDelegate.tryItWindowID) }
            }
    }
}

/// The menu shown from the menu bar icon.
private struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    private let coordinator = CaptureCoordinator.shared
    private let accessibility = AccessibilityPermission.shared

    var body: some View {
        // The app that was frontmost before the menu opened still owns the selection.
        Button("Add Selected Text to Calendar   \(AppDelegate.hotKeyDisplay)") {
            coordinator.captureFrontmostSelection()
        }
        if let problem = coordinator.lastProblem {
            Text(problem)
        }
        if !accessibility.isTrusted {
            Button("Allow Accessibility Access…") { accessibility.prompt() }
        }
        Divider()
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
