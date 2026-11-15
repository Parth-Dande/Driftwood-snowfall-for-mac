import CoreGraphics
import Foundation

enum WeatherKind: String {
    case snow, rain, petals, leaves, fireflies, stars
}

struct WeatherSurface: Equatable {
    let id: UInt32
    let rect: CGRect
}

/// What a particle is made of. Everything about how it moves follows from these.
struct WeatherBody {
    var radius: CGFloat
    /// Fall speed at which air drag balances gravity, in points per second.
    var terminal: CGFloat
    var sway: CGFloat = 0
    var swayRate: CGFloat = 0
    var phase: CGFloat = 0
    var spin: CGFloat = 0
    /// How much of the wind this body feels, from 0 (none) to 1.
    var gusts: CGFloat = 1
    /// Flat bodies (leaves, petals) rock from side to side and fall slower at the ends of each swing.
    var tumbles = false

    func angle(at time: CGFloat) -> CGFloat {
        phase + spin * time + (tumbles ? 0.9 * cos(swayRate * time + phase) : 0)
    }
}

/// A path worked out ahead of time, sampled a few times a second. The compositor plays it back.
struct WeatherFlight {
    var start: CGFloat
    var times: [CGFloat] = [0]
    var points: [CGPoint]
    var angles: [CGFloat]
    var landing: UInt32?

    var duration: CGFloat { times[times.count - 1] }
    var end: CGFloat { start + duration }
    var endPoint: CGPoint { points[points.count - 1] }

    func state(at time: CGFloat) -> (position: CGPoint, velocity: CGVector) {
        guard points.count > 1 else { return (points[0], .zero) }
        let local = min(max(0, time - start), duration)
        var index = 0
        while index < times.count - 2 && times[index + 1] <= local { index += 1 }
        let span = max(0.001, times[index + 1] - times[index])
        let a = points[index], b = points[index + 1]
        let t = (local - times[index]) / span
        return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                CGVector(dx: (b.x - a.x) / span, dy: (b.y - a.y) / span))
    }
}

struct SnowBank: Equatable {
    let surface: WeatherSurface
    var profile: [CGFloat] = []
    /// Sets the lie of this drift's lumps and hollows. Every drift gets its own, and a fresh one
    /// whenever it is cleared, so snow never builds into the same outline twice.
    var grain = CGFloat.random(in: 0...1000)

    func depth(at x: CGFloat) -> CGFloat {
        guard profile.count > 1, x >= surface.rect.minX, x <= surface.rect.maxX else { return 0 }
        let progress = min(1, max(0, (x - surface.rect.minX) / surface.rect.width))
        let offset = progress * CGFloat(profile.count - 1)
        let index = Int(offset)
        let t = offset - CGFloat(index)
        let fraction = t * t * (3 - 2 * t)
        return profile[index] * (1 - fraction) + profile[min(index + 1, profile.count - 1)] * fraction
    }
}

/// Snow knocked loose from a bank when its window moves, shrinks or closes.
struct SnowClump {
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var from: UInt32
    /// Snow that dropped off a ledge falls past it. Snow tossed into the air can come back down on it.
    var passesOwnLedge = true
}

/// Part of what rests on a window breaking free because the window jerked under it.
struct Shake {
    /// How much comes loose, from 0 to 1.
    var fraction: CGFloat
    /// The speed the window had just before the jerk. Whatever comes loose keeps it.
    var velocity: CGVector
}

struct SurfaceChange {
    var changed = false
    var clumps: [SnowClump] = []
    /// Windows that slid without changing size, and how far. What rests on them rides along.
    var carried: [UInt32: CGVector] = [:]
    var shaken: [UInt32: Shake] = [:]
    /// Windows whose size changed. Only what lost its footing falls.
    var resized: Set<UInt32> = []
    var removed: Set<UInt32> = []
}
