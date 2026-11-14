import CoreGraphics
import Foundation

@main
struct WeatherPhysicsTests {
    static let screen = CGSize(width: 1000, height: 700)
    static let window = WeatherSurface(id: 42, rect: CGRect(x: 100, y: 200, width: 500, height: 350))

    static func main() {
        gravityAndDrag()
        landing()
        snowbanks()
        movingWindows()
        replanning()
        impacts()
        flutterAndFireflies()
        snowballs()
        print("Passed: gravity and drag, landing, snowbanks, window movement, replanning, impacts, flutter, fireflies and snowballs")
    }

    private static func physics(_ kind: WeatherKind, _ surfaces: [WeatherSurface] = [window]) -> WeatherPhysics {
        var physics = WeatherPhysics(kind: kind)
        _ = physics.setSurfaces(surfaces, size: screen, elapsed: 1)
        return physics
    }

    private static func gravityAndDrag() {
        let still = physics(.stars, [])
        let flake = WeatherBody(radius: 2, terminal: 60, gusts: 0)
        let clump = WeatherBody(radius: 2, terminal: 300, gusts: 0)
        let light = still.fly(flake, from: CGPoint(x: 500, y: 0), velocity: .zero, at: 0)
        let heavy = still.fly(clump, from: CGPoint(x: 500, y: 0), velocity: .zero, at: 0)
        precondition(abs(light.state(at: 3).velocity.dy - 60) < 1.5, "A body must settle at its terminal speed")
        precondition(light.state(at: 0.05).velocity.dy < 55, "Speed must build up from rest under gravity, not start at terminal")
        precondition(heavy.state(at: 1).position.y > light.state(at: 1).position.y + 100, "A heavier body must fall faster")
        precondition(heavy.duration < light.duration, "A heavier body must reach the ground first")

        let spark = WeatherBody(radius: 1, terminal: 1300, gusts: 0)
        let arc = still.fly(spark, from: CGPoint(x: 500, y: 400), velocity: CGVector(dx: 0, dy: -200), at: 0, collides: false, limit: 0.8)
        let peak = arc.points.map(\.y).min() ?? 400
        precondition(peak < 385 && peak > 370, "A spark thrown up at 200 pt/s should rise about 25 points (v²/2g)")
        precondition(arc.endPoint.y > peak + 60, "A spark must fall back after its peak")

        let later = still.fly(flake, from: CGPoint(x: 500, y: 0), velocity: .zero, at: 50)
        precondition(abs(later.duration - light.duration) < 0.01)
    }

    private static func landing() {
        let snow = physics(.snow)
        let flake = WeatherBody(radius: 2, terminal: 60, gusts: 0)
        let onWindow = snow.fly(flake, from: CGPoint(x: 270, y: 150), velocity: .zero, at: 0)
        precondition(onWindow.landing == window.id && abs(onWindow.endPoint.y - 200) < 0.5, "Snow must settle on the top of the window")
        let inFront = snow.fly(flake, from: CGPoint(x: 270, y: 150), velocity: .zero, at: 0, foreground: true)
        precondition(inFront.landing == 0 && inFront.endPoint.y > 690, "Foreground snow passes windows and lands on the floor")
        let beside = snow.fly(flake, from: CGPoint(x: 800, y: 150), velocity: .zero, at: 0)
        precondition(beside.landing == 0, "Snow beside a window must reach the floor")

        let ceiling = WeatherSurface(id: 77, rect: CGRect(x: 0, y: 0, width: 1000, height: 25))
        let covered = physics(.snow, [ceiling, window])
        precondition(!covered.ledges.contains(where: { $0.id == 77 }), "The menu bar must not catch snow")

        let front = WeatherSurface(id: 9, rect: CGRect(x: 50, y: 100, width: 600, height: 500))
        let stacked = physics(.snow, [front, window])
        precondition(stacked.fly(flake, from: CGPoint(x: 270, y: 50), velocity: .zero, at: 0).landing == 9)
    }

