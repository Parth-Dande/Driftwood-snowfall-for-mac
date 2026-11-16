import CoreGraphics
import Foundation

/// The physical model of one display's weather: where the surfaces are, how bodies fly, and how snow settles.
struct WeatherPhysics {
    /// Downward acceleration, in points per second squared.
    static let gravity: CGFloat = 800
    /// Seconds between the samples recorded along a flight.
    static let sampleInterval: CGFloat = 0.2

    /// The kind of weather being modelled.
    let kind: WeatherKind
    /// Front to back, with the bottom of the screen last.
    private(set) var ledges: [WeatherSurface] = []
    /// The bottom of the screen, as the only surface foreground weather can reach.
    private(set) var ground: [WeatherSurface] = []
    /// The snow lying on each surface.
    private(set) var snowBanks: [SnowBank] = []
    private var surfaces: [WeatherSurface]?
    private var size: CGSize = .zero
    private var frames: [UInt32: CGRect] = [:]
    private var velocities: [UInt32: CGVector] = [:]

    /// Creates a model for `kind` of weather with no surfaces yet.
    init(kind: WeatherKind) { self.kind = kind }

    /// How much larger snowflakes are drawn at `density`; heavy snow has bigger flakes.
    static func snowRadiusScale(density: CGFloat) -> CGFloat {
        1 + 1.15 * min(1, max(0, (density - 0.55) / 0.95))
    }

    /// Replaces the surfaces with the latest look at the windows and reports what moved, resized or went away.
    mutating func updateSurfaces(_ surfaces: [WeatherSurface], in size: CGSize, elapsed: CGFloat) -> SurfaceChange {
        var change = SurfaceChange()
        guard self.surfaces != surfaces || self.size != size else {
            velocities.removeAll(keepingCapacity: true)
            return change
        }
        change.hasChanges = true
        self.surfaces = surfaces
        self.size = size
        let previous = frames
        ground = [WeatherSurface(id: 0, rect: CGRect(x: 0, y: size.height - 1, width: size.width, height: 2))]
        ledges = surfaces.filter { $0.rect.minY >= 18 } + ground
        frames.removeAll(keepingCapacity: true)
        for ledge in ledges { frames[ledge.id] = ledge.rect }

        let interval = max(1.0 / 60, elapsed)
        var moving: [UInt32: CGVector] = [:]
        for (id, old) in previous where id != 0 {
            guard let new = frames[id], !Self.isRelocated(from: old, to: new) else {
                change.removedIDs.insert(id)
                continue
            }
            if abs(old.width - new.width) + abs(old.height - new.height) >= 1.5 {
                change.resizedIDs.insert(id)
                continue
            }
            let offset = CGVector(dx: new.minX - old.minX, dy: new.minY - old.minY)
            guard abs(offset.dx) + abs(offset.dy) >= 0.5 else { continue }
            change.offsets[id] = offset
            let before = elapsed < 0.25 ? velocities[id] ?? .zero : .zero
            let now = CGVector(dx: offset.dx / interval, dy: offset.dy / interval)
            moving[id] = now
            let sideways = (abs(now.dx - before.dx) - 260) / 1100
            let dropping = (now.dy - before.dy - 320) / 900
            let fraction = min(1, max(0, sideways, dropping))
            if fraction > 0.02 { change.shakes[id] = Shake(fraction: fraction, velocity: before) }
        }
        velocities = moving
        if kind == .snow { change.clumps = updateBanks(change) }
        return change
    }

    private static func resizeKeepsLedge(from old: CGRect, to new: CGRect) -> Bool {
        let resized = abs(old.width - new.width) + abs(old.height - new.height) > 0.5
        return resized && old.minX < new.maxX && new.minX < old.maxX
    }

    private static func isRelocated(from old: CGRect, to new: CGRect) -> Bool {
        new.width < old.width * 0.62 || new.height < old.height * 0.62
            || abs(new.midX - old.midX) > 140 || abs(new.midY - old.midY) > 140
    }

