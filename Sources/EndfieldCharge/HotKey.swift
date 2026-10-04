import Carbon

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    private static let keys: [String: UInt32] = [
        "H": UInt32(kVK_ANSI_H), "B": UInt32(kVK_ANSI_B),
        "E": UInt32(kVK_ANSI_E), "P": UInt32(kVK_ANSI_P)
    ]

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == 0x45464348, identity.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().onPress?()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult func configure(enabled: Bool, key: String) -> OSStatus {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        guard enabled else { return noErr }
        let identity = EventHotKeyID(signature: 0x45464348, id: 1)
        return RegisterEventHotKey(Self.keys[key] ?? UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
            identity, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