    private static func snowbanks() {
        var snow = physics(.snow)
        for x in [270.0, 560.0] {
            for _ in 0..<4 { snow.deposit(on: window.id, at: x, radius: 2) }
        }
        let bank = snow.banks.first { $0.surface.id == window.id }
        precondition((bank?.depth(at: 270) ?? 0) > 0.4 && bank?.depth(at: 420) == 0, "A flake must build snow only near its impact")
        for _ in 0..<40 { snow.deposit(on: window.id, at: 270, radius: 2) }
        precondition((snow.banks.first?.depth(at: 270) ?? 99) <= 9.01, "A window ledge only holds so much")

        let narrower = WeatherSurface(id: window.id, rect: CGRect(x: 100, y: 200, width: 300, height: 350))
        let change = snow.setSurfaces([narrower], size: screen, elapsed: 0.033)
        precondition((snow.banks.first?.depth(at: 270) ?? 0) > 0, "Snow that is still supported must stay")
        precondition(!change.clumps.isEmpty && change.clumps.allSatisfy { $0.position.x > 400 && $0.from == window.id },
                     "Only snow whose support was removed should drop")

        var first = physics(.snow), second = physics(.snow)
        for x in stride(from: 110.0, through: 590, by: 6) {
            first.deposit(on: window.id, at: x, radius: 2)
            second.deposit(on: window.id, at: x, radius: 2)
        }
        let a = first.banks[0], b = second.banks[0]
        precondition(a.grain != b.grain && stride(from: 120.0, through: 580, by: 20).contains { abs(a.depth(at: $0) - b.depth(at: $0)) > 0.05 },
                     "Two drifts built from the same snowfall must differ")

        var brushed = first
        let swept = brushed.brush(window.id, at: 300, reach: 13, velocity: CGVector(dx: 400, dy: 0))
        precondition(!swept.isEmpty && swept.allSatisfy { abs($0.position.x - 300) < 30 && $0.velocity.dx > 50 && $0.velocity.dy < 0 })
        precondition(brushed.banks[0].depth(at: 300) < a.depth(at: 300) * 0.3 && abs(brushed.banks[0].depth(at: 500) - a.depth(at: 500)) < 0.001,
                     "Brushing must clear only where the pointer passed")
        _ = brushed.brush(window.id, at: 300, reach: 13, velocity: .zero)
        precondition(brushed.brush(window.id, at: 300, reach: 13, velocity: .zero).isEmpty, "A bare stretch has nothing left to brush")

        let grainBefore = snow.banks[0].grain
        snow.clearSettledSnow()
        precondition(snow.banks[0].grain != grainBefore, "A cleared drift must grow back differently")
        precondition(snow.banks.allSatisfy { $0.depth(at: 270) == 0 })
        precondition(WeatherPhysics.snowRadiusScale(density: 1.5) > 2 * WeatherPhysics.snowRadiusScale(density: 0.55))
    }