    /// Slow, wide gusts that everything light drifts on. Smooth in both place and time,
    /// so neighbouring flakes move together the way they do in real air.
    static func wind(_ kind: WeatherKind, at point: CGPoint, time: CGFloat) -> CGVector {
        let strength: CGFloat
        switch kind {
        case .snow: strength = 20
        case .petals: strength = 30
        case .leaves: strength = 40
        case .cash: strength = 26
        default: return .zero
        }
        let gust = sin(time * 0.23 + point.x * 0.0021 + point.y * 0.0013)
            + 0.6 * sin(time * 0.61 - point.x * 0.0047 + 1.7)
            + 0.35 * sin(time * 1.37 + point.y * 0.009 + 0.4)
        let lift = sin(time * 0.41 + point.x * 0.0035 + 2.3)
        return CGVector(dx: strength * (0.35 + gust), dy: strength * 0.22 * lift)
    }

    /// Integrates gravity against air drag until the body lands, leaves the screen or runs out of time.
    /// Drag is linear in the speed through the air, so a body settles at its own terminal speed:
    /// dv/dt = g - (g / terminal) * (v - wind).
    func flight(of body: WeatherBody, from origin: CGPoint, velocity: CGVector, at time: CGFloat,
             collides: Bool = true, isForeground: Bool = false, skipping: UInt32? = nil,
             limit: CGFloat = 90) -> WeatherFlight {
        let step: CGFloat = body.terminalSpeed < 500 ? 1.0 / 30 : 1.0 / 60
        let interval = body.tumbles || body.terminalSpeed >= 500 ? Self.sampleInterval : Self.sampleInterval * 1.5
        let decay = exp(-Self.gravity / body.terminalSpeed * step)
        let obstacles = collides ? (isForeground ? ground : ledges) : []
        var flight = WeatherFlight(startTime: time, points: [origin], angles: [body.angle(at: time)])
        var position = origin
        var v = velocity
        var elapsed: CGFloat = 0
        var nextSample = interval
        while elapsed < limit {
            let now = time + elapsed
            let theta = body.swayRate * now + body.phase
            let air = Self.wind(kind, at: position, time: now)
            let fall = body.tumbles ? body.terminalSpeed * (1 + 0.35 * cos(2 * theta)) : body.terminalSpeed
            let targetX = air.dx * body.windExposure + body.swaySpeed * sin(theta)
            let targetY = air.dy * body.windExposure + fall
            v.dx = targetX + (v.dx - targetX) * decay
            v.dy = targetY + (v.dy - targetY) * decay
            let next = CGPoint(x: position.x + v.dx * step, y: position.y + v.dy * step)
            if let hit = Self.collision(from: position, to: next, ledges: obstacles, skipping: skipping) {
                let travelled = hypot(next.x - position.x, next.y - position.y)
                let part = travelled > 0 ? hypot(hit.point.x - position.x, hit.point.y - position.y) / travelled : 0
                elapsed += step * part
                position = hit.point
                flight.landingSurfaceID = hit.id
                break
            }
            elapsed += step
            position = next
            if position.y > size.height + 24 || position.x < -80 || position.x > size.width + 80 { break }
            if elapsed >= nextSample {
                flight.times.append(elapsed)
                flight.points.append(position)
                flight.angles.append(body.angle(at: time + elapsed))
                nextSample += interval
            }
        }
        if elapsed - flight.duration > 0.0005 || flight.points.count == 1 {
            flight.times.append(max(elapsed, flight.duration + 0.01))
            flight.points.append(position)
            flight.angles.append(body.angle(at: time + elapsed))
        } else {
            flight.points[flight.points.count - 1] = position
        }
        return flight
    }

    /// A straight line at constant speed, for meteors: too fast and too brief for air to matter.
    func straightFlight(from origin: CGPoint, velocity: CGVector, at time: CGFloat) -> WeatherFlight {
        var flight = WeatherFlight(startTime: time, points: [origin], angles: [0])
        let step: CGFloat = 1.0 / 60
        var position = origin
        var elapsed: CGFloat = 0
        while elapsed < 12 {
            let next = CGPoint(x: position.x + velocity.dx * step, y: position.y + velocity.dy * step)
            if let hit = Self.collision(from: position, to: next, ledges: ledges, skipping: nil) {
                elapsed += step * (hit.point.y - position.y) / max(0.001, next.y - position.y)
                position = hit.point
                flight.landingSurfaceID = hit.id
                break
            }
            elapsed += step
            position = next
            if position.y > size.height + 24 || (position.x < -160 && velocity.dx <= 0)
                || (position.x > size.width + 160 && velocity.dx >= 0) { break }
        }
        flight.times.append(max(0.01, elapsed))
        flight.points.append(position)
        flight.angles.append(0)
        return flight
    }

