import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's `RegisterEventHotKey` is still the only public
/// API for this, and unlike event taps it needs no permission.
@MainActor
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var isDispatcherInstalled = false

    private let id: UInt32
    private var reference: EventHotKeyRef?

    /// - Parameters:
    ///   - keyCode: a virtual key code such as `kVK_ANSI_C`.
    ///   - modifiers: Carbon modifier flags such as `controlKey | optionKey`.
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installDispatcherIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x5343_4331), id: id) // 'SCC1'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    isolated deinit {
        if let reference { UnregisterEventHotKey(reference) }
        Self.handlers[id] = nil
    }

    private static func installDispatcherIfNeeded() {
        guard !isDispatcherInstalled else { return }
        isDispatcherInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotKey.handlers[id]?() }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}
