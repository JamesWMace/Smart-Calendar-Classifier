import AppKit
import SmartCalendarCore

/// Gathers selections from every entry point (hotkey, menu, Services, Shortcuts) and hands
/// each one to the preview panel.
@MainActor
@Observable
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private(set) var isCapturing = false
    /// Why the last attempt produced nothing, for the menu.
    private(set) var lastProblem: String?
    /// Shows a capture to the user; set by the app delegate to open the preview panel.
    @ObservationIgnored var present: ((CapturedText) -> Void)?

    /// The most recent app other than this one to become active. macOS activates a Services
    /// provider before calling it, so by then the source app is no longer frontmost.
    @ObservationIgnored private var lastExternalApp: NSRunningApplication?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private init() {
        lastExternalApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ownPID ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                let coordinator = CaptureCoordinator.shared
                if let app, app.processIdentifier != coordinator.ownPID { coordinator.lastExternalApp = app }
            }
        }
    }

    /// Hotkey / menu entry point: read whatever is selected in the frontmost app.
    func captureFrontmostSelection() {
        guard !isCapturing else { return }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else {
            fail("Select some text in another app first.")
            return
        }
        guard AccessibilityPermission.shared.isTrusted else {
            AccessibilityPermission.shared.prompt()
            fail("Allow Accessibility access to read selected text.")
            return
        }

        isCapturing = true
        // Load the model while the selection is read; it takes several seconds from cold.
        FoundationModelsExtractor.prewarm()
        let pid = app.processIdentifier, bundleID = app.bundleIdentifier
        Task {
            var (captured, trace) = await Task.detached { SelectionReader.readWithAccessibility(pid: pid, bundleID: bundleID) }.value
            if captured == nil, let copied = await SelectionReader.readWithCopy() {
                let window = await Task.detached { SelectionReader.windowContext(pid: pid) }.value
                let found = await Task.detached { SelectionReader.surroundings(of: copied, pid: pid, bundleID: bundleID) }.value
                captured = CapturedText(
                    selection: copied, before: found.before, after: found.after,
                    windowTitle: window.title, url: window.url, method: .clipboard,
                    trace: trace + ["copied with ⌘C"] + found.trace
                )
            }
            isCapturing = false
            guard var captured else {
                fail("No selected text found in \(app.localizedName ?? "that app").")
                return
            }
            captured.appName = app.localizedName
            captured.appBundleID = app.bundleIdentifier
            deliver(captured)
        }
    }

    /// Services entry point: the text arrives on a pasteboard, but the source app still has
    /// it selected, so try to add its surroundings too.
    func receiveFromService(_ text: String) {
        FoundationModelsExtractor.prewarm()
        let app = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ownPID ? nil : $0 } ?? lastExternalApp
        var captured = CapturedText(selection: text, appName: app?.localizedName, appBundleID: app?.bundleIdentifier, method: .service)
        guard let app, AccessibilityPermission.shared.isTrusted else {
            deliver(captured)
            return
        }
        let pid = app.processIdentifier, bundleID = app.bundleIdentifier
        Task {
            let (read, trace) = await Task.detached { SelectionReader.readWithAccessibility(pid: pid, bundleID: bundleID) }.value
            captured.trace = trace
            if let read, read.selection.isSameText(as: text) {
                captured.before = read.before
                captured.after = read.after
                captured.windowTitle = read.windowTitle
                captured.url = read.url
            } else {
                let window = await Task.detached { SelectionReader.windowContext(pid: pid) }.value
                let found = await Task.detached { SelectionReader.surroundings(of: text, pid: pid, bundleID: bundleID) }.value
                captured.windowTitle = window.title
                captured.url = read?.url ?? window.url
                captured.before = found.before
                captured.after = found.after
                captured.trace += found.trace
            }
            deliver(captured)
        }
    }

    func deliver(_ text: CapturedText) {
        lastProblem = nil
        present?(text)
    }

    private func fail(_ message: String) {
        lastProblem = message
        NSSound.beep()
    }
}

private extension String {
    /// Equal apart from whitespace, since apps and pasteboards break lines differently.
    func isSameText(as other: String) -> Bool {
        split(whereSeparator: \.isWhitespace) == other.split(whereSeparator: \.isWhitespace)
    }
}
