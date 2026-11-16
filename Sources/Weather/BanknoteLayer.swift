import AppKit
import QuartzCore

/// A banknote that bends: strips of paper hinged edge to edge in three dimensions.
///
/// Each strip shows its own slice of the note and is tilted about the crease it shares with its
/// neighbour, so the note is genuinely folded in depth and looks right from any angle as it tumbles.
/// The tilts drift back and forth the whole time, the way a falling note flexes in the air.
@MainActor
enum Banknote {
    /// The ways a note can be folded. Each gives every strip its resting tilt, in radians.
    /// The bends are slight: a used note is nearly flat, and anything stronger reads as crumpled.
    private enum Fold: CaseIterable {
        /// Nearly flat, with the shallow creases of a note that has lived in a wallet.
        case creased
        /// Folded once down the middle and partly opened.
        case halved
        /// Curled into an arc from end to end.
        case curled
        /// Bent into a wave.
        case rippled

        func tilt(ofStrip index: Int, among count: Int) -> CGFloat {
            let position = (CGFloat(index) + 0.5) / CGFloat(count)
            switch self {
            case .creased: return index.isMultiple(of: 2) ? 0.07 : -0.07
            case .halved: return position < 0.5 ? 0.22 : -0.22
            case .curled: return 0.55 * (position - 0.5)
            case .rippled: return 0.18 * sin(position * 2 * .pi + 0.5)
            }
        }
    }

    private static let stripCount = 6

    /// Makes a note with a random side showing and a random fold, flat size `Sprite.banknoteSize`,
    /// centred on the layer's own origin.
    static func makeLayer() -> CATransformLayer {
        let note = CATransformLayer()
        let showsFace = Bool.random()
        let fold = Fold.allCases.randomElement()!
        let resting = (0..<stripCount).map { fold.tilt(ofStrip: $0, among: stripCount) }
        let phase = CGFloat.random(in: 0...(2 * .pi))
        // One slow cycle of flexing, sampled finely enough that the hinges move smoothly.
        let samples = 9
        let poses = (0..<samples).map { sample -> [CATransform3D] in
            let turn = 2 * CGFloat.pi * CGFloat(sample) / CGFloat(samples - 1) + phase
            return transforms(forTilts: resting.indices.map { index in
                resting[index] * (1 + 0.2 * sin(turn)) + 0.04 * sin(turn + CGFloat(index) * 1.1)
            })
        }
        let period = Double.random(in: 1.7...3.1)
        let size = Sprite.banknoteSize
        for index in 0..<stripCount {
            let strip = CALayer()
            strip.bounds = CGRect(x: 0, y: 0, width: size.width / CGFloat(stripCount) + 0.25, height: size.height)
            // Light falls from one side, so a strip turned towards it is brighter than one turned away.
            let shade: Sprite.BanknoteShade = resting[index] > 0.06 ? .lit : resting[index] < -0.06 ? .shadowed : .plain
            strip.contents = Sprite.banknote(showingFace: showsFace, shade: shade)
            strip.contentsRect = CGRect(x: CGFloat(index) / CGFloat(stripCount), y: 0, width: 1 / CGFloat(stripCount), height: 1)
            strip.isDoubleSided = true
            strip.allowsEdgeAntialiasing = true
            strip.transform = poses[0][index]
            let flex = CAKeyframeAnimation(keyPath: "transform")
            flex.values = poses.map { NSValue(caTransform3D: $0[index]) }
            flex.duration = period
            flex.repeatCount = .infinity
            strip.add(flex, forKey: "flex")
            note.addSublayer(strip)
        }
        return note
    }

    /// Where each strip sits when the strips have these tilts: laid end to end like the links of a
    /// chain seen from above, then centred so the note turns about its middle.
    private static func transforms(forTilts tilts: [CGFloat]) -> [CATransform3D] {
        let half = Sprite.banknoteSize.width / CGFloat(tilts.count) / 2
        var edge = CGPoint.zero
        var centres: [CGPoint] = []
        for tilt in tilts {
            centres.append(CGPoint(x: edge.x + half * cos(tilt), y: edge.y + half * sin(tilt)))
            edge = CGPoint(x: edge.x + 2 * half * cos(tilt), y: edge.y + 2 * half * sin(tilt))
        }
        let middle = CGPoint(x: centres.map(\.x).reduce(0, +) / CGFloat(tilts.count),
                             y: centres.map(\.y).reduce(0, +) / CGFloat(tilts.count))
        return zip(centres, tilts).map { centre, tilt in
            CATransform3DRotate(CATransform3DMakeTranslation(centre.x - middle.x, 0, centre.y - middle.y), -tilt, 0, 1, 0)
        }
    }
}