    /// A firefly steers towards a heading that keeps turning, and towards `target` when it has one.
    func wanderingFlight(of body: WeatherBody, from origin: CGPoint, velocity: CGVector, at time: CGFloat,
                duration: CGFloat, toward target: CGPoint?) -> WeatherFlight {
        var flight = WeatherFlight(startTime: time, points: [origin], angles: [0])
        let step: CGFloat = 1.0 / 30
        let ease = 1 - exp(-step * 1.6)
        var position = origin
        var v = velocity
        var elapsed: CGFloat = 0
        var nextSample = Self.sampleInterval
        while elapsed < duration {
            let now = time + elapsed
            let heading = 2.4 * sin(now * 0.31 + body.phase) + 1.9 * sin(now * 0.73 + body.phase * 2.3)
            var want = CGVector(dx: cos(heading) * body.terminalSpeed, dy: sin(heading) * body.terminalSpeed * 0.7)
            if let target {
                let ring = 16 + 52 * (0.5 + 0.5 * sin(body.phase * 7.1))
                let spot = CGPoint(x: target.x + cos(body.phase * 3 + now * 0.35) * ring,
                                   y: target.y + sin(body.phase * 3 + now * 0.35) * ring * 0.8)
                let dx = spot.x - position.x, dy = spot.y - position.y
                let distance = max(1, hypot(dx, dy))
                let pull = min(95, distance * 1.4)
                let calm = min(1, distance / 120)
                want = CGVector(dx: want.dx * (0.25 + 0.5 * calm) + dx / distance * pull,
                                dy: want.dy * (0.25 + 0.5 * calm) + dy / distance * pull)
            }
            let margin: CGFloat = 60
            if position.x < margin { want.dx += (margin - position.x) * 0.6 }
            if position.x > size.width - margin { want.dx -= (position.x - size.width + margin) * 0.6 }
            if position.y < margin { want.dy += (margin - position.y) * 0.6 }
            if position.y > size.height - margin { want.dy -= (position.y - size.height + margin) * 0.6 }
            v.dx += (want.dx - v.dx) * ease
            v.dy += (want.dy - v.dy) * ease
            position.x += v.dx * step
            position.y += v.dy * step
            elapsed += step
            if elapsed >= nextSample {
                flight.times.append(elapsed)
                flight.points.append(position)
                flight.angles.append(0)
                nextSample += Self.sampleInterval
            }
        }
        if elapsed - flight.duration > 0.0005 {
            flight.times.append(elapsed)
            flight.points.append(position)
            flight.angles.append(0)
        }
        return flight
    }

    /// Whether a flight planned earlier still ends where it was going, now that windows have moved.
    func isStillValid(_ flight: WeatherFlight, after time: CGFloat, isForeground: Bool, skipping: UInt32?) -> Bool {
        let obstacles = isForeground ? ground : ledges
        for index in 0..<(flight.points.count - 1) where flight.startTime + flight.times[index + 1] > time {
            guard let hit = Self.collision(from: flight.points[index], to: flight.points[index + 1],
                                           ledges: obstacles, skipping: skipping) else { continue }
            let end = flight.endPoint
            return hit.id == flight.landingSurfaceID && abs(hit.point.x - end.x) < 4
        }
        return flight.landingSurfaceID == nil
    }

