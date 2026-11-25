import Carbon
import Foundation

public enum AileronHotKey: UInt32, CaseIterable, Sendable {
    case toggleHUD = 1
    case toggleDashboard = 2
    case toggleListening = 3
    case answerLast = 4
    case captureScreen = 5
    case toggleMic = 6

    public var keyCode: UInt32 {
        switch self {
        case .toggleHUD: return UInt32(kVK_ANSI_Backslash)
        case .toggleDashboard: return UInt32(kVK_ANSI_D)
        case .toggleListening: return UInt32(kVK_ANSI_A)
        case .answerLast: return UInt32(kVK_ANSI_L)
        case .captureScreen: return UInt32(kVK_ANSI_S)
        case .toggleMic: return UInt32(kVK_ANSI_M)
        }
    }

    public var modifiers: UInt32 {
        switch self {
        case .toggleHUD: return UInt32(cmdKey)
        case .toggleDashboard, .toggleListening, .answerLast, .captureScreen, .toggleMic:
            return UInt32(cmdKey | shiftKey)
        }
    }

    public var displayShortcut: String {
        switch self {
        case .toggleHUD: return "⌘\\"
        case .toggleDashboard: return "⌘⇧D"
        case .toggleListening: return "⌘⇧A"
        case .answerLast: return "⌘⇧L"
        case .captureScreen: return "⌘⇧S"
        case .toggleMic: return "⌘⇧M"
        }
    }

    public var label: String {
        switch self {
        case .toggleHUD: return "Show / Hide Floating Bar"
        case .toggleDashboard: return "Open Main Window"
        case .toggleListening: return "Start / Stop System Audio"
        case .answerLast: return "Answer Last Utterance"
        case .captureScreen: return "Capture Screen & Analyze"
        case .toggleMic: return "Live Streaming Voice Ask"
        }
    }
}

@MainActor
public final class HotKeyManager {
    private static let signature: OSType = 0x41494C52
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let onTrigger: @MainActor (AileronHotKey) -> Void
    public private(set) var registrationStatuses: [UInt32: Bool] = [:]

    public init(onTrigger: @escaping @MainActor (AileronHotKey) -> Void) {
        self.onTrigger = onTrigger
        installEventHandler()
        registerAll()
    }

    public var conflictedShortcuts: [String] {
        AileronHotKey.allCases
            .filter { registrationStatuses[$0.rawValue] == false }
            .map(\.displayShortcut)
    }

    public func reregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registerAll()
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == HotKeyManager.signature,
                      let key = AileronHotKey(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger(key)
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func registerAll() {
        var statuses: [UInt32: Bool] = [:]
        for action in AileronHotKey.allCases {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                action.keyCode,
                action.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                statuses[action.rawValue] = true
            } else {
                statuses[action.rawValue] = false
            }
        }
        registrationStatuses = statuses
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
