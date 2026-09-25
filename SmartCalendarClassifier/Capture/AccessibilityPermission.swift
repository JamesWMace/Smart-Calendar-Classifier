import AppKit
import ApplicationServices

/// Accessibility access lets the app read the selection and its surroundings in other apps,
/// and post ⌘C as a fallback. The system has no API to observe it directly, but posts a
/// distributed notification whenever any app's trust changes.
@MainActor
@Observable
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private(set) var isTrusted = AXIsProcessTrusted()

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                // The trust flag updates a moment after the notification arrives.
                try? await Task.sleep(for: .milliseconds(300))
                AccessibilityPermission.shared.refresh()
            }
        }
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Shows the system prompt that leads to System Settings (only the first time per build).
    func prompt() {
        isTrusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
