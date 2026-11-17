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

    /// The device flag of the left twin, which keeps working as a modifier while this key is held.
    var leftDeviceFlag: UInt64 {
        switch self {
        case .rightOption: 0x20
        case .rightCommand: 0x08
        case .rightControl: 0x01
        }
    }

    var modifierMask: CGEventFlags {
        switch self {
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        case .rightControl: .maskControl
        }
    }
}

/// Marks the events this app posts, so its own tap lets them through.
private let syntheticEventMarker: Int64 = 0x4D_43_4F_4D // "MCOM"
private let escapeKeyCode: Int64 = 53
/// Composing is cancelled after this long without a key, so a Compose tap by mistake doesn't keep swallowing keys.
private let composingTimeout: TimeInterval = 5

/// Watches the keyboard: a Compose key tap starts composing, the keys typed next are swallowed and fed to the engine,
/// and the composed text is typed in their place.
@MainActor final class KeyTap {
    var isEnabled = true {
        didSet { cancel() }
    }
    /// Holding the Compose key while typing starts composing too; that key then no longer acts as a modifier.
    var isHoldEnabled = false {
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
        didSet {
            guard isComposing != oldValue else { return }
            onComposingChanged(isComposing)
            if isComposing { restartTimeout() } else { timeoutTimer?.invalidate() }
        }
    }
    private var timeoutTimer: Timer?
    private(set) var sequences = loadDefaultComposeSequences()
    let emoji = loadDefaultEmojiNames()
    private lazy var engine = ComposeEngine(sequences: sequences, emoji: emoji)
    private var detector: ComposeKeyDetector
    /// Keys whose keyDown was swallowed: their keyUp is swallowed too, even once composing is over.
    private var swallowedKeyCodes: Set<Int64> = []
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(composeKey: ComposeKey) {
        self.composeKey = composeKey
        detector = ComposeKeyDetector(keyCode: composeKey.rawValue)
    }

    func reloadSequences() {
        sequences = loadDefaultComposeSequences()
        engine = ComposeEngine(sequences: sequences, emoji: emoji)
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
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
        return true
    }

    /// Drops the event tap, e.g. once Accessibility is revoked.
    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
        cancel()
    }

    /// True when the event must be swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Once Accessibility is revoked the tap stays off: the main timer drops it.
            if let port, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
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
            let isComposeKeyHeld = isHoldEnabled && event.flags.rawValue & composeKey.deviceFlag != 0
            if isComposeKeyHeld { isComposing = true }
            guard isComposing else { return false }
            var flags = event.flags
            if isComposeKeyHeld && flags.rawValue & composeKey.leftDeviceFlag == 0 { flags.remove(composeKey.modifierMask) }
            // A shortcut (⌘Q, ⌃C…) aborts composing and goes through untouched.
            if !flags.isDisjoint(with: [.maskCommand, .maskControl]) {
                cancel()
                return false
            }
            swallowedKeyCodes.insert(keyCode)
            if keyCode == escapeKeyCode {
                cancel()
                return true
            }
            // Empty for a dead key: nothing to feed, the next key brings the character.
            let nsEvent = NSEvent(cgEvent: event)
            // The held Compose key must not alter the character (Right Option + ' is ', not æ).
            let characters = isComposeKeyHeld ? nsEvent?.charactersIgnoringModifiers : nsEvent?.characters
            for character in characters ?? "" {
                feed(character)
                if !isComposing { break }
            }
            return true
        case .keyUp:
            return swallowedKeyCodes.remove(keyCode) != nil
        default:
            detector.otherInputPressed()
            if isComposing { cancel() }
            return false
        }
    }

    private func feed(_ character: Character) {
        switch engine.feed(character) {
        case .pending:
            restartTimeout()
        case .emit(let text):
            isComposing = false
            type(text)
        case .invalid:
            isComposing = false
            NSSound.beep()
        }
    }

    private func restartTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: composingTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
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
