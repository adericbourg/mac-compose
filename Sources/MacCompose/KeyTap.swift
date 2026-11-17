import AppKit
import MacComposeCore

enum ComposeKey: Int64, CaseIterable {
    case rightOption = 61, rightCommand = 54, rightControl = 62

    var title: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        }
    }

    /// The NX_DEVICE*KEYMASK bit of CGEventFlags, set while this very key (not its left twin) is down.
    var deviceFlag: UInt64 {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightControl: 0x2000
        }
    }
}

/// Marks the events this app posts, so its own tap lets them through.
private let syntheticEventMarker: Int64 = 0x4D_43_4F_4D // "MCOM"
private let escapeKeyCode: Int64 = 53

/// Watches the keyboard: a Compose key tap starts composing, the keys typed next are swallowed and fed to the engine,
/// and the composed text is typed in their place.
@MainActor final class KeyTap {
    var isEnabled = true {
        didSet { cancel() }
    }
    var composeKey: ComposeKey {
        didSet {
            detector = ComposeKeyDetector(keyCode: composeKey.rawValue)
            cancel()
        }
    }
    var onComposingChanged: (Bool) -> Void = { _ in }

    private var isComposing = false {
        didSet { if isComposing != oldValue { onComposingChanged(isComposing) } }
    }
    private var engine = ComposeEngine(sequences: loadDefaultComposeSequences())
    private var detector: ComposeKeyDetector
    /// Keys whose keyDown was swallowed: their keyUp is swallowed too, even once composing is over.
    private var swallowedKeyCodes: Set<Int64> = []
    private var port: CFMachPort?

    init(composeKey: ComposeKey) {
        self.composeKey = composeKey
        detector = ComposeKeyDetector(keyCode: composeKey.rawValue)
    }

    func reloadSequences() {
        engine = ComposeEngine(sequences: loadDefaultComposeSequences())
        cancel()
    }

    /// Creates the event tap once; false while Accessibility is not granted.
    func start() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // The tap's run loop source is on the main run loop.
                let isSwallowed = MainActor.assumeIsolated {
                    Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
                }
                return isSwallowed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        self.port = port
        return true
    }

    /// True when the event must be swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard isEnabled, event.getIntegerValueField(.eventSourceUserData) != syntheticEventMarker else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            let isComposeKeyDown = event.flags.rawValue & composeKey.deviceFlag != 0
            if detector.modifierChanged(keyCode: keyCode, isKeyDown: isComposeKeyDown) {
                if isComposing { feed(composeKeyCharacter) } else { isComposing = true }
            }
            return false
        case .keyDown:
            detector.otherInputPressed()
            swallowedKeyCodes.remove(keyCode)
            guard isComposing else { return false }
            // A shortcut (⌘Q, ⌃C…) aborts composing and goes through untouched.
            if !event.flags.isDisjoint(with: [.maskCommand, .maskControl]) {
                cancel()
                return false
            }
            swallowedKeyCodes.insert(keyCode)
            if keyCode == escapeKeyCode {
                cancel()
                return true
            }
            // Empty for a dead key: nothing to feed, the next key brings the character.
            for character in NSEvent(cgEvent: event)?.characters ?? "" {
                feed(character)
                if !isComposing { break }
            }
            return true
        case .keyUp:
            return swallowedKeyCodes.remove(keyCode) != nil
        default:
            detector.otherInputPressed()
            return false
        }
    }

    private func feed(_ character: Character) {
        switch engine.feed(character) {
        case .pending:
            break
        case .emit(let text):
            isComposing = false
            type(text)
        case .invalid:
            isComposing = false
            NSSound.beep()
        }
    }

    private func cancel() {
        engine.reset()
        isComposing = false
    }

    private func type(_ text: String) {
        // Receivers keep only the first 20 UTF-16 units of an event's string (observed limit, undocumented): one event per chunk.
        var chunks: [[UniChar]] = [[]]
        for character in text {
            let units = Array(String(character).utf16)
            if chunks[chunks.count - 1].count + units.count > 20 { chunks.append([]) }
            chunks[chunks.count - 1] += units
        }
        for chunk in chunks {
            for isKeyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isKeyDown) else { continue }
                // No modifier: a still-held Shift or Option must not alter the text.
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