    private static func movingWindows() {
        var settled = physics(.snow)
        for x in stride(from: 120.0, through: 580, by: 20) {
            for _ in 0..<3 { settled.deposit(on: window.id, at: x, radius: 2) }
        }
        let depth = settled.banks.first { $0.surface.id == window.id }?.depth(at: 300) ?? 0
        func slide(_ snow: inout WeatherPhysics, by offsets: [CGVector]) -> (rect: CGRect, last: SurfaceChange) {
            var rect = window.rect
            var last = SurfaceChange()
            for offset in offsets {
                rect = rect.offsetBy(dx: offset.dx, dy: offset.dy)
                last = snow.setSurfaces([WeatherSurface(id: window.id, rect: rect)], size: screen, elapsed: 1.0 / 30)
            }
            return (rect, last)
        }

        for step in [CGVector(dx: 4, dy: 0), CGVector(dx: -4, dy: 0), CGVector(dx: 0, dy: -6), CGVector(dx: 3, dy: 3)] {
            var snow = settled
            var shed = 0
            var rect = window.rect
            for _ in 0..<12 {
                rect = rect.offsetBy(dx: step.dx, dy: step.dy)
                let change = snow.setSurfaces([WeatherSurface(id: window.id, rect: rect)], size: screen, elapsed: 1.0 / 30)
                precondition(change.carried[window.id] == step)
                shed += change.clumps.count
            }
            let bank = snow.banks.first { $0.surface.id == window.id }
            precondition(shed == 0 && bank?.surface.rect == rect, "Snow must ride along with a window that is moved steadily")
            precondition(abs((bank?.depth(at: rect.minX + 200) ?? 0) - depth) < 0.01, "Carried snow keeps its shape")
        }

        var shaken = settled
        var thrown: [SnowClump] = []
        var rect = window.rect
        for step in [10.0, 25, 40, 25, 10, -10, -25, -40, -25, -10, 10, 25, 40, 25, 10, -10, -25, -40, -25, -10] {
            rect = rect.offsetBy(dx: step, dy: 0)
            thrown += shaken.setSurfaces([WeatherSurface(id: window.id, rect: rect)], size: screen, elapsed: 1.0 / 30).clumps
        }
        precondition(thrown.contains { $0.velocity.dx > 150 } && thrown.contains { $0.velocity.dx < -150 },
                     "Shaken snow must fly off to both sides")
        precondition((shaken.banks.first { $0.surface.id == window.id }?.depth(at: rect.minX + 200) ?? 9) < depth * 0.2,
                     "A hard shake must leave the ledge nearly bare")

        var lifted = settled
        let stop = slide(&lifted, by: [CGVector(dx: 0, dy: -25), CGVector(dx: 0, dy: -25), CGVector(dx: 0, dy: 0.6)])
        precondition(!stop.last.clumps.isEmpty && stop.last.clumps.allSatisfy { $0.velocity.dy < -100 && !$0.passesOwnLedge },
                     "Snow on a window that stops rising must be tossed upwards")
        let toss = stop.last.clumps[0]
        let arc = lifted.fly(WeatherBody(radius: 2, terminal: 180, gusts: 0), from: toss.position, velocity: toss.velocity, at: 0)
        precondition((arc.points.map(\.y).min() ?? 0) < toss.position.y - 15 && arc.landing == window.id,
                     "Tossed snow rises, then lands back on the window")

        var dropped = settled
        let snatch = slide(&dropped, by: [CGVector(dx: 0, dy: 45)])
        precondition(!snatch.last.clumps.isEmpty && snatch.last.clumps.allSatisfy { abs($0.velocity.dy) < 60 })

        let lower = WeatherSurface(id: 43, rect: CGRect(x: 150, y: 315, width: 290, height: 200))
        let away = WeatherSurface(id: window.id, rect: window.rect.offsetBy(dx: 400, dy: 0))
        for surfaces in [[lower], [away, lower]] {
            var cascade = settled
            let change = cascade.setSurfaces(surfaces, size: screen, elapsed: 0.5)
            guard let clump = change.clumps.first(where: { (160...195).contains($0.position.x) }) else { fatalError("Expected loose snow") }
            let fall = cascade.fly(WeatherBody(radius: 2, terminal: 180, gusts: 0), from: clump.position, velocity: clump.velocity,
                                   at: 0, skipping: clump.from)
            precondition(fall.landing == lower.id, "Released snow must land on a lower window")
        }

        var narrowed = settled
        let under = WeatherSurface(id: 43, rect: CGRect(x: 380, y: 400, width: 300, height: 200))
        _ = narrowed.setSurfaces([window, under], size: screen, elapsed: 1)
        let slim = WeatherSurface(id: window.id, rect: CGRect(x: 100, y: 200, width: 340, height: 350))
        let shrink = narrowed.setSurfaces([slim, under], size: screen, elapsed: 1.0 / 30)
        precondition(shrink.resized.contains(window.id) && shrink.carried.isEmpty)
        precondition(!shrink.clumps.isEmpty && shrink.clumps.allSatisfy { $0.position.x > 440 && abs($0.velocity.dx) < 6 && $0.velocity.dy > 0 },
                     "Only the unsupported strip falls, and it falls straight down")
        precondition(abs((narrowed.banks.first { $0.surface.id == window.id }?.depth(at: 300) ?? 0) - depth) < depth * 0.25,
                     "Snow still on the window must not move when it is resized")
        let strip = shrink.clumps[shrink.clumps.count / 2]
        let onto = narrowed.fly(WeatherBody(radius: 2, terminal: 180, gusts: 0), from: strip.position, velocity: strip.velocity,
                                at: 0, skipping: strip.from)
        precondition(onto.landing == under.id, "The fallen strip must land on the window below")
        var leftEdge = settled
        let trimmed = WeatherSurface(id: window.id, rect: CGRect(x: 220, y: 200, width: 380, height: 350))
        let trim = leftEdge.setSurfaces([trimmed], size: screen, elapsed: 1.0 / 30)
        precondition(trim.shaken.isEmpty && trim.clumps.allSatisfy { $0.position.x < 220 && abs($0.velocity.dx) < 6 })

        var closing = settled
        let thumbnail = WeatherSurface(id: window.id, rect: CGRect(x: 15, y: 175, width: 85, height: 95))
        let closed = closing.setSurfaces([thumbnail], size: screen, elapsed: 0.033)
        precondition(closed.removed.contains(window.id))
        precondition(!closed.clumps.isEmpty && closed.clumps.allSatisfy { $0.position.x >= window.rect.minX - 1 && abs($0.velocity.dx) < 15 },
                     "Minimized snow must start at the old window and drop straight down")

        var unchanged = settled
        precondition(!unchanged.setSurfaces([window], size: screen, elapsed: 0.033).changed)

        var ploughed = settled
        for _ in 0..<14 { ploughed.deposit(on: 0, at: 250, radius: 2) }
        precondition(!ploughed.shedLedges().isEmpty && ploughed.banks.first { $0.surface.id == window.id }?.depth(at: 300) == 0)
        precondition((ploughed.banks.last?.depth(at: 250) ?? 0) > 4)
        ploughed.clearGround()
        precondition(ploughed.banks.last?.depth(at: 250) == 0)
    }

