import AppKit
@preconcurrency import ApplicationServices

private let isEnabledKey = "isEnabled"
private let composeKeyKey = "composeKey"
private let isHoldEnabledKey = "isHoldEnabled"

/// The menu bar item and its menu; owns the settings.
@MainActor final class StatusMenu: NSObject {
    private let keyTap: KeyTap
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let holdItem = NSMenuItem(title: "Compose while held", action: #selector(toggleHold), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Accessibility permission needed", action: nil, keyEquivalent: "")
    private var composeKeyItems: [NSMenuItem] = []

    init(keyTap: KeyTap) {
        self.keyTap = keyTap
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        enabledItem.target = self
        menu.addItem(enabledItem)
        let composeKeyMenu = NSMenu()
        for key in ComposeKey.allCases {
            let item = NSMenuItem(title: key.title, action: #selector(selectComposeKey), keyEquivalent: "")
            item.target = self
            item.tag = Int(key.rawValue)
            composeKeyMenu.addItem(item)
            composeKeyItems.append(item)
        }
        let composeKeyItem = NSMenuItem(title: "Compose key", action: nil, keyEquivalent: "")
        composeKeyItem.submenu = composeKeyMenu
        menu.addItem(composeKeyItem)
        holdItem.target = self
        menu.addItem(holdItem)
        let reloadItem = NSMenuItem(title: "Reload sequences", action: #selector(reloadSequences), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let commit = (info?["MacComposeCommit"] as? String).map { " (\($0))" } ?? ""
        let versionItem = NSMenuItem(title: "Version \(version)\(commit)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        statusItem.menu = menu

        keyTap.onComposingChanged = { [weak self] isComposing in self?.updateIcon(isComposing: isComposing) }
        updateIcon(isComposing: false)
        updateItems()
    }

    var isPermissionNeeded = true {
        didSet { permissionItem.isHidden = !isPermissionNeeded }
    }

    @objc private func toggleEnabled() {
        keyTap.isEnabled.toggle()
        UserDefaults.standard.set(keyTap.isEnabled, forKey: isEnabledKey)
        updateItems()
        updateIcon(isComposing: false)
    }

    @objc private func toggleHold() {
        keyTap.isHoldEnabled.toggle()
        UserDefaults.standard.set(keyTap.isHoldEnabled, forKey: isHoldEnabledKey)
        updateItems()
    }

    @objc private func selectComposeKey(_ sender: NSMenuItem) {
        guard let key = ComposeKey(rawValue: Int64(sender.tag)) else { return }
        keyTap.composeKey = key
        UserDefaults.standard.set(key.rawValue, forKey: composeKeyKey)
        updateItems()
    }

    @objc private func reloadSequences() {
        keyTap.reloadSequences()
    }

    private func updateItems() {
        enabledItem.state = keyTap.isEnabled ? .on : .off
        holdItem.state = keyTap.isHoldEnabled ? .on : .off
        for item in composeKeyItems {
            item.state = item.tag == Int(keyTap.composeKey.rawValue) ? .on : .off
        }
    }

    private func updateIcon(isComposing: Bool) {
        let image = NSImage(
            systemSymbolName: isComposing ? "keyboard.fill" : "keyboard",
            accessibilityDescription: isComposing ? "MacCompose, composing" : "MacCompose"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !keyTap.isEnabled
    }
}

// What LSUIElement does in the bundle, for a bare `swift run` binary.
NSApplication.shared.setActivationPolicy(.accessory)
UserDefaults.standard.register(defaults: [isEnabledKey: true, composeKeyKey: ComposeKey.rightOption.rawValue, isHoldEnabledKey: false])

let keyTap = KeyTap(composeKey: ComposeKey(rawValue: Int64(UserDefaults.standard.integer(forKey: composeKeyKey))) ?? .rightOption)
keyTap.isEnabled = UserDefaults.standard.bool(forKey: isEnabledKey)
keyTap.isHoldEnabled = UserDefaults.standard.bool(forKey: isHoldEnabledKey)
let statusMenu = StatusMenu(keyTap: keyTap)

_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
statusMenu.isPermissionNeeded = !keyTap.start()
if statusMenu.isPermissionNeeded {
    // The tap can only be created once Accessibility is granted.
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
        let isStarted = MainActor.assumeIsolated { keyTap.start() }
        guard isStarted else { return }
        timer.invalidate()
        MainActor.assumeIsolated { statusMenu.isPermissionNeeded = false }
    }
}

NSApplication.shared.run()
