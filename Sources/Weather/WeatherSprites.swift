import AppKit
import QuartzCore

/// Small images shared by every particle of a kind. Drawn once, in points with y pointing down.
@MainActor
enum Sprite {
    private static var cache: [String: CGImage] = [:]

    private static func image(_ key: String, width: CGFloat, height: CGFloat, scale: CGFloat = 4,
                              draw: (CGContext) -> Void) -> CGImage {
        if let cached = cache[key] { return cached }
        let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: height * scale)
        context.scaleBy(x: scale, y: -scale)
        draw(context)
        let image = context.makeImage()!
        cache[key] = image
        return image
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func radial(_ context: CGContext, center: CGPoint, radius: CGFloat, stops: [(CGFloat, CGColor)]) {
        let gradient = CGGradient(colorsSpace: nil, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func dot(_ key: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, core: CGFloat) -> CGImage {
        image(key, width: 16, height: 16) { context in
            radial(context, center: CGPoint(x: 8, y: 8), radius: 8,
                   stops: [(0, color(r, g, b)), (core, color(r, g, b)), (1, color(r, g, b, 0))])
        }
    }

    static var snow: CGImage { dot("snow", 0.96, 0.98, 1, core: 0.5) }
    static var droplet: CGImage { dot("droplet", 0.78, 0.92, 1, core: 0.55) }
    static var ember: CGImage { dot("ember", 0.95, 0.84, 1, core: 0.3) }

    static var glow: CGImage {
        image("glow", width: 36, height: 36) { context in
            radial(context, center: CGPoint(x: 18, y: 18), radius: 18,
                   stops: [(0, color(0.98, 1, 0.8)), (0.13, color(0.9, 1, 0.45)), (0.24, color(0.85, 1, 0.36, 0.5)),
                           (0.55, color(0.85, 1, 0.36, 0.14)), (1, color(0.85, 1, 0.36, 0))])
        }
    }

    static func leaf(_ variant: Int) -> CGImage {
        let tints: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.59, 0.23), (0.93, 0.42, 0.16), (0.98, 0.74, 0.27), (0.80, 0.30, 0.14)]
        let (r, g, b) = tints[variant % tints.count]
        return image("leaf\(variant)", width: 27, height: 15.5) { context in
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: 4, y: 7.75))
            blade.addCurve(to: CGPoint(x: 26, y: 7.75), control1: CGPoint(x: 8, y: -1.5), control2: CGPoint(x: 20, y: 0.5))
            blade.addCurve(to: CGPoint(x: 4, y: 7.75), control1: CGPoint(x: 20, y: 15), control2: CGPoint(x: 8, y: 17))
            context.addPath(blade)
            context.clip()
            let shade = CGGradient(colorsSpace: nil, colors: [color(min(1, r + 0.06), min(1, g + 0.14), b + 0.05),
                                                              color(r * 0.86, g * 0.78, b * 0.8)] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(shade, start: CGPoint(x: 0, y: 1), end: CGPoint(x: 0, y: 14.5), options: [])
            context.resetClip()
            context.setStrokeColor(color(r * 0.62, g * 0.5, b * 0.5, 0.75))
            context.setLineWidth(0.7)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 0.6, y: 7.75))
            context.addLine(to: CGPoint(x: 23, y: 7.75))
            for x in stride(from: CGFloat(9), through: 19, by: 5) {
                context.move(to: CGPoint(x: x, y: 7.75))
                context.addLine(to: CGPoint(x: x + 3.4, y: 4.2))
                context.move(to: CGPoint(x: x, y: 7.75))
                context.addLine(to: CGPoint(x: x + 3.4, y: 11.3))
            }
            context.strokePath()
        }
    }

    static func petal(_ variant: Int) -> CGImage {
        let tints: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.57, 0.72), (1, 0.72, 0.82), (0.98, 0.47, 0.66)]
        let (r, g, b) = tints[variant % tints.count]
        return image("petal\(variant)", width: 24, height: 18) { context in
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 1, y: 9))
            shape.addCurve(to: CGPoint(x: 22.5, y: 4.5), control1: CGPoint(x: 6, y: -1), control2: CGPoint(x: 19, y: -1.5))
            shape.addQuadCurve(to: CGPoint(x: 19.5, y: 9), control: CGPoint(x: 21.5, y: 7.5))
            shape.addQuadCurve(to: CGPoint(x: 22.5, y: 13.5), control: CGPoint(x: 21.5, y: 10.5))
            shape.addCurve(to: CGPoint(x: 1, y: 9), control1: CGPoint(x: 19, y: 19.5), control2: CGPoint(x: 6, y: 19))
            context.addPath(shape)
            context.clip()
            let blush = CGGradient(colorsSpace: nil, colors: [color(r * 0.94, g * 0.8, b * 0.86), color(r, g, b),
                                                              color(1, min(1, g + 0.26), min(1, b + 0.2))] as CFArray,
                                   locations: [0, 0.35, 1])!
            context.drawLinearGradient(blush, start: CGPoint(x: 1, y: 9), end: CGPoint(x: 23, y: 9), options: [])
        }
    }

    /// A meteor: a tail that thins and fades away from a white-hot head on the right.
    static var streak: CGImage {
        image("streak", width: 96, height: 6) { context in
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: 0, y: 3))
            tail.addLine(to: CGPoint(x: 91, y: 0.4))
            tail.addArc(center: CGPoint(x: 92.4, y: 3), radius: 2.6, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            tail.addLine(to: CGPoint(x: 0, y: 3))
            context.addPath(tail)
            context.clip()
            let fade = CGGradient(colorsSpace: nil, colors: [color(0.9, 0.76, 1, 0), color(0.9, 0.76, 1, 0.5),
                                                             color(0.97, 0.92, 1, 1), color(1, 1, 1, 1)] as CFArray,
                                  locations: [0, 0.6, 0.93, 1])!
            context.drawLinearGradient(fade, start: .zero, end: CGPoint(x: 96, y: 0), options: [])
        }
    }

    /// A raindrop streak, leaning the way the rain travels (down and to the left).
    static var rain: CGImage {
        image("rain", width: 12, height: 46) { context in
            let head = CGPoint(x: 2, y: 44), tail = CGPoint(x: 10.9, y: 2)
            context.move(to: tail)
            context.addLine(to: head)
            context.setLineWidth(1.5)
            context.setLineCap(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            let fade = CGGradient(colorsSpace: nil, colors: [color(0.78, 0.92, 1, 0), color(0.78, 0.92, 1, 1)] as CFArray,
                                  locations: [0, 1])!
            context.drawLinearGradient(fade, start: tail, end: head, options: [])
        }
    }

    /// The ring a raindrop throws up where it lands.
    static var crown: CGImage {
        image("crown", width: 20, height: 8.4) { context in
            context.setStrokeColor(color(0.82, 0.93, 1, 0.9))
            context.setLineWidth(1)
            context.strokeEllipse(in: CGRect(x: 1, y: 1, width: 18, height: 6.4))
        }
    }

    static var snowball: CGImage {
        image("snowball", width: 32, height: 32) { context in
            let box = CGRect(x: 0.5, y: 0.5, width: 31, height: 31)
            context.addEllipse(in: box)
            context.clip()
            context.setFillColor(color(0.72, 0.85, 1))
            context.fill(box)
            radial(context, center: CGPoint(x: 13, y: 12.2), radius: 12,
                   stops: [(0, color(0.99, 0.99, 1, 0.95)), (0.1, color(0.99, 0.99, 1, 0.95)), (1, color(0.99, 0.99, 1, 0))])
        }
    }

    /// A top hat, coal eyes, a carrot and a scarf, laid over the top ball of a snowman.
    /// The ball itself fills the lower 32 points; the hat stands on the 12 above it.
    static var face: CGImage {
        image("face", width: 32, height: 44) { context in
            let r: CGFloat = 16, top: CGFloat = 12
            context.setFillColor(color(0.10, 0.11, 0.16))
            context.fill(CGRect(x: 8.5, y: 0.5, width: 15, height: 12.5))
            context.fill(CGRect(x: 4, y: 12, width: 24, height: 3))
            context.setFillColor(color(0.85, 0.13, 0.25))
            context.fill(CGRect(x: 8.5, y: 9, width: 15, height: 3))
            context.setFillColor(color(0.07, 0.10, 0.14))
            for x in [-0.26, 0.26] {
                context.fillEllipse(in: CGRect(x: r + r * x - 1.4, y: top + r - r * 0.16 - 1.4, width: 2.8, height: 2.8))
            }
            for x in [-0.3, -0.15, 0, 0.15, 0.3] {
                context.fillEllipse(in: CGRect(x: r + r * x - 0.7, y: top + r + r * 0.42 - abs(x) * 5 - 0.7, width: 1.4, height: 1.4))
            }
            context.setFillColor(color(1, 0.45, 0.10))
            context.move(to: CGPoint(x: r - 0.5, y: top + r - 1))
            context.addLine(to: CGPoint(x: r + r * 0.62, y: top + r + r * 0.12))
            context.addLine(to: CGPoint(x: r - 0.5, y: top + r + r * 0.24))
            context.fillPath()
            context.setFillColor(color(0.85, 0.13, 0.25))
            context.fill(CGRect(x: r - r * 0.6, y: top + r + r * 0.72, width: r * 1.2, height: r * 0.2))
            context.fill(CGRect(x: r + r * 0.2, y: top + r + r * 0.86, width: r * 0.24, height: r * 0.14))
        }
    }

    /// Coal buttons and twig arms for the middle ball. The ball sits in the centre 32 points.
    static var torso: CGImage {
        image("torso", width: 57.6, height: 32) { context in
            let centre: CGFloat = 28.8
            context.setFillColor(color(0.07, 0.10, 0.14))
            for y in [9.0, 16.0, 23.0] {
                context.fillEllipse(in: CGRect(x: centre - 1.5, y: y - 1.5, width: 3, height: 3))
            }
            context.setStrokeColor(color(0.36, 0.24, 0.15))
            context.setLineWidth(1.5)
            context.setLineCap(.round)
            for side in [-1.0, 1.0] {
                let shoulder = CGPoint(x: centre + side * 14, y: 14)
                let hand = CGPoint(x: centre + side * 27, y: 5)
                context.move(to: shoulder)
                context.addLine(to: hand)
                context.move(to: CGPoint(x: centre + side * 22, y: 8.5))
                context.addLine(to: CGPoint(x: centre + side * 24.5, y: 2.5))
                context.move(to: CGPoint(x: centre + side * 22, y: 8.5))
                context.addLine(to: CGPoint(x: centre + side * 27.5, y: 10))
            }
            context.strokePath()
        }
    }

    /// The pile of snow a plough pushes along in front of its blade.
    static var heap: CGImage {
        image("heap", width: 44, height: 24) { context in
            let mound = CGMutablePath()
            mound.move(to: CGPoint(x: 0, y: 24))
            mound.addCurve(to: CGPoint(x: 14, y: 5), control1: CGPoint(x: 1, y: 12), control2: CGPoint(x: 6, y: 5))
            mound.addCurve(to: CGPoint(x: 30, y: 12), control1: CGPoint(x: 21, y: 5), control2: CGPoint(x: 24, y: 11))
            mound.addCurve(to: CGPoint(x: 44, y: 24), control1: CGPoint(x: 37, y: 13), control2: CGPoint(x: 42, y: 19))
            mound.closeSubpath()
            context.addPath(mound)
            context.clip()
            let shade = CGGradient(colorsSpace: nil, colors: [color(0.98, 0.99, 1), color(0.80, 0.88, 0.99)] as CFArray,
                                   locations: [0, 1])!
            context.drawLinearGradient(shade, start: CGPoint(x: 0, y: 4), end: CGPoint(x: 0, y: 24), options: [])
        }
    }

    static var truck: CGImage {
        image("truck", width: 60, height: 36) { context in
            context.scaleBy(x: 1.5, y: 1.5)
            let x: CGFloat = 19, y: CGFloat = 21
            context.setFillColor(color(0.96, 0.65, 0.16))
            context.fill(CGRect(x: x - 17, y: y - 11, width: 25, height: 7))
            context.fill(CGRect(x: x - 12, y: y - 19, width: 12, height: 9))
            context.setFillColor(color(0.53, 0.83, 0.92))
            context.fill(CGRect(x: x - 10, y: y - 17, width: 7, height: 5))
            context.setFillColor(color(1, 0.86, 0.35))
            context.fillEllipse(in: CGRect(x: x - 8, y: y - 21.5, width: 4, height: 3))
            context.setFillColor(color(0.17, 0.22, 0.31))
            context.fillEllipse(in: CGRect(x: x - 15, y: y - 7, width: 8, height: 8))
            context.fillEllipse(in: CGRect(x: x - 2, y: y - 7, width: 8, height: 8))
            context.setFillColor(color(0.62, 0.66, 0.72))
            context.fillEllipse(in: CGRect(x: x - 13, y: y - 5, width: 4, height: 4))
            context.fillEllipse(in: CGRect(x: x, y: y - 5, width: 4, height: 4))
            context.setFillColor(color(0.67, 0.78, 0.90))
            context.move(to: CGPoint(x: x + 8, y: y - 9))
            context.addLine(to: CGPoint(x: x + 18, y: y + 2))
            context.addLine(to: CGPoint(x: x + 7, y: y + 2))
            context.fillPath()
        }
    }
}
