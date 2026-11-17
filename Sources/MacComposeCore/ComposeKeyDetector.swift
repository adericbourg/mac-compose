/// Tells a Compose key tap (the modifier pressed then released, nothing in between) from the same modifier used as a modifier.
public struct ComposeKeyDetector: Sendable {
    public let keyCode: Int64
    private var isArmed = false

    public init(keyCode: Int64) {
        self.keyCode = keyCode
    }

    /// For each modifier change; `isKeyDown` tells whether the Compose key is down after it. True on a Compose tap.
    public mutating func modifierChanged(keyCode: Int64, isKeyDown: Bool) -> Bool {
        let wasArmed = isArmed
        isArmed = keyCode == self.keyCode && isKeyDown
        return keyCode == self.keyCode && !isKeyDown && wasArmed
    }

    /// For any key or mouse button press: the modifier held now is a plain modifier.
    public mutating func otherInputPressed() {
        isArmed = false
    }
}
