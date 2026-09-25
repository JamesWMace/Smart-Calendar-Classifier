import AppKit
import Carbon.HIToolbox
import SmartCalendarCore

/// A menu bar app (`LSUIElement`): no Dock icon, lives in the menu bar (decision #1), and
/// keeps running with every window closed. Idle cost is essentially zero: no timers, and
/// the language model is only loaded when an extraction is requested.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared by the windows and the preview panel.
    let calendars = CalendarService()
    private(set) lazy var windows = AppWindows(calendars: calendars)
    private lazy var previewPanel = PreviewPanelController(calendars: calendars)
    private var statusItem: StatusItemController?
    private var hotKey: HotKey?
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CaptureCoordinator.shared.present = { [weak self] capture in self?.previewPanel.show(capture) }
        statusItem = StatusItemController(windows: windows, preview: previewPanel)
        ShortcutStore.shared.onChange = { [weak self] in self?.registerHotKey() }
        registerHotKey()
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        if !UserDefaults.standard.bool(forKey: SettingsKey.onboardingCompleted) {
            windows.showOnboarding()
        }
    }

    private func registerHotKey() {
        hotKey = nil
        let store = ShortcutStore.shared
        guard !store.isRecording else { return }
        let shortcut = store.shortcut
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) {
            CaptureCoordinator.shared.captureFrontmostSelection()
        }
        store.registrationError = hotKey == nil ? "\(shortcut.display) is already used by another app. Pick a different shortcut." : nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
