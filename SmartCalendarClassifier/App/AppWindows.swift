import AppKit
import SmartCalendarCore
import SwiftUI

/// The app's ordinary windows (main, Settings, setup guide), opened from the menu bar icon. Managed in AppKit (rather
/// than as SwiftUI scenes) so they can be opened from anywhere and always come to the front,
/// even though a menu bar app is never the active app when its icon is clicked.
@MainActor
final class AppWindows {
    private let calendars: CalendarService
    private var tryIt: NSWindow?
    private var settings: NSWindow?
    private var onboarding: NSWindow?

    init(calendars: CalendarService) {
        self.calendars = calendars
    }

    func showTryIt() {
        let window = tryIt ?? makeWindow(
            title: "Smart Calendar Classifier",
            content: TryItView(),
            style: [.titled, .closable, .miniaturizable, .resizable],
            autosaveName: "TryItWindow",
            size: NSSize(width: 760, height: 680)
        )
        tryIt = window
        bringForward(window)
    }

    func showSettings() {
        let window = settings ?? makeWindow(
            title: "Settings",
            content: SettingsView(),
            style: [.titled, .closable],
            autosaveName: "SettingsWindow",
            sizesToContent: true
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
        let controller = NSHostingController(rootView: content.environment(calendars))
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
