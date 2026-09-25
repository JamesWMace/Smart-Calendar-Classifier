import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SmartCalendarCore

/// Text the user selected somewhere, plus everything we could learn about where it came from.
struct CapturedText: Sendable {
    enum Method: String, Sendable {
        case accessibility = "Accessibility"
        case webContent = "Web content"
        case clipboard = "Copy (⌘C)"
        case service = "Services menu"
        case shortcut = "Shortcuts"
    }

    var selection: String
    var before: String?
    var after: String?
    var appName: String?
    var windowTitle: String?
    var url: URL?
    var method: Method
    /// What the reader tried, shown in Try It to diagnose apps that don't cooperate.
    var trace: [String] = []
}

struct WindowContext: Sendable {
    var title: String?
    var url: URL?
}

/// Reads the current selection and its surroundings from another app (decision #4).
///
/// Order of attempts:
/// 1. Web content (Safari, Mail messages, Chromium/Electron) through WebKit's text-marker
///    accessibility API, which also yields the text around the selection and the page URL.
/// 2. Native text views through `AXSelectedText` + `AXValue`.
/// 3. Posting ⌘C and reading the clipboard, which is then restored (selection only).
///
/// The Accessibility calls block while the other app answers, so call them off the main thread.
enum SelectionReader {
    static let maxBefore = 2_000
    static let maxAfter = 1_000

    /// Chromium browsers expose web content to Accessibility only once asked to.
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// Selection plus surroundings, or `nil` with a trace of why nothing was found.
    static func readWithAccessibility(pid: pid_t, bundleID: String?) -> (CapturedText?, [String]) {
        var trace: [String] = []
        let app = application(pid: pid, bundleID: bundleID, trace: &trace)
        let window = windowContext(of: app)

        var focused = element(app, kAXFocusedUIElementAttribute)
        var web = webArea(in: app, focused: focused)
        if web == nil, let bundleID, chromiumBrowsers.contains(bundleID) {
            // The page's accessibility tree is built asynchronously the first time it's requested.
            trace.append("waiting for the browser's page tree")
            Thread.sleep(forTimeInterval: 0.5)
            focused = element(app, kAXFocusedUIElementAttribute)
            web = webArea(in: app, focused: focused)
        }

        if let web {
            trace.append("web area found")
            if var captured = readWebSelection(web, trace: &trace) {
                captured.windowTitle = window.title
                captured.url = captured.url ?? window.url
                captured.trace = trace
                return (captured, trace)
            }
        } else {
            trace.append("no web area")
        }

        guard let focused else {
            // Common when the app isn't frontmost, e.g. after the Services menu activated us.
            trace.append("no focused element")
            return (nil, trace)
        }
        guard let selected = string(focused, kAXSelectedTextAttribute), !selected.isBlank else {
            trace.append("focused element has no selected text")
            return (nil, trace)
        }
        var captured = CapturedText(selection: selected, windowTitle: window.title, url: window.url, method: .accessibility)
        if let value = string(focused, kAXValueAttribute),
           let range = range(focused, kAXSelectedTextRangeAttribute),
           let slice = SurroundingText.slice(value, selection: range, maxBefore: maxBefore, maxAfter: maxAfter),
           slice.selected == selected {
            captured.before = slice.before
            captured.after = slice.after
            trace.append("text view: selection + surroundings")
        } else {
            trace.append("text view: selection only")
        }
        captured.trace = trace
        return (captured, trace)
    }

    /// For a selection that arrived without a position (⌘C, Services): find it in the page or
    /// text view and return what surrounds it.
    static func surroundings(of selection: String, pid: pid_t, bundleID: String?) -> (before: String?, after: String?, trace: [String]) {
        var trace: [String] = []
        let app = application(pid: pid, bundleID: bundleID, trace: &trace)
        let focused = element(app, kAXFocusedUIElementAttribute)
        let document: String?
        if let web = webArea(in: app, focused: focused) {
            document = pageText(web, trace: &trace)
        } else {
            document = focused.flatMap { string($0, kAXValueAttribute) }
            trace.append(document == nil ? "no document text" : "searched text view")
        }
        guard let document, let range = SurroundingText.locate(selection, in: document),
              let slice = SurroundingText.slice(document, selection: range, maxBefore: maxBefore, maxAfter: maxAfter) else {
            trace.append("selection not found in document")
            return (nil, nil, trace)
        }
        trace.append("found selection in document")
        return (slice.before.isBlank ? nil : slice.before, slice.after.isBlank ? nil : slice.after, trace)
    }