    private static func replanning() {
        var snow = physics(.snow)
        let flake = WeatherBody(radius: 2, terminal: 60, gusts: 0)
        let flight = snow.fly(flake, from: CGPoint(x: 270, y: 100), velocity: .zero, at: 0)
        precondition(snow.stillValid(flight, after: 0.5, foreground: false, skipping: nil))
        _ = snow.setSurfaces([], size: screen, elapsed: 0.5)
        precondition(!snow.stillValid(flight, after: 0.5, foreground: false, skipping: nil),
                     "A flake heading for a window that closed must be replanned")
        let state = flight.state(at: 0.5)
        let onward = snow.fly(flake, from: state.position, velocity: state.velocity, at: 0.5)
        precondition(onward.landing == 0 && abs(onward.points[0].y - state.position.y) < 0.01,
                     "The new path must continue from where the flake is")

        let toFloor = snow.fly(flake, from: CGPoint(x: 270, y: 100), velocity: .zero, at: 0)
        _ = snow.setSurfaces([window], size: screen, elapsed: 0.5)
        precondition(!snow.stillValid(toFloor, after: 0.5, foreground: false, skipping: nil),
                     "A window opened under a falling flake must catch it")
        precondition(snow.stillValid(toFloor, after: 0.5, foreground: true, skipping: nil))
    }

    private static func impacts() {
        let stars = physics(.stars)
        let meteor = stars.glide(from: CGPoint(x: 600, y: 0), velocity: CGVector(dx: -400, dy: 320), at: 0)
        precondition(meteor.landing == window.id && abs(meteor.endPoint.x - 350) < 2 && abs(meteor.duration - 0.625) < 0.02,
                     "A meteor must strike the window where its line meets the top edge")
        precondition(stars.glide(from: CGPoint(x: 990, y: 0), velocity: CGVector(dx: -100, dy: 500), at: 0).landing == 0)

        let rain = physics(.rain)
        var onWindow = 0
        for _ in 0..<400 {
            guard let point = rain.splashPoint() else { continue }
            precondition(point.y == 200 || point.y == 699, "Rain splashes only on a ledge")
            if point.y == 200 {
                precondition((100...600).contains(point.x))
                onWindow += 1
            }
        }
        precondition(onWindow > 100, "Rain must splash on window tops as well as the floor")
        for rainy in [true, false] {
            let spark = WeatherPhysics.spark(rain: rainy)
            precondition(spark.velocity.dy < 0 && spark.life > 0.2, "Splashes and sparks are thrown upwards")
        }
    }

