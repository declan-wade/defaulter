import AppKit

// Draws the app icon: a document with a swap arrow, rendered at every size
// macOS asks for. Run from build.sh; failure is non-fatal.
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let out = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data? {
    let s = CGFloat(px)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        let inset = s * 0.06
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)

        // Rounded-square background with a blue gradient.
        let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let colors = [NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.96, alpha: 1).cgColor,
                      NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.80, alpha: 1).cgColor]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
        ctx.restoreGState()

        // A document sheet with a folded corner.
        let dw = s * 0.34, dh = s * 0.44
        let dx = s * 0.16, dy = s * 0.30
        let fold = dw * 0.30
        let doc = NSBezierPath()
        doc.move(to: CGPoint(x: dx, y: dy))
        doc.line(to: CGPoint(x: dx, y: dy + dh))
        doc.line(to: CGPoint(x: dx + dw - fold, y: dy + dh))
        doc.line(to: CGPoint(x: dx + dw, y: dy + dh - fold))
        doc.line(to: CGPoint(x: dx + dw, y: dy))
        doc.close()
        NSColor.white.withAlphaComponent(0.95).setFill()
        doc.fill()

        // Swap arrows to the right of the document.
        let ax = s * 0.56, ay = s * 0.44, aw = s * 0.27
        let lw = max(1, s * 0.055)
        NSColor.white.setStroke()
        let top = NSBezierPath()
        top.lineWidth = lw; top.lineCapStyle = .round
        top.move(to: CGPoint(x: ax, y: ay + s * 0.07))
        top.line(to: CGPoint(x: ax + aw, y: ay + s * 0.07))
        top.stroke()
        let bottom = NSBezierPath()
        bottom.lineWidth = lw; bottom.lineCapStyle = .round
        bottom.move(to: CGPoint(x: ax + aw, y: ay - s * 0.07))
        bottom.line(to: CGPoint(x: ax, y: ay - s * 0.07))
        bottom.stroke()
        // Arrowheads.
        func head(at p: CGPoint, pointingRight: Bool) {
            let d = s * 0.075
            let h = NSBezierPath()
            h.lineWidth = lw; h.lineCapStyle = .round; h.lineJoinStyle = .round
            let sign: CGFloat = pointingRight ? -1 : 1
            h.move(to: CGPoint(x: p.x + sign * d, y: p.y + d * 0.85))
            h.line(to: p)
            h.line(to: CGPoint(x: p.x + sign * d, y: p.y - d * 0.85))
            h.stroke()
        }
        head(at: CGPoint(x: ax + aw, y: ay + s * 0.07), pointingRight: true)
        head(at: CGPoint(x: ax, y: ay - s * 0.07), pointingRight: false)
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: px, height: px)
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = draw(size) else { continue }
    try? data.write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    if let data2 = draw(size * 2), size <= 512 {
        try? data2.write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
print("iconset written")
