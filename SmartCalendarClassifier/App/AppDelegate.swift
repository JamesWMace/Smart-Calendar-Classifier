import AppKit

/// A menu bar app (`LSUIElement`): no Dock icon, lives in the menu bar (decision #1), and
/// keeps running with every window closed. Idle cost is essentially zero: no timers, and
/// the language model is only loaded when an extraction is requested.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let tryItWindowID = "try-it"

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
