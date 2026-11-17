import CoreGraphics
import Foundation

/// The kinds of weather Driftwood can show.
enum WeatherKind: String {
    /// Snow that settles on windows and the ground.
    case snow
    /// Rain that splashes where it lands.
    case rain
    /// Blossom petals carried on the wind.
    case petals
    /// Autumn leaves that tumble as they fall.
    case leaves
    /// Fireflies that wander and glow.
    case fireflies
    /// Stars that twinkle, with the odd shooting star.
    case stars
    /// Hundred-dollar notes that flutter down.
    case cash
}

/// Something weather can land on: the top edge of a window, or the ground.
struct WeatherSurface: Equatable {
    /// The window's number, or `0` for the ground.
    let id: UInt32
    /// The surface's frame in the display's coordinates, with y pointing down.
    let rect: CGRect
}

/// What a particle is made of. Everything about how it moves follows from these.
struct WeatherBody {
    /// The drawn radius, in points.
    var radius: CGFloat
    /// Fall speed at which air drag balances gravity, in points per second.
    var terminalSpeed: CGFloat
    /// Peak sideways speed of the body's own flutter, in points per second.
    var swaySpeed: CGFloat = 0
    /// How quickly the flutter swings back and forth, in radians per second.
    var swayRate: CGFloat = 0
    /// Where in its flutter the body starts, so no two move in step.
    var phase: CGFloat = 0
    /// Steady rotation, in radians per second.
    var spinRate: CGFloat = 0
    /// How much of the wind this body feels, from 0 (none) to 1.
    var windExposure: CGFloat = 1
    /// Flat bodies (leaves, petals) rock from side to side and fall slower at the ends of each swing.
    var tumbles = false

    /// The body's rotation at `time`.
    func angle(at time: CGFloat) -> CGFloat {
        phase + spinRate * time + (tumbles ? 0.9 * cos(swayRate * time + phase) : 0)
    }
}

/// A path worked out ahead of time, sampled a few times a second. The compositor plays it back.
struct WeatherFlight {
    /// When the flight begins, in weather time.
    var startTime: CGFloat
    /// Seconds after `startTime` at which each sample was taken.
    var times: [CGFloat] = [0]
    /// The body's position at each sample.
    var points: [CGPoint]
    /// The body's rotation at each sample.
    var angles: [CGFloat]
    /// The surface the flight ends on, or `nil` if it leaves the screen or runs out of time.
    var landingSurfaceID: UInt32?

    /// How long the flight lasts, in seconds.
    var duration: CGFloat { times[times.count - 1] }
    /// When the flight ends, in weather time.
    var endTime: CGFloat { startTime + duration }
    /// Where the flight ends.
    var endPoint: CGPoint { points[points.count - 1] }

    /// The position and velocity at `time`, interpolated between samples.
    func state(at time: CGFloat) -> (position: CGPoint, velocity: CGVector) {
        guard points.count > 1 else { return (points[0], .zero) }
        let local = min(max(0, time - startTime), duration)
        var index = 0
        while index < times.count - 2 && times[index + 1] <= local { index += 1 }
        let span = max(0.001, times[index + 1] - times[index])
        let a = points[index], b = points[index + 1]
        let t = (local - times[index]) / span
        return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                CGVector(dx: (b.x - a.x) / span, dy: (b.y - a.y) / span))
    }
}

/// The snow lying on one surface.
struct SnowBank: Equatable {
    /// The surface the snow lies on.
    let surface: WeatherSurface
    /// Snow depth at evenly spaced points along the surface, or empty when there is none.
    var depths: [CGFloat] = []
    /// Sets the lie of this drift's lumps and hollows. Every drift gets its own, and a fresh one
    /// whenever it is cleared, so snow never builds into the same outline twice.
    var grain = CGFloat.random(in: 0...1000)

    /// The snow depth at horizontal position `x`, smoothed between samples.
    func depth(at x: CGFloat) -> CGFloat {
        guard depths.count > 1, x >= surface.rect.minX, x <= surface.rect.maxX else { return 0 }
        let progress = min(1, max(0, (x - surface.rect.minX) / surface.rect.width))
        let offset = progress * CGFloat(depths.count - 1)
        let index = Int(offset)
        let t = offset - CGFloat(index)
        let fraction = t * t * (3 - 2 * t)
        return depths[index] * (1 - fraction) + depths[min(index + 1, depths.count - 1)] * fraction
    }
}

/// Snow knocked loose from a bank when its window moves, shrinks or closes.
struct SnowClump {
    /// Where the clump starts.
    var position: CGPoint
    /// How fast it is moving when it comes loose.
    var velocity: CGVector
    /// The radius, in points.
    var radius: CGFloat
    /// The surface it came from.
    var sourceID: UInt32
    /// Snow that dropped off a ledge falls past it. Snow tossed into the air can come back down on it.
    var fallsPastSource = true
}

/// Part of what rests on a window breaking free because the window jerked under it.
struct Shake {
    /// How much comes loose, from 0 to 1.
    var fraction: CGFloat
    /// The speed the window had just before the jerk. Whatever comes loose keeps it.
    var velocity: CGVector
}

/// What happened to the surfaces between two looks at the windows.
struct SurfaceChange {
    /// Whether anything changed at all.
    var hasChanges = false
    /// Snow knocked loose by the change.
    var clumps: [SnowClump] = []
    /// Windows that slid without changing size, and how far. What rests on them rides along.
    var offsets: [UInt32: CGVector] = [:]
    /// Windows that were jerked hard enough to shake things off.
    var shakes: [UInt32: Shake] = [:]
    /// Windows whose size changed. Only what lost its footing falls.
    var resizedIDs: Set<UInt32> = []
    /// Windows that closed, minimised or jumped elsewhere.
    var removedIDs: Set<UInt32> = []
}