    /// The first surface a body moving from `start` to `end` lands on, and where.
    static func collision(from start: CGPoint, to end: CGPoint, ledges: [WeatherSurface],
                          skipping: UInt32?) -> (id: UInt32, point: CGPoint)? {
        let dy = end.y - start.y
        guard dy > 0 else { return nil }
        var nearest: (UInt32, CGPoint)?
        for (index, ledge) in ledges.enumerated() {
            guard ledge.id != skipping else { continue }
            let before = start.y - ledge.rect.minY
            let after = end.y - ledge.rect.minY
            guard before <= 0, after >= -0.01 else { continue }
            let time = min(1, -before / dy)
            let x = start.x + (end.x - start.x) * time
            let point = CGPoint(x: x, y: start.y + dy * time)
            guard point.y < (nearest?.1.y ?? .infinity) else { continue }
            guard x >= ledge.rect.minX, x <= ledge.rect.maxX else { continue }
            guard !ledges.prefix(index).contains(where: { $0.rect.contains(point) }) else { continue }
            nearest = (ledge.id, point)
        }
        return nearest
    }

    /// A random point along the open top edges where rain can splash, weighted by width.
    func randomSplashPoint() -> CGPoint? {
        var total: CGFloat = 0
        for ledge in ledges { total += ledge.rect.width * (ledge.id == 0 ? 0.4 : 1) }
        guard total > 0 else { return nil }
        var pick = CGFloat.random(in: 0..<total)
        for (index, ledge) in ledges.enumerated() {
            let weight = ledge.rect.width * (ledge.id == 0 ? 0.4 : 1)
            if pick >= weight { pick -= weight; continue }
            let point = CGPoint(x: .random(in: ledge.rect.minX...ledge.rect.maxX), y: ledge.rect.minY)
            guard point.x >= 0, point.x <= size.width, point.y <= size.height,
                  !ledges.prefix(index).contains(where: { $0.rect.contains(point) }) else { return nil }
            return point
        }
        return nil
    }

    /// Creates a new body of this model's kind, with randomised size and flutter.
    func makeBody(isForeground: Bool, density: CGFloat) -> WeatherBody {
        let phase = CGFloat.random(in: 0...(2 * .pi))
        switch kind {
        case .snow:
            let near: CGFloat = isForeground ? 1.35 : 1
            let radius = CGFloat.random(in: 0.95...1.8) * Self.snowRadiusScale(density: density) * near
            return WeatherBody(radius: radius, terminalSpeed: (34 + 15 * radius) * near, swaySpeed: .random(in: 7...19),
                               swayRate: .random(in: 0.8...2.1), phase: phase)
        case .petals:
            return WeatherBody(radius: .random(in: 3.2...5.2), terminalSpeed: .random(in: 46...72), swaySpeed: .random(in: 26...48),
                               swayRate: .random(in: 1.3...2.3), phase: phase, spinRate: .random(in: -0.7...0.7), tumbles: true)
        case .leaves:
            return WeatherBody(radius: .random(in: 4.5...8), terminalSpeed: .random(in: 62...104), swaySpeed: .random(in: 34...66),
                               swayRate: .random(in: 1.0...1.9), phase: phase,
                               spinRate: Bool.random() ? .random(in: -2.6...2.6) : .random(in: -0.4...0.4), tumbles: true)
        case .cash:
            // A banknote is broad and nearly weightless for its area: it planes from side to side
            // in long swings and now and then turns right over.
            // Notes close to the viewer are larger and cross the screen faster, which gives the fall its depth.
            let near: CGFloat = isForeground ? .random(in: 1.5...2.0) : .random(in: 0.75...1.25)
            return WeatherBody(radius: 10.5 * near, terminalSpeed: .random(in: 74...104) * (0.7 + 0.3 * near), swaySpeed: .random(in: 46...84),
                               swayRate: .random(in: 1.1...1.9), phase: phase,
                               spinRate: Bool.random() ? .random(in: -1.6...1.6) : .random(in: -0.3...0.3), tumbles: true)
        case .fireflies:
            return WeatherBody(radius: .random(in: 1.6...3), terminalSpeed: .random(in: 12...26), phase: phase, windExposure: 0)
        case .stars:
            return WeatherBody(radius: .random(in: 1.2...2.2), terminalSpeed: 2000, phase: phase, windExposure: 0)
        case .rain:
            return WeatherBody(radius: .random(in: 0.9...1.5), terminalSpeed: 2000, phase: phase, windExposure: 0)
        }
    }

