import Carbon
import ChargeCore

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    static let availableKeys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private static let keys: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z)
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

    @discardableResult func configure(enabled: Bool, key: String, modifiers: Set<ShortcutModifier>) -> OSStatus {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        guard enabled else { return noErr }
        guard let keyCode = Self.keys[key], !modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return OSStatus(paramErr)
        }
        let mask = modifiers.reduce(UInt32(0)) { result, modifier in
            switch modifier {
            case .command: return result | UInt32(cmdKey)
            case .control: return result | UInt32(controlKey)
            case .option: return result | UInt32(optionKey)
            case .shift: return result | UInt32(shiftKey)
            }
        }
        let identity = EventHotKeyID(signature: 0x45464348, id: 1)
        return RegisterEventHotKey(keyCode, mask,
            identity, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
