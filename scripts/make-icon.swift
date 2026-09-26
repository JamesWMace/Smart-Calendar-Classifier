// Renders the app icon at 1024×1024. Run via scripts/make-icon.sh.
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let context = NSGraphicsContext.current!.cgContext

    // macOS icon grid: an 824-pt rounded square with a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
    context.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 30
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    context.restoreGState()

    context.saveGState()
    tilePath.addClip()
    NSGradient(colors: [
        NSColor(red: 0.36, green: 0.58, blue: 1.00, alpha: 1),
        NSColor(red: 0.30, green: 0.25, blue: 0.86, alpha: 1),
    ])!.draw(in: tile, angle: -90)
    // A faint highlight across the top.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    context.restoreGState()

    // The calendar page.
    let page = NSRect(x: 222, y: 200, width: 540, height: 500)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 70, yRadius: 70)
    context.saveGState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    pageShadow.shadowOffset = NSSize(width: 0, height: -10)
    pageShadow.shadowBlurRadius = 24
    pageShadow.set()
    NSColor.white.setFill()
    pagePath.fill()
    context.restoreGState()

    context.saveGState()
    pagePath.addClip()
    let header = NSRect(x: page.minX, y: page.maxY - 140, width: page.width, height: 140)
    NSGradient(colors: [
        NSColor(red: 1.00, green: 0.36, blue: 0.33, alpha: 1),
        NSColor(red: 0.90, green: 0.20, blue: 0.22, alpha: 1),
    ])!.draw(in: header, angle: -90)
    context.restoreGState()

    // Binder rings.
    NSColor(white: 0.93, alpha: 1).setFill()
    for x in [page.minX + 140, page.maxX - 164] {
        NSBezierPath(roundedRect: NSRect(x: x, y: page.maxY - 52, width: 24, height: 88), xRadius: 12, yRadius: 12).fill()
    }

    // Day grid, one day picked out.
    let columns = 4, rows = 3
    let cell: CGFloat = 78, gap: CGFloat = 26
    let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
    let originX = page.midX - gridWidth / 2
    let originY = page.minY + 52
    for row in 0..<rows {
        for column in 0..<columns {
            let rect = NSRect(x: originX + CGFloat(column) * (cell + gap), y: originY + CGFloat(row) * (cell + gap), width: cell, height: cell)
            let isPicked = row == 1 && column == 1
            (isPicked ? NSColor(red: 0.30, green: 0.36, blue: 0.95, alpha: 1) : NSColor(white: 0.90, alpha: 1)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
        }
    }

    // Sparkles: Apple Intelligence reading the page.
    func sparkle(center: NSPoint, radius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let pinch = r * 0.16
        let tips = [NSPoint(x: center.x, y: center.y + r), NSPoint(x: center.x + r, y: center.y),
                    NSPoint(x: center.x, y: center.y - r), NSPoint(x: center.x - r, y: center.y)]
        path.move(to: tips[0])
        for index in 0..<4 {
            let next = tips[(index + 1) % 4]
            let control = NSPoint(
                x: center.x + (tips[index].x - center.x + next.x - center.x) * pinch / r,
                y: center.y + (tips[index].y - center.y + next.y - center.y) * pinch / r
            )
            path.curve(to: next, controlPoint1: control, controlPoint2: control)
        }
        path.close()
        return path
    }
    for (center, radius) in [(NSPoint(x: 770, y: 712), CGFloat(150)), (NSPoint(x: 648, y: 820), CGFloat(62))] {
        let star = sparkle(center: center, radius: radius)
        context.saveGState()
        let glow = NSShadow()
        glow.shadowColor = NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.55)
        glow.shadowBlurRadius = 30
        glow.set()
        NSColor.white.setFill()
        star.fill()
        context.restoreGState()
        context.saveGState()
        star.addClip()
        NSGradient(colors: [NSColor.white, NSColor(red: 1.0, green: 0.86, blue: 0.40, alpha: 1)])!
            .draw(in: star.bounds, angle: -60)
        context.restoreGState()
    }
    return true
}

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
