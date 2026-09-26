import AppKit

/// The menu bar icon: a left click opens the app's window, a right click (or Control-click)
/// shows the menu with capture, Settings and Quit. SwiftUI's `MenuBarExtra` can't tell the
/// two clicks apart, so this is a plain `NSStatusItem`.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let windows: AppWindows
    private let preview: PreviewPanelController

    init(windows: AppWindows, preview: PreviewPanelController) {
        self.windows = windows
        self.preview = preview
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Smart Calendar Classifier"
        updateIcon()
        observeCapturing()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            windows.showMain()
        }
    }

    private func showMenu() {
        let coordinator = CaptureCoordinator.shared
        let menu = NSMenu()
        // The app that was frontmost before the click still owns the selection.
        let shortcut = ShortcutStore.shared.shortcut
        menu.addItem(action("Add Selected Text to Calendar", key: shortcut.key, modifiers: shortcut.menuModifiers) {
            coordinator.captureFrontmostSelection()
        })
        if let problem = coordinator.lastProblem {
            let note = NSMenuItem(title: problem, action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        if !AccessibilityPermission.shared.isTrusted {
            menu.addItem(action("Allow Accessibility Access…") { AccessibilityPermission.shared.prompt() })
        }
        if preview.hasLastResult {
            menu.addItem(action("Show Last Result") { [preview] in preview.reopen() })
        }
        menu.addItem(.separator())
        menu.addItem(action("Open Smart Calendar Classifier") { [windows] in windows.showMain() })
        menu.addItem(action("Settings…", key: ",") { [windows] in windows.showSettings() })
        menu.addItem(action("Setup Guide…") { [windows] in windows.showOnboarding() })
        menu.addItem(.separator())
        menu.addItem(action("Quit Smart Calendar Classifier", key: "q") { NSApp.terminate(nil) })

        // Attaching the menu only for this click keeps left clicks free to open the window.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func action(
        _ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, _ handler: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        let target = MenuAction(handler)
        menuItem.target = target
        menuItem.representedObject = target // NSMenuItem holds its target weakly.
        return menuItem
    }

    private func updateIcon() {
        let symbol = CaptureCoordinator.shared.isCapturing ? "calendar.badge.clock" : "calendar.badge.plus"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Smart Calendar Classifier")
        image?.isTemplate = true
        item.button?.image = image
    }

    /// Shows a clock on the icon while a selection is being read.
    private func observeCapturing() {
        withObservationTracking {
            _ = CaptureCoordinator.shared.isCapturing
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observeCapturing()
            }
        }
    }
}

private final class MenuAction: NSObject {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor @objc func run() {
        handler()
    }
}
