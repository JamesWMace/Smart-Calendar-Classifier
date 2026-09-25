import AppKit

/// Handles right-click → Services → "Add Event to Calendar", declared under `NSServices`
/// in Info.plist. Works in almost every app and needs no permission; users can also give it
/// a keyboard shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services.
final class ServiceProvider: NSObject {
    @objc func addToCalendar(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isBlank else {
            error.pointee = "No text was selected."
            return
        }
        // Services messages arrive on the main thread.
        MainActor.assumeIsolated {
            CaptureCoordinator.shared.receiveFromService(text)
        }
    }
}
