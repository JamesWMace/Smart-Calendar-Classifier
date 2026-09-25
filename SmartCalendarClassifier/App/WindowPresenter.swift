import AppKit

/// Brings a SwiftUI window in front of other apps.
///
/// A menu bar app isn't frontmost when its menu is used, and SwiftUI creates the window a
/// run-loop pass after `openWindow`, so it would otherwise appear behind the active app.
@MainActor
enum WindowPresenter {
    static func present(titled title: String, open: () -> Void) {
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        open()
        Task {
            // Wait (briefly) for SwiftUI to create or reveal the window.
            for _ in 0..<25 {
                let window = NSApp.windows.first { $0.isVisible && $0.canBecomeKey && $0.title.contains(title) }
                    ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey && !existing.contains(ObjectIdentifier($0)) }
                if let window {
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}
