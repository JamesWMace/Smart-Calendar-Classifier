import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the new shortcut (Esc cancels).
struct ShortcutRecorder: View {
    private let store = ShortcutStore.shared
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(store.isRecording ? "Type the new shortcut…" : store.shortcut.display) {
                    store.isRecording ? stop() : start()
                }
                .frame(minWidth: 150)
                if store.shortcut != .standard && !store.isRecording {
                    Button("Reset") { store.shortcut = .standard }
                        .buttonStyle(.link)
                }
            }
            if let message = store.registrationError ?? hint {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        hint = "Include ⌘, ⌃ or ⌥. Esc cancels."
        store.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let shortcut = GlobalShortcut(event: event) {
                store.shortcut = shortcut
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hint = nil
        if store.isRecording { store.isRecording = false }
    }
}
