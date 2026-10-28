import AppKit

let target = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let bounds = NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.90, height: p * 0.90)
        let path = NSBezierPath(roundedRect: bounds, xRadius: p * 0.20, yRadius: p * 0.20)
        NSGradient(starting: NSColor(calibratedWhite: 0.29, alpha: 1), ending: NSColor(calibratedWhite: 0.17, alpha: 1))!.draw(in: path, angle: -90)
        let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: p * 0.51, weight: .medium))!
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
        NSRect(origin: .zero, size: symbol.size).fill()
        symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()
        let width = p * 0.64
        let height = width * symbol.size.height / symbol.size.width
        tinted.draw(in: NSRect(x: (p - width) / 2, y: (p - height) / 2, width: width, height: height))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(target)/icon_\(size)x\(size)\(suffix).png"))
    }
}
