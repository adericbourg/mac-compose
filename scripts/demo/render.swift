// Renders the README demos to docs/images/demo-*.webp: one Compose sequence each.
// Usage: swift scripts/demo/render.swift (from the repo root; needs img2webp from Homebrew's webp)
// noto-emoji_u1f601.png comes from googlefonts/noto-emoji (2D/png/512), SIL Open Font License 1.1 (noto-emoji-LICENSE).
import AppKit

let size: CGFloat = 800
let background = NSColor(srgbRed: 0x20 / 255, green: 0x2a / 255, blue: 0x36 / 255, alpha: 1)
let text = NSColor(srgbRed: 0xf6 / 255, green: 0xe9 / 255, blue: 0xd7 / 255, alpha: 1)
let highlight = NSColor(srgbRed: 0xf1 / 255, green: 0xa5 / 255, blue: 0x41 / 255, alpha: 1)

enum Output {
    case text(String)
    case image(NSImage) // emoji drawn from Noto art rather than the system's Apple Color Emoji
}

struct Demo {
    let name: String
    let keys: [String]
    let output: Output
    var pauseBeforeOutput = 0 // ms; a name other names continue (grin, grinning…) emits after the app's 1 s pause
}

struct Frame: Equatable {
    var pressed: Int? = nil
    var isTyped = false
    var isTypedHighlighted = false
    var isCursorOn = true
}

let compose = "option"

/// (duration ms, state) per step; the last step holds the result before looping.
func steps(_ demo: Demo) -> [(Int, Frame)] {
    var steps = [(1000, Frame())]
    for (i, key) in demo.keys.enumerated() {
        // Letters of an emoji name (after Compose, Compose) are typed like a word; other keys get the slow pace.
        let isNameLetter = key != compose && demo.keys.starts(with: [compose, compose])
        let (press, gap) = isNameLetter ? (450, 150) : (800, 300)
        steps.append((press, Frame(pressed: i)))
        if i < demo.keys.count - 1 { steps.append((gap, Frame())) }
    }
    if demo.pauseBeforeOutput > 0 { steps.append((demo.pauseBeforeOutput, Frame())) }
    steps.append((800, Frame(isTyped: true, isTypedHighlighted: true)))
    steps.append((2500, Frame(isTyped: true)))
    return steps
}

func draw(_ f: Frame, _ demo: Demo) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // Typed output and caret (y grows upwards)
    let baseline: CGFloat = 400
    var typedFont = NSFont.systemFont(ofSize: 150)
    var x: CGFloat = 150
    if case .text(let s) = demo.output {
        // A long kaomoji shrinks to fit and moves left so it's centered; short output keeps the 150 px margin.
        let width = NSAttributedString(string: s, attributes: [.font: typedFont]).size().width
        typedFont = .systemFont(ofSize: min(150, 150 * (size - 140) / width))
        x = min(x, (size - width * typedFont.pointSize / 150 - 20) / 2)
    }
    var typedWidth: CGFloat = 0
    if f.isTyped {
        switch demo.output {
        case .text(let s):
            let typed = NSAttributedString(string: s, attributes: [
                .font: typedFont, .foregroundColor: f.isTypedHighlighted ? highlight : text,
            ])
            typed.draw(at: NSPoint(x: x, y: baseline + typedFont.descender))
            typedWidth = typed.size().width
        case .image(let image):
            let side = typedFont.ascender - typedFont.descender - 20
            let rect = NSRect(x: x, y: baseline + typedFont.descender + 10, width: side, height: side)
            if f.isTypedHighlighted { // an emoji can't be recolored, so it gets a highlight outline
                let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -10, dy: -10), xRadius: 24, yRadius: 24)
                ring.lineWidth = 6
                highlight.setStroke()
                ring.stroke()
            }
            image.draw(in: rect)
            typedWidth = side + 14
        }
    }
    if f.isCursorOn {
        text.setFill()
        NSRect(x: x + typedWidth + 6, y: baseline + typedFont.descender + 10,
               width: 8, height: typedFont.ascender - typedFont.descender - 20).fill()
    }

    // Keycaps, one row sized to fit: letter keys are `unit` wide, Compose keys 1.47 units, gaps 0.2 units.
    let units = demo.keys.map { $0 == compose ? 1.47 : 1 }.reduce(0, +) + 0.2 * CGFloat(demo.keys.count - 1)
    let unit = min(150, (size - 120) / units)
    let gap = unit * 0.2, keyHeight = min(100, unit + 10), keyY: CGFloat = 110
    let keyFont = NSFont.systemFont(ofSize: min(40, unit * 0.32), weight: .medium)
    var keyX = (size - unit * units) / 2
    for (i, label) in demo.keys.enumerated() {
        let rect = NSRect(x: keyX, y: keyY, width: label == compose ? unit * 1.47 : unit, height: keyHeight)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 18, yRadius: 18)
        path.lineWidth = 4
        let isPressed = f.pressed == i
        if isPressed { highlight.setFill(); path.fill(); highlight.setStroke() } else { text.setStroke() }
        path.stroke()
        let caption = NSAttributedString(string: label, attributes: [
            .font: keyFont, .foregroundColor: isPressed ? background : text,
        ])
        let s = caption.size()
        caption.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
        keyX += rect.width + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func render(_ demo: Demo) throws {
    let steps = steps(demo)
    // Sample every 10 ms and keep a frame only when the picture changes.
    var runs: [(Frame, Int)] = []
    var start = 0
    for (duration, step) in steps {
        for t in stride(from: start, to: start + duration, by: 10) {
            var f = step
            f.isCursorOn = t % 1060 < 530 // macOS caret blink rate
            if let last = runs.last, last.0 == f { runs[runs.count - 1].1 += 10 } else { runs.append((f, 10)) }
        }
        start += duration
    }

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(demo.name)-\(getpid())")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    var args = ["img2webp", "-loop", "0", "-lossless"]
    for (i, (f, duration)) in runs.enumerated() {
        let png = tmp.appendingPathComponent("\(i).png")
        try draw(f, demo).write(to: png)
        args += ["-d", "\(duration)", png.path]
    }
    args += ["-o", "docs/images/demo-\(demo.name).webp"]

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { exit(p.terminationStatus) }
}

let grin = NSImage(contentsOfFile: "scripts/demo/noto-emoji_u1f601.png")!
for demo in [
    Demo(name: "accent", keys: [compose, "'", "e"], output: .text("é")),
    Demo(name: "emoji", keys: [compose, compose, "g", "r", "i", "n"], output: .image(grin), pauseBeforeOutput: 1000),
    Demo(name: "kaomoji", keys: [compose, compose, "t", "f", "l", "i", "p"], output: .text("(╯°□°)╯︵ ┻━┻")),
] {
    try render(demo)
}
