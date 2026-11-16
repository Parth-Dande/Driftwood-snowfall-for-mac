import AppKit
import CoreText

/// Pictures of a banknote for the money weather.
///
/// The note is a small photograph of a real one when the app bundle carries it, and a prop note
/// drawn in code otherwise.
extension Sprite {
    /// How brightly a part of a note is lit, which depends on the way that part of the paper faces.
    enum BanknoteShade: CaseIterable {
        case lit, plain, shadowed
    }

    /// The size of a flat note in points.
    static let banknoteSize = CGSize(width: 61, height: 26)

    /// One side of a flat note, lit as `shade` describes.
    static func banknote(showingFace isFace: Bool, shade: BanknoteShade) -> CGImage {
        let side = isFace ? "face" : "reverse"
        let flat = photograph(named: "banknote-\(side)") ?? (isFace ? flatFace : flatReverse)
        guard shade != .plain else { return flat }
        return image("banknote-\(side)-\(shade)", width: banknoteSize.width, height: banknoteSize.height, scale: pixelsPerPoint) { context in
            let sheet = CGRect(origin: .zero, size: banknoteSize)
            context.saveGState()
            context.translateBy(x: 0, y: banknoteSize.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(flat, in: sheet)
            context.restoreGState()
            context.setBlendMode(.sourceAtop)
            context.setFillColor(shade == .lit ? CGColor(gray: 1, alpha: 0.10) : CGColor(gray: 0, alpha: 0.20))
            context.fill(sheet)
        }
    }

    private static let pixelsPerPoint: CGFloat = 8

    /// A bundled photograph of one side of a note, fitted to the size of a flat note.
    private static func photograph(named name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Artwork"),
              let photo = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return image(name, width: banknoteSize.width, height: banknoteSize.height, scale: pixelsPerPoint) { context in
            let sheet = CGRect(origin: .zero, size: banknoteSize)
            context.addPath(CGPath(roundedRect: sheet.insetBy(dx: 0.2, dy: 0.2), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil))
            context.clip()
            // Images draw upside down in a context whose y axis points down, so turn this one back over.
            context.translateBy(x: 0, y: banknoteSize.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(photo, in: sheet)
        }
    }

    // MARK: Artwork

    private static let ink = color(0.11, 0.22, 0.21)
    private static let gold = color(0.76, 0.53, 0.16)
    private static let copper = color(0.72, 0.36, 0.14)

    /// The face: a portrait left of centre, a blue woven ribbon, a copper inkwell under a quill,
    /// seals, serial numbers and a large gold numeral.
    private static var flatFace: CGImage {
        image("banknoteFace", width: banknoteSize.width, height: banknoteSize.height, scale: pixelsPerPoint) { context in
            paper(in: context, tint: [color(0.80, 0.87, 0.84), color(0.87, 0.91, 0.86), color(0.79, 0.86, 0.84)])

            // Quill: a pale feather sweeping up behind the inkwell.
            let quill = CGMutablePath()
            quill.move(to: CGPoint(x: 39.5, y: 18.5))
            quill.addCurve(to: CGPoint(x: 51.5, y: 3.4), control1: CGPoint(x: 40.5, y: 9), control2: CGPoint(x: 46, y: 3.2))
            quill.addCurve(to: CGPoint(x: 39.5, y: 18.5), control1: CGPoint(x: 50, y: 10), control2: CGPoint(x: 45, y: 15.5))
            context.addPath(quill)
            context.setFillColor(color(0.93, 0.87, 0.76, 0.9))
            context.fillPath()

            // Inkwell with a darker bell inside it.
            let well = CGMutablePath()
            well.move(to: CGPoint(x: 40.2, y: 21.3))
            well.addLine(to: CGPoint(x: 40.9, y: 15.6))
            well.addLine(to: CGPoint(x: 39.9, y: 14.4))
            well.addLine(to: CGPoint(x: 45.5, y: 14.4))
            well.addLine(to: CGPoint(x: 44.5, y: 15.6))
            well.addLine(to: CGPoint(x: 45.2, y: 21.3))
            well.closeSubpath()
            context.addPath(well)
            context.setFillColor(copper)
            context.fillPath()
            context.setFillColor(color(0.45, 0.20, 0.08, 0.8))
            context.fillEllipse(in: CGRect(x: 41.6, y: 16.4, width: 2.2, height: 3.4))

            // Ribbon: blue, with lighter marks woven through it.
            let ribbon = CGRect(x: 33.2, y: 0.6, width: 3.5, height: 24.8)
            context.saveGState()
            context.clip(to: ribbon)
            let weave = CGGradient(colorsSpace: nil, colors: [color(0.14, 0.27, 0.62), color(0.30, 0.50, 0.86), color(0.13, 0.25, 0.58)] as CFArray,
                                   locations: [0, 0.45, 1])!
            context.drawLinearGradient(weave, start: CGPoint(x: ribbon.minX, y: 0), end: CGPoint(x: ribbon.maxX, y: 0), options: [])
            context.setFillColor(color(0.70, 0.82, 1, 0.55))
            for y in stride(from: CGFloat(1.6), to: 25, by: 2.3) { context.fillEllipse(in: CGRect(x: 34.2, y: y, width: 1.5, height: 1.1)) }
            context.restoreGState()

            portrait(in: context)

            // Seals: a dark one with a ring on the left, a green one on the right.
            context.setFillColor(color(0.08, 0.10, 0.10, 0.85))
            context.fillEllipse(in: CGRect(x: 8.6, y: 11.8, width: 6.0, height: 6.0))
            context.setStrokeColor(color(0.84, 0.90, 0.86))
            context.setLineWidth(0.3)
            context.strokeEllipse(in: CGRect(x: 9.5, y: 12.7, width: 4.2, height: 4.2))
            context.setFillColor(color(0.12, 0.42, 0.27, 0.9))
            context.fillEllipse(in: CGRect(x: 47.3, y: 6.6, width: 5.2, height: 5.2))
            text("100", at: CGPoint(x: 47.9, y: 10.3), size: 2.9, color: color(0.86, 0.94, 0.88), in: context)

            text("100", at: CGPoint(x: 3.0, y: 8.2), size: 6.2, color: ink, in: context)
            text("100", at: CGPoint(x: 3.0, y: 23.6), size: 5.6, color: ink, in: context)
            text("100", at: CGPoint(x: 49.6, y: 7.0), size: 5.4, color: ink, in: context)
            text("100", at: CGPoint(x: 45.6, y: 23.4), size: 9.2, color: gold, in: context)
            text("DRIFTWOOD RESERVE NOTE", at: CGPoint(x: 13.4, y: 4.3), size: 1.5, color: ink, in: context)
            text("PROP MONEY · NOT LEGAL TENDER", at: CGPoint(x: 37.4, y: 23.9), size: 1.05, color: ink, in: context)
            text("DW 10112026 A", at: CGPoint(x: 3.1, y: 10.6), size: 1.8, color: color(0.10, 0.30, 0.22), in: context)
            text("DW 10112026 A", at: CGPoint(x: 46.4, y: 14.2), size: 2.1, color: color(0.10, 0.30, 0.22), in: context)
            text("D2", at: CGPoint(x: 8.9, y: 20.6), size: 2.0, color: ink, in: context)
            // Two signatures, as scribbles.
            context.setStrokeColor(ink)
            context.setLineWidth(0.22)
            for y in [20.6, 22.6] as [CGFloat] {
                context.move(to: CGPoint(x: 12.6, y: y))
                for step in 1...12 {
                    context.addLine(to: CGPoint(x: 12.6 + CGFloat(step) * 0.45, y: y + (step % 2 == 0 ? -0.55 : 0.4) * (step % 3 == 0 ? 1.4 : 0.7)))
                }
            }
            context.strokePath()
            frame(in: context)
        }
    }

    /// The reverse: a hall with a clock tower between corner numerals, and a tall gold numeral at the right.
    private static var flatReverse: CGImage {
        image("banknoteReverse", width: banknoteSize.width, height: banknoteSize.height, scale: pixelsPerPoint) { context in
            paper(in: context, tint: [color(0.74, 0.85, 0.80), color(0.83, 0.90, 0.84), color(0.73, 0.84, 0.80)])
            // Vignette: sky panel, a long hall, a tower and trees.
            let panel = CGRect(x: 11, y: 5.2, width: 31, height: 15.6)
            context.setFillColor(color(0.11, 0.22, 0.21, 0.22))
            context.fill(panel)
            context.setFillColor(color(0.11, 0.22, 0.21, 0.62))
            context.fill(CGRect(x: 14, y: 12.4, width: 25, height: 7))
            context.fill(CGRect(x: 24.4, y: 6.6, width: 4.2, height: 6))
            context.move(to: CGPoint(x: 24.0, y: 6.8))
            context.addLine(to: CGPoint(x: 26.5, y: 4.9))
            context.addLine(to: CGPoint(x: 29.0, y: 6.8))
            context.fillPath()
            context.setFillColor(color(0.84, 0.91, 0.86, 0.9))
            for x in stride(from: CGFloat(15.4), to: 38, by: 2.1) { context.fill(CGRect(x: x, y: 13.6, width: 0.9, height: 2.4)) }
            for x in stride(from: CGFloat(15.4), to: 38, by: 2.1) { context.fill(CGRect(x: x, y: 16.8, width: 0.9, height: 2.2)) }
            context.fillEllipse(in: CGRect(x: 25.6, y: 8.2, width: 1.8, height: 1.8))
            context.setFillColor(color(0.11, 0.22, 0.21, 0.5))
            for x in [12.6, 40.4] as [CGFloat] { context.fillEllipse(in: CGRect(x: x - 2, y: 14.4, width: 4, height: 5.4)) }

            text("100", at: CGPoint(x: 3.0, y: 8.2), size: 6.2, color: ink, in: context)
            text("100", at: CGPoint(x: 3.0, y: 23.6), size: 5.6, color: ink, in: context)
            text("100", at: CGPoint(x: 43.0, y: 19.6), size: 9.6, color: gold, in: context)
            text("PROP MONEY", at: CGPoint(x: 20.4, y: 4.4), size: 2.2, color: ink, in: context)
            text("NOT LEGAL TENDER", at: CGPoint(x: 18.6, y: 23.4), size: 2.0, color: ink, in: context)
            frame(in: context)
        }
    }

    /// Paper with a soft sideways wash, fine engraved lines and a few fibres.
    private static func paper(in context: CGContext, tint: [CGColor]) {
        let sheet = CGRect(x: 0.4, y: 0.4, width: banknoteSize.width - 0.8, height: banknoteSize.height - 0.8)
        context.saveGState()
        context.clip(to: sheet)
        let wash = CGGradient(colorsSpace: nil, colors: tint as CFArray, locations: [0, 0.5, 1])!
        context.drawLinearGradient(wash, start: .zero, end: CGPoint(x: banknoteSize.width, y: banknoteSize.height), options: [])
        context.setStrokeColor(color(0.11, 0.22, 0.21, 0.09))
        context.setLineWidth(0.16)
        for y in stride(from: CGFloat(2.8), to: banknoteSize.height - 2.4, by: 0.62) {
            context.move(to: CGPoint(x: 2.6, y: y))
            context.addLine(to: CGPoint(x: banknoteSize.width - 2.6, y: y))
        }
        context.strokePath()
        var seed: UInt64 = 2026
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        for _ in 0..<26 {
            let start = CGPoint(x: next() * banknoteSize.width, y: next() * banknoteSize.height)
            context.setStrokeColor(next() > 0.5 ? color(0.72, 0.25, 0.25, 0.35) : color(0.20, 0.30, 0.65, 0.35))
            context.move(to: start)
            context.addLine(to: CGPoint(x: start.x + next() * 1.2 - 0.6, y: start.y + next() * 1.2 - 0.6))
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A head-and-shoulders portrait in engraved tones: long hair, a lit face, a collar and a dark coat.
    private static func portrait(in context: CGContext) {
        let tone = { (alpha: CGFloat) in color(0.11, 0.22, 0.21, alpha) }
        context.saveGState()
        context.clip(to: CGRect(x: 15.5, y: 3.2, width: 17.6, height: 22.2))
        // Coat and shoulders.
        let coat = CGMutablePath()
        coat.move(to: CGPoint(x: 14.5, y: 26))
        coat.addCurve(to: CGPoint(x: 21.4, y: 17.4), control1: CGPoint(x: 15, y: 20.5), control2: CGPoint(x: 18, y: 18))
        coat.addLine(to: CGPoint(x: 27.4, y: 17.4))
        coat.addCurve(to: CGPoint(x: 34, y: 26), control1: CGPoint(x: 31, y: 18), control2: CGPoint(x: 33.4, y: 21))
        coat.closeSubpath()
        context.addPath(coat)
        context.setFillColor(tone(0.78))
        context.fillPath()
        // Collar and cravat.
        context.setFillColor(color(0.88, 0.92, 0.88))
        context.move(to: CGPoint(x: 22.2, y: 17.2))
        context.addLine(to: CGPoint(x: 24.4, y: 23.4))
        context.addLine(to: CGPoint(x: 26.8, y: 17.2))
        context.fillPath()
        // Hair, falling to the shoulders on both sides.
        let hair = CGMutablePath()
        hair.move(to: CGPoint(x: 20.2, y: 18.6))
        hair.addCurve(to: CGPoint(x: 24.6, y: 4.6), control1: CGPoint(x: 17.2, y: 12), control2: CGPoint(x: 19.6, y: 4.6))
        hair.addCurve(to: CGPoint(x: 29.4, y: 18.6), control1: CGPoint(x: 30.2, y: 4.6), control2: CGPoint(x: 31.6, y: 12.4))
        hair.addLine(to: CGPoint(x: 27.2, y: 17))
        hair.addLine(to: CGPoint(x: 22, y: 17))
        hair.closeSubpath()
        context.addPath(hair)
        context.setFillColor(tone(0.55))
        context.fillPath()
        // Face, lit from the left, with brow, nose and mouth lines.
        let face = CGRect(x: 21.3, y: 6.8, width: 6.6, height: 9.8)
        context.saveGState()
        context.addEllipse(in: face)
        context.clip()
        let skin = CGGradient(colorsSpace: nil, colors: [color(0.90, 0.93, 0.89), color(0.62, 0.72, 0.69)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(skin, start: CGPoint(x: face.minX, y: 0), end: CGPoint(x: face.maxX, y: 0), options: [])
        context.restoreGState()
        context.setStrokeColor(tone(0.8))
        context.setLineWidth(0.28)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 22.5, y: 10.2)); context.addLine(to: CGPoint(x: 24.0, y: 9.9))
        context.move(to: CGPoint(x: 25.3, y: 9.9)); context.addLine(to: CGPoint(x: 26.8, y: 10.2))
        context.move(to: CGPoint(x: 24.7, y: 10.6)); context.addLine(to: CGPoint(x: 24.4, y: 13)); context.addLine(to: CGPoint(x: 25.2, y: 13.1))
        context.move(to: CGPoint(x: 23.7, y: 14.7)); context.addLine(to: CGPoint(x: 25.8, y: 14.6))
        context.strokePath()
        context.setFillColor(tone(0.85))
        for x in [23.2, 26.0] as [CGFloat] { context.fillEllipse(in: CGRect(x: x - 0.4, y: 10.5, width: 0.8, height: 0.6)) }
        // Hatching over the coat and hair, as an engraver would shade them.
        context.setStrokeColor(color(0.84, 0.90, 0.86, 0.22))
        context.setLineWidth(0.14)
        for offset in stride(from: CGFloat(-10), to: 30, by: 0.7) {
            context.move(to: CGPoint(x: 14 + offset, y: 26))
            context.addLine(to: CGPoint(x: 22 + offset, y: 4))
        }
        context.strokePath()
        context.restoreGState()
    }

    /// The outer edge and the fine rule just inside it.
    private static func frame(in context: CGContext) {
        context.setStrokeColor(ink)
        context.setLineWidth(0.3)
        context.stroke(CGRect(x: 0.4, y: 0.4, width: banknoteSize.width - 0.8, height: banknoteSize.height - 0.8))
        context.setStrokeColor(color(0.11, 0.22, 0.21, 0.55))
        context.stroke(CGRect(x: 1.9, y: 1.9, width: banknoteSize.width - 3.8, height: banknoteSize.height - 3.8), width: 0.2)
    }

    /// Draws `string` with its baseline starting at `point`, in a context whose y axis points down.
    private static func text(_ string: String, at point: CGPoint, size: CGFloat, color: CGColor, in context: CGContext) {
        let font = CTFontCreateWithName("HelveticaNeue-CondensedBold" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
            .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