    private static func flutterAndFireflies() {
        let leaves = physics(.leaves, [])
        let leaf = WeatherBody(radius: 6, terminal: 80, sway: 50, swayRate: 1.5, phase: 0.3, spin: 0.2, gusts: 0, tumbles: true)
        let fall = leaves.fly(leaf, from: CGPoint(x: 500, y: 0), velocity: .zero, at: 0)
        let xs = fall.points.map(\.x)
        precondition((xs.max() ?? 0) - (xs.min() ?? 0) > 40, "A leaf must swing from side to side as it falls")
        precondition((fall.angles.max() ?? 0) - (fall.angles.min() ?? 0) > 1, "A leaf must rock as it swings")
        var sharpest: CGFloat = 0
        for index in 2..<fall.points.count - 1 {
            let before = (fall.points[index].y - fall.points[index - 1].y) / (fall.times[index] - fall.times[index - 1])
            let after = (fall.points[index + 1].y - fall.points[index].y) / (fall.times[index + 1] - fall.times[index])
            sharpest = max(sharpest, abs(after - before))
            precondition(after > 0, "A leaf never falls upwards without a gust")
        }
        precondition(sharpest < 40, "Motion must be smooth from one sample to the next")

        let a = WeatherPhysics.wind(.snow, at: CGPoint(x: 400, y: 300), time: 12)
        let b = WeatherPhysics.wind(.snow, at: CGPoint(x: 410, y: 300), time: 12)
        precondition(abs(a.dx - b.dx) < 1.5 && WeatherPhysics.wind(.rain, at: .zero, time: 3) == .zero)

        let marsh = physics(.fireflies, [])
        let firefly = WeatherBody(radius: 2, terminal: 20, phase: 1.1, gusts: 0)
        let pointer = CGPoint(x: 700, y: 300)
        let home = marsh.wander(firefly, from: CGPoint(x: 300, y: 500), velocity: .zero, at: 0, duration: 9, toward: pointer)
        precondition(hypot(home.endPoint.x - pointer.x, home.endPoint.y - pointer.y) < 90, "Fireflies gather round a resting pointer")
        let free = marsh.wander(firefly, from: CGPoint(x: 300, y: 500), velocity: .zero, at: 0, duration: 9, toward: nil)
        precondition(hypot(free.endPoint.x - 300, free.endPoint.y - 500) < 200, "Left alone, a firefly only drifts")
        precondition(free.points.allSatisfy { $0.x > -20 && $0.x < 1020 && $0.y > -20 && $0.y < 720 })
    }

    private static func snowballs() {
        var stack = Snowballs()
        let floor = screen.height - 6
        for point in [CGPoint(x: 420, y: 535), CGPoint(x: 421, y: 470), CGPoint(x: 419, y: 390)] {
            stack.begin(at: CGPoint(x: 420, y: floor))
            stack.drag(to: point)
            let dropped = stack.release(at: point, size: screen, floor: floor)
            precondition(dropped != nil && dropped!.ball.center.y > dropped!.from.y, "A released ball must fall")
        }
        precondition(stack.placed.count == 3)
        precondition(stack.placed[2].center.y < stack.placed[1].center.y && stack.placed[1].center.y < stack.placed[0].center.y,
                     "Each snowball should land above the one below it")
        precondition(stack.placed[0].center.y + stack.placed[0].radius == floor)
        precondition(stack.snowmen.count == 1 && stack.snowmen[0].head == 2 && stack.snowmen[0].torso == 1, "Three stacked balls should make one snowman")

        var pitch = Snowballs()
        pitch.begin(at: CGPoint(x: 180, y: floor))
        pitch.drag(to: CGPoint(x: 400, y: 500))
        precondition(pitch.throwBall() != nil && pitch.rolling == nil && pitch.placed.isEmpty, "A thrown ball leaves the hand and is not placed")

        var tap = Snowballs()
        tap.begin(at: CGPoint(x: 180, y: floor))
        precondition(tap.release(at: CGPoint(x: 182, y: floor - 3), size: screen, floor: floor) == nil, "A click is not a snowball")
    }
}