    static func windowContext(pid: pid_t) -> WindowContext {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return windowContext(of: app)
    }

    private static func application(pid: pid_t, bundleID: String?, trace: inout [String]) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        // Generous: fetching a long page's text can take a moment.
        AXUIElementSetMessagingTimeout(app, 2.0)
        // Electron apps build their accessibility tree when asked this way…
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // …and Chromium browsers this way (what screen readers set).
        if let bundleID, chromiumBrowsers.contains(bundleID) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            trace.append("enabled Chromium accessibility")
        }
        return app
    }

    /// Last resort: copy the selection with a synthetic ⌘C, then put the clipboard back.
    @MainActor
    static func readWithCopy() async -> String? {
        await waitForModifierKeysReleased()
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let changeCount = pasteboard.changeCount

        postCommandC()
        var copied: String?
        for _ in 0..<25 where copied == nil {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != changeCount { copied = pasteboard.string(forType: .string) ?? "" }
        }

        if pasteboard.changeCount != changeCount {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
        return copied.flatMap { $0.isBlank ? nil : $0 }
    }

    // MARK: - Web content

    private static func readWebSelection(_ webArea: AXUIElement, trace: inout [String]) -> CapturedText? {
        guard let selection = attribute(webArea, "AXSelectedTextMarkerRange") else {
            trace.append("page has no selection range")
            return nil
        }
        guard let selected = parameterized(webArea, "AXStringForTextMarkerRange", selection) as? String, !selected.isBlank else {
            trace.append("page selection is empty")
            return nil
        }
        var captured = CapturedText(selection: selected, url: url(webArea, "AXURL"), method: .webContent)
        trace.append("page selection")

        // Preferred: read just the text on either side of the selection.
        var before = "", after = ""
        if let start = parameterized(webArea, "AXStartTextMarkerForTextMarkerRange", selection),
           let end = parameterized(webArea, "AXEndTextMarkerForTextMarkerRange", selection) {
            let startIndex = parameterized(webArea, "AXIndexForTextMarker", start) as? Int
            let endIndex = parameterized(webArea, "AXIndexForTextMarker", end) as? Int
            if startIndex == nil || endIndex == nil { trace.append("no marker indexes") }
            let beforeStart = startIndex.flatMap { marker(webArea, index: max(0, $0 - maxBefore)) } ?? attribute(webArea, "AXStartTextMarker")
            let afterEnd = endIndex.flatMap { marker(webArea, index: $0 + maxAfter) } ?? attribute(webArea, "AXEndTextMarker")
            before = beforeStart.flatMap { webText(webArea, from: $0, to: start) } ?? ""
            after = afterEnd.flatMap { webText(webArea, from: end, to: $0) } ?? ""
        } else {
            trace.append("no selection start/end markers")
        }
        var stitched = before + selected + after
        var range = NSRange(location: before.utf16.count, length: selected.utf16.count)

        // Otherwise (Chrome): read the page's text and find the selection in it.
        if before.isBlank && after.isBlank {
            guard let page = pageText(webArea, trace: &trace), let found = SurroundingText.locate(selected, in: page) else {
                trace.append("selection not found in page text")
                return captured
            }
            stitched = page
            range = found
        }
        if let slice = SurroundingText.slice(stitched, selection: range, maxBefore: maxBefore, maxAfter: maxAfter) {
            captured.before = slice.before.isBlank ? nil : slice.before
            captured.after = slice.after.isBlank ? nil : slice.after
            trace.append("surroundings: \(slice.before.count) chars before, \(slice.after.count) after")
        }
        return captured
    }

    /// All of a page's text: through text markers where supported (Safari/WebKit), otherwise
    /// by collecting the page's text nodes in document order (Chrome).
    private static func pageText(_ webArea: AXUIElement, trace: inout [String]) -> String? {
        if let start = attribute(webArea, "AXStartTextMarker"), let end = attribute(webArea, "AXEndTextMarker"),
           let text = webText(webArea, from: start, to: end), !text.isBlank {
            trace.append("read page text (\(text.count) chars)")
            return text
        }
        let text = textNodes(under: webArea)
        trace.append(text.isEmpty ? "no page text" : "collected page text nodes (\(text.count) chars)")
        return text.isEmpty ? nil : text
    }

    /// Depth-first over the page, joining static text; one IPC round trip per node.
    private static func textNodes(under root: AXUIElement, maxNodes: Int = 6_000, maxLength: Int = 400_000) -> String {
        let names = [kAXRoleAttribute, kAXValueAttribute, kAXChildrenAttribute] as CFArray
        var pieces: [String] = []
        var length = 0, visited = 0
        var stack = [root]
        while let element = stack.popLast(), visited < maxNodes, length < maxLength {
            visited += 1
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                  let list = values as? [CFTypeRef], list.count == 3 else { continue }
            if list[0] as? String == kAXStaticTextRole, let text = list[1] as? String, !text.isBlank {
                pieces.append(text)
                length += text.count
            }
            if let children = list[2] as? [CFTypeRef] {
                stack += children.reversed().compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
            }
        }
        return pieces.joined(separator: "\n")
    }

    private static func marker(_ webArea: AXUIElement, index: Int) -> CFTypeRef? {
        parameterized(webArea, "AXTextMarkerForIndex", index as CFNumber)
    }

    private static func webText(_ webArea: AXUIElement, from start: CFTypeRef, to end: CFTypeRef) -> String? {
        guard let range = parameterized(webArea, "AXTextMarkerRangeForUnorderedTextMarkers", [start, end] as CFArray) else { return nil }
        return parameterized(webArea, "AXStringForTextMarkerRange", range) as? String
    }

    /// Browser chrome that never contains the page; skipping it keeps the search short.
    private static let nonPageRoles: Set<String> = ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXMenu", "AXScrollBar", "AXButton"]

    /// The web area holding the focused element, or else the page in the app's front window.
    /// The window search matters when the app isn't frontmost and reports no focused element.
    private static func webArea(in app: AXUIElement, focused: AXUIElement?) -> AXUIElement? {
        var current = focused
        for _ in 0..<40 {
            guard let element = current else { break }
            if string(element, kAXRoleAttribute) == "AXWebArea" { return element }
            current = self.element(element, kAXParentAttribute)
        }
        let window = element(app, kAXFocusedWindowAttribute)
            ?? element(app, kAXMainWindowAttribute)
            ?? elements(app, kAXWindowsAttribute).first
        // Breadth-first finds the top-level page before any embedded frames.
        var queue = window.map { [$0] } ?? []
        var visited = 0
        while !queue.isEmpty, visited < 2_000 {
            let element = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" { return element }
            if !nonPageRoles.contains(role) { queue += elements(element, kAXChildrenAttribute) }
        }
        return nil
    }

    // MARK: - Window

    private static func windowContext(of app: AXUIElement) -> WindowContext {
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute) else {
            return WindowContext()
        }
        let title = string(window, kAXTitleAttribute).flatMap { $0.isBlank ? nil : $0 }
        // Only web addresses; local file paths add noise and the title already names the file.
        let document = string(window, kAXDocumentAttribute).flatMap(URL.init(string:))
        let url = document.flatMap { ["http", "https"].contains($0.scheme) ? $0 : nil }
        return WindowContext(title: title, url: url)
    }

    // MARK: - Keyboard

    @MainActor
    private static func waitForModifierKeysReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<50 where !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Accessibility helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func parameterized(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func url(_ element: AXUIElement, _ name: String) -> URL? {
        attribute(element, name) as? URL
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let values = attribute(element, name) as? [CFTypeRef] else { return [] }
        return values.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private static func range(_ element: AXUIElement, _ name: String) -> NSRange? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
