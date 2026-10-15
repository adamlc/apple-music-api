import AppKit

/// The app icon and menu bar glyph, drawn in code so there are no binary assets to keep in sync.
/// `script/bundle` runs the binary with `--render-icons` to turn the app icon into an .icns.
enum IconArtwork {
    // MARK: Shared note shape

    /// A beamed pair of eighth notes in a 100x100 box (origin bottom left), the same motif as the
    /// Apple Music icon, drawn as a play on it.
    ///
    /// Returned as separate pieces: overlapping subpaths in one path cancel out where their winding
    /// directions differ, which punches holes in the stems.
    static func noteShapes() -> [NSBezierPath] {
        var shapes: [NSBezierPath] = []

        func head(cx: CGFloat, cy: CGFloat) {
            let oval = NSBezierPath(ovalIn: NSRect(x: -14, y: -10.5, width: 28, height: 21))
            var t = AffineTransform(rotationByDegrees: 20)
            t.append(AffineTransform(translationByX: cx, byY: cy))
            oval.transform(using: t)
            shapes.append(oval)
        }
        head(cx: 26, cy: 21)
        head(cx: 71, cy: 13)

        // Each stem's right edge sits on the right edge of its (tilted) notehead. The tilted oval's
        // rightmost point (x = cx + 13.64) is 2.02 above its centre, so start the stem there; any
        // lower and its corner pokes out past the curve of the head.
        shapes.append(NSBezierPath(rect: NSRect(x: 33.64, y: 23.02, width: 6, height: 65.98)))
        shapes.append(NSBezierPath(rect: NSRect(x: 78.64, y: 15.02, width: 6, height: 63.98)))

        let beam = NSBezierPath()
        beam.move(to: NSPoint(x: 33.64, y: 91))
        beam.line(to: NSPoint(x: 84.64, y: 81))
        beam.line(to: NSPoint(x: 84.64, y: 66))
        beam.line(to: NSPoint(x: 33.64, y: 76))
        beam.close()
        shapes.append(beam)
        return shapes
    }

    // MARK: App icon

    private static func drawAppIcon() {
        // Coordinates are in a 1024 box, with the usual macOS margin around the squircle.
        let squircle = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor(red: 0.85, green: 0.06, blue: 0.21, alpha: 1).setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        NSGradient(
            starting: NSColor(red: 1.00, green: 0.42, blue: 0.51, alpha: 1),
            ending: NSColor(red: 0.85, green: 0.06, blue: 0.21, alpha: 1)
        )?.draw(in: squircle.bounds, angle: -90)

        // Two server units behind the note: translucent slabs with a status light and vents.
        for y in [190.0, 306.0] as [CGFloat] {
            let slab = NSBezierPath(roundedRect: NSRect(x: 220, y: y, width: 584, height: 100), xRadius: 30, yRadius: 30)
            NSColor.white.withAlphaComponent(0.24).setFill()
            slab.fill()
            NSColor.white.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: 258, y: y + 37, width: 26, height: 26)).fill()
            for i in 0..<3 {
                NSBezierPath(roundedRect: NSRect(x: 640 + CGFloat(i) * 46, y: y + 28, width: 20, height: 44), xRadius: 10, yRadius: 10).fill()
            }
        }

        // The note, with a soft shadow so it lifts off the server units.
        var t = AffineTransform(scaleByX: 5.0, byY: 5.0)
        t.append(AffineTransform(translationByX: 262, byY: 395))
        let noteShadow = NSShadow()
        noteShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        noteShadow.shadowBlurRadius = 18
        noteShadow.shadowOffset = NSSize(width: 0, height: -8)
        noteShadow.set()
        NSColor.white.setFill()
        // One transparency layer so the shadow falls on the whole note, not on each piece
        // (per-piece shadows draw seams where the stems meet the heads and beam).
        let cg = NSGraphicsContext.current!.cgContext
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        fillNote(transform: t)
        cg.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func fillNote(transform: AffineTransform) {
        for shape in noteShapes() {
            shape.transform(using: transform)
            shape.fill()
        }
    }

    static func appIcon(pixels: Int) -> NSImage {
        let size = NSSize(width: pixels, height: pixels)
        return NSImage(size: size, flipped: false) { rect in
            let s = rect.width / 1024
            NSGraphicsContext.current?.cgContext.scaleBy(x: s, y: s)
            drawAppIcon()
            return true
        }
    }

    // MARK: Menu bar glyph

    /// Black-on-transparent template image: macOS recolours it for light, dark and highlighted bars.
    static func menuBarGlyph() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            var t = AffineTransform(scaleByX: 0.15, byY: 0.15)
            t.append(AffineTransform(translationByX: 1.6, byY: 3.4))
            NSColor.black.setFill()
            fillNote(transform: t)
            // A thin "server unit" line under the note.
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 0.8, width: 13, height: 1.8), xRadius: 0.9, yRadius: 0.9).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Rendering to disk

    /// Writes an `AppIcon.iconset` folder into `directory`, ready for `iconutil -c icns`.
    static func writeIconset(to directory: URL) throws {
        let iconset = directory.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try writePNG(appIcon(pixels: pixels), pixels: pixels, to: iconset.appendingPathComponent(name))
            }
        }
        // A full-size copy to look at while designing.
        try writePNG(appIcon(pixels: 1024), pixels: 1024, to: directory.appendingPathComponent("AppIcon-1024.png"))
        try writePNG(menuBarGlyph(), pixels: 144, to: directory.appendingPathComponent("MenuBarGlyph.png"), onWhite: true)
    }

    private static func writePNG(_ image: NSImage, pixels: Int, to url: URL, onWhite: Bool = false) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if onWhite {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        }
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
