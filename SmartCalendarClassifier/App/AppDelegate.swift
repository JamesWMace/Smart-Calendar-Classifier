import AppKit
import Carbon.HIToolbox
import SmartCalendarCore

/// A menu bar app (`LSUIElement`): no Dock icon, lives in the menu bar (decision #1), and
/// keeps running with every window closed. Idle cost is essentially zero: no timers, and
/// the language model is only loaded when an extraction is requested.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shown in the menu and Settings; a recorder to change it arrives with phase 6.
    static let hotKeyDisplay = "⌃⌥C"

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
        hotKey = HotKey(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey) {
            CaptureCoordinator.shared.captureFrontmostSelection()
        }
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
