import AppKit
import SmartCalendarCore
import SwiftUI

/// A floating panel that takes keyboard focus without activating the app, so the app the
/// text came from stays frontmost — the way Spotlight behaves.
final class PreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows one preview panel per capture, next to the mouse, and keeps its top edge in place
/// while events stream in and the panel grows.
@MainActor
final class PreviewPanelController: NSObject, NSWindowDelegate {
    private let calendars: CalendarService
    private let history: HistoryStore
    private let panel = PreviewPanel()
    private var model: PreviewModel?
    /// Where the panel's top-left corner should stay as its height changes.
    private var anchor: NSPoint?

    init(calendars: CalendarService, history: HistoryStore) {
        self.calendars = calendars
        self.history = history
        super.init()
        panel.delegate = self
    }

    func show(_ capture: CapturedText) {
        model?.cancel()
        let model = PreviewModel(capture: capture, calendars: calendars, history: history)
        self.model = model

        let hosting = NSHostingController(rootView: PreviewView(model: model) { [weak self] in self?.close() }
            .environment(calendars))
        hosting.sizingOptions = [.preferredContentSize]
        // The (hidden) title bar would otherwise reserve an empty strip above the content.
        hosting.safeAreaRegions = []
        panel.contentViewController = hosting

        anchor = nil
        panel.layoutIfNeeded()
        placeNearMouse()
        panel.makeKeyAndOrderFront(nil)
        model.start()
    }

    #if DEBUG
    /// The panel, for debug snapshots.
    var debugPanel: NSPanel { panel }
    /// The current capture's log.
    var debugTrace: [String] {
        (model?.capture.trace ?? []) + ["PROMPT:", model?.debugPrompt ?? "", model?.timing ?? "extraction not finished"]
    }
    #endif

    func close() {
        model?.cancel()
        panel.orderOut(nil)
    }

    /// Whether there's a previous result to bring back (e.g. to undo after closing).
    var hasLastResult: Bool { model != nil }

    /// Shows the last panel again, as it was left.
    func reopen() {
        guard model != nil else { return }
        placeNearMouse()
        panel.makeKeyAndOrderFront(nil)
    }

    private func placeNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        // Below and to the right of the pointer, kept fully on screen.
        let x = min(max(mouse.x + 12, visible.minX + 8), visible.maxX - size.width - 8)
        let top = max(min(mouse.y - 12, visible.maxY - 8), visible.minY + min(size.height, 560) + 8)
        anchor = NSPoint(x: x, y: top)
        panel.setFrameTopLeftPoint(anchor!)
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // AppKit grows windows upward from their bottom edge; keep the top where it was.
        guard let anchor, panel.frame.maxY != anchor.y || panel.frame.minX != anchor.x else { return }
        panel.setFrameTopLeftPoint(anchor)
    }

    func windowDidMove(_ notification: Notification) {
        if anchor != nil { anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY) }
    }
}
