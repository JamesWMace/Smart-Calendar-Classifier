import AppKit
import Carbon.HIToolbox

/// A menu bar app (`LSUIElement`): no Dock icon, lives in the menu bar (decision #1), and
/// keeps running with every window closed. Idle cost is essentially zero: no timers, and
/// the language model is only loaded when an extraction is requested.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let tryItWindowID = "try-it"
    /// Shown in the menu and Settings; a recorder to change it arrives with phase 6.
    static let hotKeyDisplay = "⌃⌥C"

    private var hotKey: HotKey?
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
