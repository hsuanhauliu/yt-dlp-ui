// Generates Sources/Assets.xcassets/AppIcon.appiconset from a single drawn icon.
// Run via scripts/make-icon.sh.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appending(path: "Sources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-square background with a vertical blue gradient.
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = rect.width * 0.2237
    let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.25, green: 0.58, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.11, green: 0.36, blue: 0.86, alpha: 1),
    ])!.draw(in: bg, angle: -90)

    // Download glyph: rounded stem + arrowhead + tray line, in white.
    NSColor.white.set()
    let cx = size / 2

    let stemW = size * 0.13
    NSBezierPath(
        roundedRect: CGRect(x: cx - stemW / 2, y: size * 0.46, width: stemW, height: size * 0.26),
        xRadius: stemW / 2, yRadius: stemW / 2
    ).fill()

    let headW = size * 0.34
    let head = NSBezierPath()
    head.move(to: CGPoint(x: cx - headW / 2, y: size * 0.50))
    head.line(to: CGPoint(x: cx + headW / 2, y: size * 0.50))
    head.line(to: CGPoint(x: cx, y: size * 0.28))
    head.close()
    head.fill()

    let trayW = size * 0.42
    let trayH = size * 0.11
    NSBezierPath(
        roundedRect: CGRect(x: cx - trayW / 2, y: size * 0.16, width: trayW, height: trayH),
        xRadius: trayH / 2, yRadius: trayH / 2
    ).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (pt, scale) in entries {
    let name = "icon_\(pt)x\(pt)@\(scale)x.png"
    try! drawIcon(px: pt * scale).write(to: iconset.appending(path: name))
    images.append(["size": "\(pt)x\(pt)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization
    .data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appending(path: "Contents.json"))
print("wrote \(images.count) icon sizes")
