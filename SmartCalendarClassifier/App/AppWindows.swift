import AppKit
import SmartCalendarCore
import SwiftUI

/// The app's ordinary windows (main, Settings, setup guide), opened from the menu bar icon. Managed in AppKit (rather
/// than as SwiftUI scenes) so they can be opened from anywhere and always come to the front,
/// even though a menu bar app is never the active app when its icon is clicked.
@MainActor
final class AppWindows {
    private let calendars: CalendarService
    private let history: HistoryStore
    private var main: NSWindow?
    private var settings: NSWindow?
    private var onboarding: NSWindow?

    init(calendars: CalendarService, history: HistoryStore) {
        self.calendars = calendars
        self.history = history
    }

    func showMain() {
        let window = main ?? makeWindow(
            title: "Smart Calendar Classifier",
            content: MainView(),
            style: [.titled, .closable, .miniaturizable, .resizable],
            autosaveName: "MainWindow",
            size: NSSize(width: 760, height: 680)
        )
        main = window
        bringForward(window)
    }

    func showSettings() {
        let window = settings ?? makeWindow(
            title: "Settings",
            content: SettingsView(),
            // A fixed size with the form scrolling inside: sizing the window to a scrolling
            // form made AppKit loop through layout and crash.
            style: [.titled, .closable, .resizable],
            autosaveName: "SettingsWindow",
            size: NSSize(width: 540, height: 680)
        )
        settings = window
        bringForward(window)
    }

    func showOnboarding() {
        let window = onboarding ?? makeWindow(
            title: "Welcome",
            content: OnboardingView { [weak self] in self?.onboarding?.close() },
            style: [.titled, .closable],
            autosaveName: "OnboardingWindow",
            sizesToContent: true
        )
        onboarding = window
        bringForward(window)
    }

    private func makeWindow(
        title: String, content: some View, style: NSWindow.StyleMask, autosaveName: String,
        size: NSSize? = nil, sizesToContent: Bool = false
    ) -> NSWindow {
        let controller = NSHostingController(rootView: content.environment(calendars).environment(history))
        if sizesToContent { controller.sizingOptions = [.preferredContentSize] }
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = style
        window.isReleasedWhenClosed = false
        if let size { window.setContentSize(size) }
        window.center()
        window.setFrameAutosaveName(autosaveName)
        return window
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