    /// A droplet or ember thrown up from an impact. Nearly ballistic: gravity does almost all the work.
    static func makeSpark(isRaindrop rain: Bool) -> (body: WeatherBody, velocity: CGVector, life: CGFloat) {
        let body = WeatherBody(radius: rain ? .random(in: 0.7...1.2) : .random(in: 1.0...2.1), terminalSpeed: rain ? 900 : 1300, windExposure: 0)
        let velocity = rain
            ? CGVector(dx: .random(in: -75...75), dy: .random(in: -150 ... -60))
            : CGVector(dx: .random(in: -200...200), dy: .random(in: -300 ... -70))
        return (body, velocity, rain ? .random(in: 0.22...0.38) : .random(in: 0.35...0.75))
    }

    /// Adds a flake's worth of snow to a surface at `x`.
    mutating func depositSnow(on id: UInt32, at x: CGFloat, radius: CGFloat) {
        guard let bank = snowBanks.firstIndex(where: { $0.surface.id == id }) else { return }
        let rect = snowBanks[bank].surface.rect
        let count = max(2, Int(ceil(rect.width / 14)) + 1)
        if snowBanks[bank].depths.isEmpty { snowBanks[bank].depths = Array(repeating: 0, count: count) }
        let position = (x - rect.minX) / rect.width * CGFloat(count - 1)
        let limit: CGFloat = id == 0 ? 20 : 9
        let share: CGFloat = id == 0 ? 0.42 : 0.24
        let amount = radius * share * .random(in: 0.4...1.8)
        let spread = CGFloat.random(in: 1.4...3.4)
        let reach = Int(spread.rounded(.up))
        let center = min(count - 1, max(0, Int(position.rounded())))
        for index in max(0, center - reach)...min(count - 1, center + reach) {
            let weight = max(0, 1 - abs(CGFloat(index) - position) / spread)
            snowBanks[bank].depths[index] = min(limit, snowBanks[bank].depths[index] + weight * amount * 2.5 / spread)
        }
    }

    /// Knocks the snow off a stretch of ledge, as a hand or a pointer brushing along it would.
    mutating func brushSnow(off id: UInt32, at x: CGFloat, reach: CGFloat, velocity: CGVector) -> [SnowClump] {
        guard let bank = snowBanks.firstIndex(where: { $0.surface.id == id }), snowBanks[bank].depths.count > 1 else { return [] }
        let rect = snowBanks[bank].surface.rect
        let count = snowBanks[bank].depths.count
        let spacing = rect.width / CGFloat(count - 1)
        var clumps: [SnowClump] = []
        for index in 0..<count {
            let cell = rect.minX + CGFloat(index) * spacing
            let depth = snowBanks[bank].depths[index]
            guard abs(cell - x) <= reach, depth > 0.5 else { continue }
            snowBanks[bank].depths[index] = depth * 0.05
            for _ in 0..<max(1, Int(depth / 3)) {
                clumps.append(SnowClump(
                    position: CGPoint(x: cell + .random(in: -spacing / 2...spacing / 2), y: rect.minY - depth * 0.4 - 1),
                    velocity: CGVector(dx: max(-260, min(260, velocity.dx * 0.3)) + CGFloat.random(in: -30...30),
                                       dy: min(0, velocity.dy * 0.2) - CGFloat.random(in: 10...70)),
                    radius: .random(in: 0.9...2.2), sourceID: id, fallsPastSource: id != 0 && Bool.random()))
            }
        }
        return clumps
    }

    /// Removes all settled snow.
    mutating func clearSettledSnow() {
        for index in snowBanks.indices { snowBanks[index] = SnowBank(surface: snowBanks[index].surface) }
    }

    /// Removes the snow on the ground, leaving window ledges as they are.
    mutating func clearGround() {
        for index in snowBanks.indices where snowBanks[index].surface.id == 0 { snowBanks[index] = SnowBank(surface: snowBanks[index].surface) }
    }

