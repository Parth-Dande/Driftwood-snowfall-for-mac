import AppKit

/// A ball of packed snow.
struct Snowball {
    /// The ball's centre.
    var center: CGPoint
    /// The radius, in points.
    var radius: CGFloat
}

/// The snowballs on one display: the one being rolled and those already set down.
struct Snowballs {
    /// Downward acceleration of a dropped or thrown ball, in points per second squared.
    static let gravity: CGFloat = 1400

    /// Balls that have come to rest, in the order they were set down.
    private(set) var placedBalls: [Snowball] = []
    /// The ball currently in the hand, if any.
    private(set) var rollingBall: Snowball?
    private var distance: CGFloat = 0
    private var last = CGPoint.zero

    /// Three balls standing one on another make a snowman: the indices of its top ball and the one below.
    var snowmen: [(head: Int, torso: Int)] {
        guard placedBalls.count >= 3 else { return [] }
        func isOn(_ top: Snowball, _ lower: Snowball) -> Bool {
            let gap = (top.radius + lower.radius) * 0.87
            return abs(top.center.x - lower.center.x) < 1 && abs(lower.center.y - top.center.y - gap) < 1
        }
        var found: [(head: Int, torso: Int)] = []
        for (head, top) in placedBalls.enumerated() where !placedBalls.contains(where: { isOn($0, top) }) {
            guard let torso = placedBalls.firstIndex(where: { isOn(top, $0) }),
                  placedBalls.contains(where: { isOn(placedBalls[torso], $0) }) else { continue }
            found.append((head, torso))
        }
        return found
    }

    /// Starts a new ball at `point`.
    mutating func beginRolling(at point: CGPoint) {
        last = point
        distance = 0
        rollingBall = Snowball(center: point, radius: 5)
    }

    /// Moves the ball in the hand to `point`. It grows with the distance rolled.
    mutating func roll(to point: CGPoint) {
        guard rollingBall != nil else { return }
        distance += hypot(point.x - last.x, point.y - last.y)
        last = point
        rollingBall?.center = point
        rollingBall?.radius = min(29, 5 + distance * 0.075)
    }

    /// Takes the rolled ball out of the hand to be thrown, if it is big enough to count as one.
    mutating func removeRollingBall() -> Snowball? {
        defer { rollingBall = nil }
        return distance > 22 ? rollingBall : nil
    }

    /// Lets go of the rolled ball. It comes to rest on the floor, or on a ball it was dropped over;
    /// the result says where it was let go so the fall can be shown.
    mutating func dropBall(at point: CGPoint, in size: CGSize, floorY floor: CGFloat) -> (from: CGPoint, ball: Snowball)? {
        roll(to: point)
        defer { rollingBall = nil }
        guard var ball = rollingBall, distance > 22, placedBalls.count < 36 else { return nil }
        ball.center.x = min(max(ball.radius, point.x), size.width - ball.radius)
        ball.center.y = max(ball.radius, point.y)
        let from = ball.center
        var landing = floor - ball.radius
        var stacked = false
        for other in placedBalls {
            let reach = (ball.radius + other.radius) * 0.7
            let surface = other.center.y - (ball.radius + other.radius) * 0.87
            if abs(from.x - other.center.x) <= reach && from.y <= surface + ball.radius && surface < landing {
                landing = surface
                ball.center.x = other.center.x
                stacked = true
            }
        }
        ball.center.y = stacked ? landing : max(from.y, landing)
        if !stacked {
            for other in placedBalls where abs(ball.center.y - other.center.y) < ball.radius + other.radius {
                let gap = ball.center.x - other.center.x
                if abs(gap) < ball.radius + other.radius {
                    ball.center.x = other.center.x + (gap < 0 ? -1 : 1) * (ball.radius + other.radius)
                }
            }
            ball.center.x = min(max(ball.radius, ball.center.x), size.width - ball.radius)
        }
        placedBalls.append(ball)
        return (from, ball)
    }
}
