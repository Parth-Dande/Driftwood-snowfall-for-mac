import AppKit

struct Snowball {
    var center: CGPoint
    var radius: CGFloat
}

struct Snowballs {
    static let gravity: CGFloat = 1400

    private(set) var placed: [Snowball] = []
    private(set) var rolling: Snowball?
    private var distance: CGFloat = 0
    private var last = CGPoint.zero

    /// Three balls standing one on another make a snowman: the indices of its top ball and the one below.
    var snowmen: [(head: Int, torso: Int)] {
        guard placed.count >= 3 else { return [] }
        func isOn(_ top: Snowball, _ lower: Snowball) -> Bool {
            let gap = (top.radius + lower.radius) * 0.87
            return abs(top.center.x - lower.center.x) < 1 && abs(lower.center.y - top.center.y - gap) < 1
        }
        var found: [(head: Int, torso: Int)] = []
        for (head, top) in placed.enumerated() where !placed.contains(where: { isOn($0, top) }) {
            guard let torso = placed.firstIndex(where: { isOn(top, $0) }),
                  placed.contains(where: { isOn(placed[torso], $0) }) else { continue }
            found.append((head, torso))
        }
        return found
    }

    mutating func begin(at point: CGPoint) {
        last = point
        distance = 0
        rolling = Snowball(center: point, radius: 5)
    }

    mutating func drag(to point: CGPoint) {
        guard rolling != nil else { return }
        distance += hypot(point.x - last.x, point.y - last.y)
        last = point
        rolling?.center = point
        rolling?.radius = min(29, 5 + distance * 0.075)
    }

    /// Takes the rolled ball out of the hand to be thrown, if it is big enough to count as one.
    mutating func throwBall() -> Snowball? {
        defer { rolling = nil }
        return distance > 22 ? rolling : nil
    }

    /// Lets go of the rolled ball. It comes to rest on the floor, or on a ball it was dropped over;
    /// the result says where it was let go so the fall can be shown.
    mutating func release(at point: CGPoint, size: CGSize, floor: CGFloat) -> (from: CGPoint, ball: Snowball)? {
        drag(to: point)
        defer { rolling = nil }
        guard var ball = rolling, distance > 22, placed.count < 36 else { return nil }
        ball.center.x = min(max(ball.radius, point.x), size.width - ball.radius)
        ball.center.y = max(ball.radius, point.y)
        let from = ball.center
        var landing = floor - ball.radius
        var stacked = false
        for other in placed {
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
            for other in placed where abs(ball.center.y - other.center.y) < ball.radius + other.radius {
                let gap = ball.center.x - other.center.x
                if abs(gap) < ball.radius + other.radius {
                    ball.center.x = other.center.x + (gap < 0 ? -1 : 1) * (ball.radius + other.radius)
                }
            }
            ball.center.x = min(max(ball.radius, ball.center.x), size.width - ball.radius)
        }
        placed.append(ball)
        return (from, ball)
    }
}