    /// Tips the snow off every window ledge, leaving the ground as it is.
    mutating func shedLedgeSnow() -> [SnowClump] {
        var clumps: [SnowClump] = []
        for index in snowBanks.indices where snowBanks[index].surface.id != 0 {
            clumps += release(snowBanks[index], supportedBy: nil)
            snowBanks[index].depths.removeAll()
        }
        return clumps
    }

    private mutating func updateBanks(_ change: SurfaceChange) -> [SnowClump] {
        let previousBanks = Dictionary(uniqueKeysWithValues: snowBanks.map { ($0.surface.id, $0) })
        var clumps: [SnowClump] = []
        var next: [SnowBank] = []
        for (index, ledge) in ledges.enumerated() {
            let id = ledge.id
            let rect = ledge.rect
            let visibleMin = max(0, rect.minX)
            let visibleMax = min(size.width, rect.maxX)
            guard visibleMax - visibleMin >= 16, rect.minY < size.height else { continue }
            let center = CGPoint(x: (visibleMin + visibleMax) / 2, y: rect.minY)
            let shadowed = ledges.prefix(index).contains {
                $0.rect.contains(center) && $0.rect.minX <= visibleMin && $0.rect.maxX >= visibleMax
            }
            guard !shadowed || id == 0 else { continue }

            var bank = SnowBank(surface: ledge)
            if let old = previousBanks[id] { bank.grain = old.grain }
            if let old = previousBanks[id], !old.depths.isEmpty {
                let oldRect = old.surface.rect
                if oldRect == rect {
                    bank.depths = old.depths
                } else if change.offsets[id] != nil {
                    bank.depths = old.depths
                    if let shake = change.shakes[id] {
                        clumps += release(SnowBank(surface: ledge, depths: old.depths), supportedBy: nil, shake: shake)
                        bank.depths = old.depths.map { $0 * (1 - shake.fraction) }
                    }
                } else if id == 0 || Self.resizeKeepsLedge(from: oldRect, to: rect) {
                    clumps += release(old, supportedBy: rect)
                    let count = max(2, Int(ceil(rect.width / 14)) + 1)
                    bank.depths = (0..<count).map { old.depth(at: rect.minX + rect.width * CGFloat($0) / CGFloat(count - 1)) }
                } else {
                    clumps += release(old, supportedBy: nil)
                }
            }
            next.append(bank)
        }
        let present = Set(next.map(\.surface.id))
        for bank in snowBanks where bank.surface.id != 0 && !present.contains(bank.surface.id) {
            clumps += release(bank, supportedBy: nil)
        }
        snowBanks = next
        return clumps
    }

    /// Snow that lost its footing simply drops. Snow shaken loose keeps the speed its window had,
    /// so a flick to the side sends it off that way and a window snatched away leaves it hanging.
    private func release(_ bank: SnowBank, supportedBy: CGRect?, shake: Shake? = nil) -> [SnowClump] {
        let rect = bank.surface.rect
        let left = max(0, rect.minX)
        let right = min(size.width, rect.maxX)
        let count = min(38, Int(max(0, right - left) / 11))
        var clumps: [SnowClump] = []
        for i in 0..<count {
            let x = left + (right - left) * (CGFloat(i) + 0.5) / CGFloat(count)
            if let supportedBy, (supportedBy.minX...supportedBy.maxX).contains(x) { continue }
            let depth = bank.depth(at: x)
            guard depth > 0.2 else { continue }
            var velocity = CGVector(dx: CGFloat.random(in: -5...5), dy: CGFloat.random(in: 2...55))
            if let shake {
                guard CGFloat.random(in: 0...1) < shake.fraction else { continue }
                let pace = max(1, hypot(shake.velocity.dx, shake.velocity.dy))
                let keep = min(1, 700 / pace) * .random(in: 0.45...1)
                velocity = CGVector(dx: shake.velocity.dx * keep + .random(in: -30...30),
                                    dy: shake.velocity.dy * keep + .random(in: -40...10))
            }
            clumps.append(SnowClump(position: CGPoint(x: x, y: rect.minY - depth * 0.45 - 1), velocity: velocity,
                                    radius: .random(in: 0.9...2.2), sourceID: bank.surface.id, fallsPastSource: shake == nil))
        }
        return clumps
    }
}
