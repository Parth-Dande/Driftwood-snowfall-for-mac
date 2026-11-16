import AppKit
import QuartzCore

/// Draws the weather with Core Animation. Each particle's whole path is worked out once by
/// `WeatherPhysics` and handed to the compositor, which plays it back at the display's own
/// refresh rate. Driftwood only wakes a few times a second to launch newcomers and react to
/// windows and the pointer, so there is no per-frame work in this process at all.
@MainActor
final class WeatherView: NSView {
    private enum Look { case faller, spark, crown, meteor, firefly }

    private struct Particle {
        let layer: CALayer
        var look: Look
        var body: WeatherBody
        var flight: WeatherFlight
        var born: CGFloat
        var expires: CGFloat
        var alpha: Float
        var isForeground = false
        var releasedFrom: UInt32?
        var restingOn: UInt32?
        var settled = false
        /// A clump of packed snow, which adds far more to a drift than one flake.
        var heavy = false
    }

    /// The kind of weather this view shows.
    let kind: WeatherKind
    /// The physical model behind what is drawn.
    private(set) var physics: WeatherPhysics
    /// The snowballs on this display.
    private(set) var snowballs = Snowballs()

    /// How much weather falls.
    var density: CGFloat = 0.65 {
        didSet { if density != oldValue { rain?.birthRate = Float(scale) } }
    }
    /// How fast weather time runs against the clock. Everything inside `stage` follows it.
    var timeScale: Double = 1 {
        didSet { if timeScale != oldValue, !isPaused { setRate(timeScale) } }
    }
    /// Whether weather time is stopped. A new view starts paused.
    var isPaused = true {
        didSet { if isPaused != oldValue { setRate(isPaused ? 0 : timeScale) } }
    }

    private let stage = CALayer()
    private let back = CALayer()
    private let bankLayer = CALayer()
    private let front = CALayer()
    private let props = CALayer()
    private let flash = CALayer()
    private let cutout = CAShapeLayer()
    private var rain: CAEmitterLayer?

    private var particles: [Particle] = []
    private var pool: [CALayer] = []
    private var bankShapes: [UInt32: (shape: CAShapeLayer, rect: CGRect)] = [:]
    private var ballLayers: [CALayer] = []
    private var rollingLayer: CALayer?
    private var truck: (layer: CALayer, starts: CGFloat, ends: CGFloat)?
    private var sweptBalls: [CALayer] = []
    /// Thrown snowballs in the air, and when each one lands.
    private var thrown: [(layer: CALayer, lands: CGFloat)] = []
    /// The last few places the rolled ball was held, to tell a throw from a drop.
    private var grip: [(point: CGPoint, time: Double)] = []
    private var lastPointer: CGPoint?
    private var holdUntil = 0.0
    private var holding = false
    private var banksDirty = false
    private var seeded = false
    private var surfaces: [WeatherSurface] = []
    private var masks: [CGRect] = []
    private var geometryStale = true

    private var wallAnchor = CACurrentMediaTime()
    private var simAnchor = 100.0
    private var rate = 0.0
    private var lastAdvance: CGFloat = 0
    private var lastAdvanceWall = 0.0
    private var spawnBudget: CGFloat = 0
    private var splashBudget: CGFloat = 0
    private var nextFlash: CGFloat = 0
    private var stillTime: CGFloat = 0
    private var attractor: CGPoint?

    private static let restTime: CGFloat = 13
    private static let fadeTime: CGFloat = 1.5
    private static let snowRestTime: CGFloat = 2.6

    /// Creates a view showing `kind` of weather.
    init(kind: WeatherKind) {
        self.kind = kind
        physics = WeatherPhysics(kind: kind)
        super.init(frame: .zero)
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
        root.addSublayer(stage)
        for part in [back, bankLayer, front, props, flash] { stage.addSublayer(part) }
        cutout.fillColor = .white
        stage.mask = cutout
        flash.backgroundColor = CGColor(red: 0.7, green: 0.82, blue: 1, alpha: 1)
        flash.opacity = 0
        stage.speed = 0
        stage.timeOffset = simAnchor
        if kind == .rain { rain = makeRain() }
    }

    required init?(coder: NSCoder) { fatalError("Use init(kind:)") }
    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [stage, back, bankLayer, front, props, flash, cutout] { part.frame = bounds }
        cutout.path = CGPath(rect: bounds, transform: nil)
        geometryStale = true
        if let rain {
            let lean = bounds.height * 0.213
            rain.emitterPosition = CGPoint(x: bounds.midX + lean / 2, y: -40)
            rain.emitterSize = CGSize(width: bounds.width + lean + 40, height: 1)
            rain.emitterCells = [makeRainCell(pace: 760, perSecond: 110, size: 0.6, alpha: 0.55),
                                 makeRainCell(pace: 1040, perSecond: 34, size: 0.95, alpha: 0.85)]
            rain.birthRate = Float(scale)
        }
        CATransaction.commit()
    }

    /// Weather time, in seconds. It stops while isPaused and stretches with the speed slider.
    var now: CGFloat { CGFloat(simAnchor + (CACurrentMediaTime() - wallAnchor) * rate) }

    private func setRate(_ next: Double) {
        let wall = CACurrentMediaTime()
        simAnchor += (wall - wallAnchor) * rate
        wallAnchor = wall
        rate = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.beginTime = wall
        stage.timeOffset = simAnchor
        stage.speed = Float(next)
        CATransaction.commit()
        lastAdvance = now
    }

    private var scale: CGFloat {
        let boost = kind == .snow ? 1 + max(0, density - 0.70) * 0.4 : 1
        return max(0.5, min(2, bounds.width / 1200)) * density * boost
    }

    private var target: Int {
        switch kind {
        case .snow: return min(225, Int(135 * scale))
        case .petals, .leaves: return Int(64 * scale)
        case .cash: return Int(46 * scale)
        case .fireflies: return max(3, Int(34 * scale))
        case .stars, .rain: return 0
        }
    }

    private var spawnRate: CGFloat {
        switch kind {
        case .snow: return CGFloat(target) * 80 / (bounds.height + 40)
        case .petals: return CGFloat(target) * 59 / (bounds.height + 40)
        case .leaves: return CGFloat(target) * 83 / (bounds.height + 40)
        case .cash: return CGFloat(target) * 93 / (bounds.height + 40)
        case .fireflies: return CGFloat(target) / 13
        case .stars: return 1.7 * scale
        case .rain: return 0
        }
    }

    /// Called a few times a second. Launches newcomers, lets landings take effect and recycles
    /// what has finished. Nothing here moves a particle: that already belongs to the compositor.
    func advance() {
        guard !isPaused, bounds.width > 0, bounds.height > 0 else { return }
        if geometryStale { update(surfaces: surfaces, masks: masks, elapsed: 1) }
        let wall = CACurrentMediaTime()
        guard wall >= holdUntil, wall - lastAdvanceWall >= 0.45 || !seeded else { return }
        lastAdvanceWall = wall
        let time = now
        if holding {
            holding = false
            lastAdvance = time
            if let rain {
                rain.beginTime = time
                rain.lifetime = 1
            }
        }
        let elapsed = min(1.5, time - lastAdvance)
        lastAdvance = time
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !seeded {
            seeded = true
            seed(at: time)
            nextFlash = time + .random(in: 6...14)
        }
        retire(at: time, horizon: 0.6 * rate)
        spawn(elapsed: elapsed, at: time)
        if banksDirty {
            banksDirty = false
            drawBanks(animated: true)
        }
        thrown.removeAll { ball in
            guard time >= ball.lands else { return false }
            ball.layer.removeFromSuperlayer()
            return true
        }
        if let truck, time >= truck.ends { finishPlough() }
        CATransaction.commit()
    }

    private func seed(at time: CGFloat) {
        switch kind {
        case .snow, .petals, .leaves, .cash:
            for _ in 0..<target {
                addFaller(at: time, age: .random(in: 0...1))
            }
        case .fireflies:
            for _ in 0..<target { addFirefly(at: time, age: .random(in: 0...0.6)) }
        case .stars, .rain:
            break
        }
    }

    private func spawn(elapsed: CGFloat, at time: CGFloat) {
        let cap = target * 3 + 60
        spawnBudget += elapsed * spawnRate
        while spawnBudget >= 1 {
            spawnBudget -= 1
            guard particles.count < cap else { continue }
            let start = time + .random(in: 0...elapsed)
            switch kind {
            case .snow, .petals, .leaves, .cash: addFaller(at: start, age: 0)
            case .fireflies: addFirefly(at: start, age: 0)
            case .stars: addMeteor(at: start)
            case .rain: break
            }
        }
        guard kind == .rain else { return }
        splashBudget += elapsed * 26 * scale
        while splashBudget >= 1 {
            splashBudget -= 1
            guard particles.count < 420, let point = physics.randomSplashPoint() else { continue }
            addSplash(at: point, time: time + .random(in: 0...elapsed))
        }
        if time >= nextFlash {
            nextFlash = time + .random(in: 11...24)
            let strike = CAKeyframeAnimation(keyPath: "opacity")
            strike.values = [0, 0.17, 0.04, 0.12, 0]
            strike.keyTimes = [0, 0.08, 0.3, 0.42, 1]
            strike.duration = 0.55
            flash.add(strike, forKey: "strike")
        }
    }

    private func retire(at time: CGFloat, horizon: CGFloat) {
        var index = 0
        while index < particles.count {
            var particle = particles[index]
            if !particle.settled, particle.flight.landingSurfaceID != nil {
                if kind == .snow, particle.look == .faller, particle.flight.endTime <= time {
                    particle.settled = true
                    if particle.flight.landingSurfaceID != 0 || particle.flight.endPoint.x > (bladeX(at: time) ?? -.infinity) {
                        physics.depositSnow(on: particle.flight.landingSurfaceID!, at: particle.flight.endPoint.x,
                                        radius: particle.body.radius * (particle.heavy ? 2.5 : 1))
                        banksDirty = true
                    }
                } else if particle.look == .meteor, particle.flight.endTime <= time + horizon {
                    particle.settled = true
                    for _ in 0..<10 { addSpark(at: particle.flight.endPoint, time: particle.flight.endTime, rain: false) }
                }
                particles[index].settled = particle.settled
            }
            if time >= particle.expires {
                recycle(particle.layer)
                particles.swapAt(index, particles.count - 1)
                particles.removeLast()
            } else {
                index += 1
            }
        }
    }

    private func borrowLayer(in parent: CALayer, image: CGImage, size: CGSize) -> CALayer {
        let layer = pool.popLast() ?? CALayer()
        layer.removeAllAnimations()
        layer.transform = CATransform3DIdentity
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contents = image
        layer.opacity = 0
        layer.isHidden = false
        if layer.superlayer !== parent { parent.addSublayer(layer) }
        return layer
    }

    private func recycle(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.isHidden = true
        if pool.count < 400 { pool.append(layer) } else { layer.removeFromSuperlayer() }
    }

    private func addFaller(at time: CGFloat, age: CGFloat) {
        let isForeground = (kind == .snow || kind == .cash) && Int.random(in: 0..<4) == 0
        let body = physics.makeBody(isForeground: isForeground, density: density)
        let start = time - age * (bounds.height + 40) / body.terminalSpeed
        let origin = CGPoint(x: .random(in: -50...(bounds.width + 30)), y: -12 - .random(in: 0...28))
        let image: CGImage
        let size: CGSize
        var alpha: Float
        switch kind {
        case .petals:
            image = Sprite.petal(variant: Int.random(in: 0..<3))
            size = CGSize(width: body.radius * 2.4, height: body.radius * 1.8)
            alpha = 0.92
        case .leaves:
            image = Sprite.leaf(variant: Int.random(in: 0..<4))
            size = CGSize(width: body.radius * 2.7, height: body.radius * 1.55)
            alpha = 0.94
        case .cash:
            // The layer itself stays empty: the note is a folded shape of strips placed inside it.
            image = Sprite.banknote(showingFace: true, shade: .plain)
            size = CGSize(width: body.radius * 3.05, height: body.radius * 3.05 * Sprite.banknoteSize.height / Sprite.banknoteSize.width)
            alpha = 1
        default:
            image = Sprite.snow
            size = CGSize(width: body.radius * 2.6, height: body.radius * 2.6)
            let plain = body.radius / WeatherPhysics.snowRadiusScale(density: density)
            alpha = Float(0.89 * (0.46 + min(0.46, plain * 0.24)))
        }
        var particle = Particle(layer: borrowLayer(in: isForeground ? front : back, image: image, size: size),
                                look: .faller, body: body,
                                flight: WeatherFlight(startTime: start, points: [origin], angles: [0]),
                                born: start, expires: start, alpha: alpha, isForeground: isForeground)
        if kind == .cash { holdBanknote(in: particle.layer) }
        route(&particle, from: origin, velocity: CGVector(dx: .random(in: -14...22), dy: body.terminalSpeed * 0.7), at: start)
        guard particle.expires > time else { return recycle(particle.layer) }
        show(particle, fresh: true)
        particles.append(particle)
    }

    private func addClump(_ clump: SnowClump, at time: CGFloat, appearing: Bool = false) {
        guard particles.count < target * 3 + 160 else { return }
        let body = WeatherBody(radius: clump.radius * WeatherPhysics.snowRadiusScale(density: density),
                               terminalSpeed: .random(in: 150...210), windExposure: 0.3)
        var particle = Particle(layer: borrowLayer(in: back, image: Sprite.snow,
                                                   size: CGSize(width: body.radius * 2.6, height: body.radius * 2.6)),
                                look: .faller, body: body,
                                flight: WeatherFlight(startTime: time, points: [clump.position], angles: [0]),
                                born: time, expires: time, alpha: 0.8,
                                releasedFrom: clump.fallsPastSource ? clump.sourceID : nil, heavy: true)
        route(&particle, from: clump.position, velocity: clump.velocity, at: time)
        show(particle, fresh: appearing)
        particles.append(particle)
    }

    private func addFirefly(at time: CGFloat, age: CGFloat) {
        let body = physics.makeBody(isForeground: false, density: density)
        let life = CGFloat.random(in: 10...16)
        let born = time - age * life
        let origin = CGPoint(x: .random(in: 30...max(31, bounds.width - 30)), y: .random(in: 40...max(41, bounds.height - 30)))
        var particle = Particle(layer: borrowLayer(in: back, image: Sprite.glow,
                                                   size: CGSize(width: body.radius * 10, height: body.radius * 10)),
                                look: .firefly, body: body,
                                flight: WeatherFlight(startTime: time, points: [origin], angles: [0]),
                                born: born, expires: born + life, alpha: 0.9)
        let heading = CGFloat.random(in: 0...(2 * .pi))
        particle.flight = physics.wanderingFlight(of: body, from: origin,
                                         velocity: CGVector(dx: cos(heading) * body.terminalSpeed, dy: sin(heading) * body.terminalSpeed),
                                         at: time, duration: particle.expires - time, toward: attractor)
        show(particle, fresh: true)
        particles.append(particle)
    }

    private func addMeteor(at time: CGFloat) {
        let body = physics.makeBody(isForeground: false, density: density)
        let pace = CGFloat.random(in: 400...580)
        let velocity = CGVector(dx: -0.788 * pace, dy: 0.616 * pace)
        let origin = CGPoint(x: .random(in: (bounds.width * 0.15)...(bounds.width + bounds.height * 0.6)), y: -8)
        let flight = physics.straightFlight(from: origin, velocity: velocity, at: time)
        let layer = borrowLayer(in: back, image: Sprite.streak,
                                size: CGSize(width: pace * 0.2, height: body.radius * 2.6))
        layer.anchorPoint = CGPoint(x: 0.96, y: 0.5)
        layer.transform = CATransform3DMakeRotation(atan2(velocity.dy, velocity.dx), 0, 0, 1)
        let particle = Particle(layer: layer, look: .meteor, body: body, flight: flight,
                                born: time, expires: flight.endTime, alpha: 0.95)
        show(particle, fresh: true)
        particles.append(particle)
    }

    private func addSpark(at point: CGPoint, time: CGFloat, rain: Bool) {
        let spark = WeatherPhysics.makeSpark(isRaindrop: rain)
        let flight = physics.flight(of: spark.body, from: point, velocity: spark.velocity, at: time,
                                 collides: false, limit: spark.life)
        let side = spark.body.radius * 2.6
        let particle = Particle(layer: borrowLayer(in: back, image: rain ? Sprite.droplet : Sprite.ember,
                                                   size: CGSize(width: side, height: side)),
                                look: .spark, body: spark.body, flight: flight,
                                born: time, expires: flight.endTime, alpha: rain ? 0.8 : 0.95)
        show(particle, fresh: false)
        particles.append(particle)
    }

    private func addSplash(at point: CGPoint, time: CGFloat) {
        let life = CGFloat.random(in: 0.26...0.4)
        let width = CGFloat.random(in: 9...16)
        let layer = borrowLayer(in: back, image: Sprite.crown, size: CGSize(width: width, height: width * 0.42))
        let crown = Particle(layer: layer, look: .crown, body: WeatherBody(radius: 1, terminalSpeed: 1),
                             flight: WeatherFlight(startTime: time, times: [0, life], points: [point, point], angles: [0, 0]),
                             born: time, expires: time + life, alpha: 0.7)
        show(crown, fresh: false)
        particles.append(crown)
        for _ in 0..<2 { addSpark(at: CGPoint(x: point.x, y: point.y - 1), time: time, rain: true) }
    }

    /// Plans a falling particle's path from here, and how long it stays once it lands.
    private func route(_ particle: inout Particle, from origin: CGPoint, velocity: CGVector, at time: CGFloat) {
        var flight = physics.flight(of: particle.body, from: origin, velocity: velocity, at: time,
                                 isForeground: particle.isForeground, skipping: particle.releasedFrom)
        particle.restingOn = nil
        particle.settled = false
        var afterlife: CGFloat = 0
        if let landing = flight.landingSurfaceID {
            flight.points[flight.points.count - 1] = restPoint(on: landing, at: flight.endPoint)
            particle.restingOn = landing
            afterlife = kind == .snow ? Self.snowRestTime : Self.restTime + Self.fadeTime
        }
        particle.flight = flight
        particle.expires = flight.endTime + afterlife
    }

    /// Where something that reached a ledge at `point` comes to rest: on top of the snow already
    /// there, or a little heaped up for leaves and petals.
    private func restPoint(on id: UInt32, at point: CGPoint) -> CGPoint {
        guard kind == .snow else { return CGPoint(x: point.x, y: point.y - .random(in: 0.6...6.5)) }
        let lift = physics.snowBanks.first { $0.surface.id == id }.map { driftHeight($0, at: point.x) } ?? 0
        return CGPoint(x: point.x, y: point.y - max(0, lift - 1))
    }

    /// Hands a particle's planned path to the compositor.
    private func show(_ particle: Particle, fresh: Bool) {
        let flight = particle.flight
        let layer = particle.layer
        let total = max(0.02, particle.expires - flight.startTime)
        if flight.points.count > 1, flight.duration > 0 {
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.values = flight.points.map { NSValue(point: $0) }
            fly.keyTimes = flight.times.map { NSNumber(value: Double($0 / flight.duration)) }
            fly.calculationMode = flight.points.count > 2 ? .cubic : .linear
            fly.duration = flight.duration
            fly.beginTime = flight.startTime
            fly.fillMode = .backwards
            layer.add(fly, forKey: "fly")
        }
        layer.position = flight.endPoint

        let alpha = particle.alpha
        var keys: [(CGFloat, Float)]
        switch particle.look {
        case .faller:
            let rise = fresh ? (particle.heavy ? 0.03 : min(0.6, total * 0.3)) : 0
            keys = [(0, fresh ? 0 : alpha), (rise, alpha)]
            if flight.landingSurfaceID != nil {
                keys += [(total - (kind == .snow ? 1.1 : Self.fadeTime), alpha), (total, 0)]
            } else {
                keys.append((total, alpha))
            }
            if particle.body.tumbles {
                let turn = CAKeyframeAnimation(keyPath: "transform")
                let turns = flight.times.indices.map { index -> CATransform3D in
                    let time = flight.startTime + flight.times[index]
                    if kind == .cash { return banknoteTransform(for: particle, sample: index) }
                    let face = 0.3 + 0.35 * (1 + cos(2.6 * particle.body.swayRate * time + particle.body.phase * 3))
                    return CATransform3DScale(CATransform3DMakeRotation(flight.angles[index], 0, 0, 1), 1, face, 1)
                }
                turn.values = turns.map { NSValue(caTransform3D: $0) }
                turn.keyTimes = flight.times.map { NSNumber(value: Double($0 / max(0.001, flight.duration))) }
                turn.duration = max(0.02, flight.duration)
                turn.beginTime = flight.startTime
                turn.fillMode = .backwards
                // A banknote turns as a whole folded shape inside its layer; a leaf or petal is the layer.
                let turning = kind == .cash ? layer.sublayers?.first ?? layer : layer
                turning.add(turn, forKey: "turn")
                turning.transform = turns[turns.count - 1]
            }
        case .spark:
            keys = [(0, alpha), (total * 0.45, alpha), (total, 0)]
        case .crown:
            keys = [(0, alpha), (total, 0)]
            let spread = CABasicAnimation(keyPath: "transform.scale")
            spread.fromValue = 0.25
            spread.toValue = 1
            spread.duration = total
            spread.beginTime = flight.startTime
            spread.fillMode = .backwards
            spread.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(spread, forKey: "spread")
        case .meteor:
            keys = [(0, 0), (min(0.12, total * 0.4), alpha), (total, alpha)]
        case .firefly:
            let life = particle.expires - particle.born
            keys = stride(from: CGFloat(0), through: total, by: 0.2).map { offset in
                let age = flight.startTime + offset - particle.born
                let envelope = max(0, min(1, age / 1.5, (life - age) / 2))
                let pulse = 0.62 + 0.38 * sin((flight.startTime + offset) * 2.3 + particle.body.phase * 5)
                return (offset, alpha * Float(envelope * pulse))
            }
            keys.append((total, 0))
        }
        var times: [NSNumber] = []
        var values: [NSNumber] = []
        var last: CGFloat = -1
        for (offset, value) in keys where offset > last || times.isEmpty {
            times.append(NSNumber(value: Double(min(1, max(0, offset / total)))))
            values.append(NSNumber(value: value))
            last = offset
        }
        guard times.count > 1 else { return }
        times[times.count - 1] = 1
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = values
        fade.keyTimes = times
        fade.duration = total
        fade.beginTime = flight.startTime
        fade.fillMode = .backwards
        layer.add(fade, forKey: "fade")
    }

    /// Puts a folded banknote inside `layer`, or keeps the one a recycled layer already holds.
    /// The layer supplies the perspective; the note inside it is what turns.
    private func holdBanknote(in layer: CALayer) {
        layer.contents = nil
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 420
        layer.sublayerTransform = perspective
        let note = layer.sublayers?.first ?? {
            let note = Banknote.makeLayer()
            layer.addSublayer(note)
            return note
        }()
        note.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
    }

    /// How a banknote is turned at one sample of its flight: end over end, rolling from side to
    /// side and spinning flat, at the size its distance from the viewer gives it. Once it lands it
    /// lies tipped back a little, the way paper settles.
    private func banknoteTransform(for particle: Particle, sample index: Int) -> CATransform3D {
        let flight = particle.flight
        let body = particle.body
        let time = flight.startTime + flight.times[index]
        let size = body.radius * 3.05 / Sprite.banknoteSize.width
        let landed = index == flight.times.count - 1 && flight.landingSurfaceID != nil
        let pitch = landed ? 1.02 + 0.2 * sin(body.phase * 5) : 1.9 * body.swayRate * time + body.phase * 3
        let roll = landed ? 0 : 0.75 * sin(0.8 * body.swayRate * time + body.phase * 2)
        var transform = CATransform3DMakeScale(size, size, size)
        transform = CATransform3DRotate(transform, flight.angles[index], 0, 0, 1)
        transform = CATransform3DRotate(transform, pitch, 1, 0, 0)
        return CATransform3DRotate(transform, roll, 0, 1, 0)
    }

    private func position(of particle: Particle, at time: CGFloat) -> CGPoint {
        if time >= particle.flight.endTime { return particle.flight.endPoint }
        return particle.layer.presentation()?.position ?? particle.flight.state(at: time).position
    }

    /// Tells the view where the windows are now, so weather can land on, ride along with and fall off them.
    func update(surfaces: [WeatherSurface], masks: [CGRect], elapsed: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let change = physics.updateSurfaces(surfaces, in: bounds.size, elapsed: elapsed)
        self.surfaces = surfaces
        guard change.hasChanges || geometryStale || self.masks != masks else { return }
        let time = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if geometryStale || self.masks != masks {
            geometryStale = false
            self.masks = masks
            var path = CGPath(rect: bounds, transform: nil)
            for rect in masks.prefix(120) where rect.intersects(bounds) {
                path = path.subtracting(CGPath(rect: rect, transform: nil))
            }
            cutout.path = path
        }
        if change.hasChanges {
            if kind == .snow { drawBanks(animated: false) }
            for index in particles.indices {
                var particle = particles[index]
                guard particle.look == .faller else { continue }
                if let id = particle.restingOn, time >= particle.flight.endTime {
                    let origin = particle.flight.endPoint
                    if change.removedIDs.contains(id) {
                        particle.isForeground = true
                        particle.releasedFrom = id
                        front.addSublayer(particle.layer)
                        route(&particle, from: origin, velocity: CGVector(dx: .random(in: -12...12), dy: .random(in: 0...40)), at: time)
                    } else if change.resizedIDs.contains(id), let rect = physics.ledges.first(where: { $0.id == id })?.rect {
                        guard origin.x < rect.minX || origin.x > rect.maxX else {
                            let point = restPoint(on: id, at: CGPoint(x: origin.x, y: rect.minY))
                            particle.flight.points[particle.flight.points.count - 1] = point
                            particle.layer.position = point
                            particles[index] = particle
                            continue
                        }
                        particle.releasedFrom = id
                        route(&particle, from: origin, velocity: CGVector(dx: .random(in: -8...8), dy: .random(in: 0...30)), at: time)
                    } else if let offset = change.offsets[id] {
                        let point = CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
                        guard let shake = change.shakes[id], CGFloat.random(in: 0...1) < shake.fraction else {
                            particle.flight.points[particle.flight.points.count - 1] = point
                            particle.layer.position = point
                            particles[index] = particle
                            continue
                        }
                        let pace = max(1, hypot(shake.velocity.dx, shake.velocity.dy))
                        let keep = min(1, 600 / pace) * .random(in: 0.4...1)
                        particle.releasedFrom = nil
                        route(&particle, from: CGPoint(x: point.x, y: point.y - 2),
                              velocity: CGVector(dx: shake.velocity.dx * keep + .random(in: -40...40),
                                                 dy: shake.velocity.dy * keep - .random(in: 20...90)), at: time)
                    } else {
                        continue
                    }
                } else if time < particle.flight.endTime,
                          !physics.isStillValid(particle.flight, after: time, isForeground: particle.isForeground,
                                              skipping: particle.releasedFrom) {
                    let state = particle.flight.state(at: time)
                    route(&particle, from: position(of: particle, at: time), velocity: state.velocity, at: time)
                } else {
                    continue
                }
                show(particle, fresh: false)
                particles[index] = particle
            }
            for clump in change.clumps { addClump(clump, at: time) }
        }
        CATransaction.commit()
    }

    /// Tells the view where the pointer is, so it can brush snow, scatter leaves or draw fireflies.
    func pointerMoved(to point: CGPoint, velocity: CGVector, elapsed: CGFloat) {
        guard !isPaused else { return }
        let pace = hypot(velocity.dx, velocity.dy)
        let previous = lastPointer ?? point
        lastPointer = point
        switch kind {
        case .snow:
            guard pace > 60, !holding else { return }
            brush(from: previous, to: point, velocity: velocity)
        case .fireflies:
            stillTime = pace < 22 ? stillTime + elapsed : 0
            let gather = stillTime > 0.45 && bounds.contains(point) ? point : nil
            guard (gather == nil) != (attractor == nil) else { return }
            attractor = gather
            let time = now
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for index in particles.indices where particles[index].look == .firefly && particles[index].expires - time > 0.5 {
                var particle = particles[index]
                let state = particle.flight.state(at: time)
                particle.flight = physics.wanderingFlight(of: particle.body, from: position(of: particle, at: time), velocity: state.velocity,
                                                 at: time, duration: particle.expires - time, toward: gather)
                show(particle, fresh: false)
                particles[index] = particle
            }
            CATransaction.commit()
        case .leaves, .cash:
            guard pace > 70, bounds.insetBy(dx: -90, dy: -90).contains(point) else { return }
            let time = now
            let reach: CGFloat = 85
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for index in particles.indices where particles[index].look == .faller {
                var particle = particles[index]
                let resting = particle.restingOn != nil && time >= particle.flight.endTime
                guard resting || time - particle.flight.startTime > 0.35 else { continue }
                let origin = position(of: particle, at: time)
                let dx = origin.x - point.x, dy = origin.y - point.y
                let distance = hypot(dx, dy)
                guard distance < reach else { continue }
                let push = 1 - distance / (reach * 1.3)
                let carry = min(900, pace) * push * .random(in: 0.35...0.7)
                var next = CGVector(dx: velocity.dx / pace * carry + dx / max(10, distance) * .random(in: 20...90),
                                    dy: velocity.dy / pace * carry * 0.5 - .random(in: 50...170) * push)
                if !resting {
                    let state = particle.flight.state(at: time)
                    next = CGVector(dx: state.velocity.dx + next.dx * 0.6, dy: state.velocity.dy + next.dy * 0.6)
                }
                particle.releasedFrom = nil
                route(&particle, from: CGPoint(x: origin.x, y: origin.y - 1.5), velocity: next, at: time)
                show(particle, fresh: false)
                particles[index] = particle
            }
            CATransaction.commit()
        default:
            break
        }
    }

    /// The pointer sweeps settled snow off whatever it passes along: a window's top edge or the ground.
    private func brush(from start: CGPoint, to end: CGPoint, velocity: CGVector) {
        let steps = max(1, min(16, Int(hypot(end.x - start.x, end.y - start.y) / 12)))
        var clumps: [SnowClump] = []
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            for bank in physics.snowBanks where !bank.depths.isEmpty {
                let top = bank.surface.rect.minY
                guard point.x >= bank.surface.rect.minX, point.x <= bank.surface.rect.maxX,
                      point.y > top - driftHeight(bank, at: point.x) - 9, point.y < top + 5 else { continue }
                clumps += physics.brushSnow(off: bank.surface.id, at: point.x, reach: 13, velocity: velocity)
            }
        }
        guard !clumps.isEmpty else { return }
        let time = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for clump in clumps { addClump(clump, at: time) }
        banksDirty = false
        drawBanks(animated: true)
        CATransaction.commit()
    }

    private func drawBanks(animated: Bool) {
        var live = Set<UInt32>()
        for bank in physics.snowBanks {
            let id = bank.surface.id
            guard let path = bankPath(bank) else { continue }
            live.insert(id)
            var entry = bankShapes[id] ?? {
                let shape = CAShapeLayer()
                shape.fillColor = CGColor(red: 0.96, green: 0.98, blue: 1, alpha: 0.93)
                shape.frame = bounds
                bankLayer.addSublayer(shape)
                return (shape, .null)
            }()
            if animated, entry.rect == bank.surface.rect, let old = entry.shape.presentation()?.path ?? entry.shape.path {
                let grow = CABasicAnimation(keyPath: "path")
                grow.fromValue = old
                grow.toValue = path
                grow.duration = 0.9
                entry.shape.add(grow, forKey: "grow")
            } else {
                entry.shape.removeAnimation(forKey: "grow")
            }
            entry.shape.path = path
            entry.rect = bank.surface.rect
            bankShapes[id] = entry
        }
        for (id, entry) in bankShapes where !live.contains(id) {
            entry.shape.removeFromSuperlayer()
            bankShapes[id] = nil
        }
    }

    /// How high the snow stands at `x`. The ground gathers into drifts: broad hills with smaller
    /// mounds riding on them, so it reads as a landscape even where only its crest shows. A window
    /// ledge holds a thin, slightly uneven cap that tapers at both ends.
    private func driftHeight(_ bank: SnowBank, at x: CGFloat) -> CGFloat {
        let depth = bank.depth(at: x)
        let grain = bank.grain
        if bank.surface.id == 0 {
            let nearby = (bank.depth(at: x - 16) + bank.depth(at: x + 16)) * 0.25 + depth * 0.5
            let hill = pow(0.5 + 0.5 * sin(x * 0.0125 + grain + 1.2 * sin(x * 0.0041 + grain * 1.7)), 1.4)
            let mound = 0.5 + 0.5 * sin(x * 0.041 + grain * 2.3 + 0.6 * sin(x * 0.009 + grain))
            return nearby * (0.3 + 1.25 * hill + 0.35 * mound * (0.4 + hill))
        }
        let left = max(0, bank.surface.rect.minX)
        let right = min(bounds.width, bank.surface.rect.maxX)
        let lumps = 0.74 + 0.17 * sin(x * 0.047 + grain) + 0.11 * sin(x * 0.113 + grain * 3.1)
        return depth * lumps * max(0, min(1, (x - left) / 11, (right - x) / 11))
    }

    private func bankPath(_ bank: SnowBank) -> CGPath? {
        guard bank.depths.contains(where: { $0 > 0.16 }) else { return nil }
        let rect = bank.surface.rect
        let left = max(0, rect.minX)
        let right = min(bounds.width, rect.maxX)
        guard right - left > 6 else { return nil }
        let count = max(3, Int((right - left) / 6))
        let base = rect.minY + (bank.surface.id == 0 ? 0.9 : 1.5)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: base))
        for i in 0...count {
            let x = left + (right - left) * CGFloat(i) / CGFloat(count)
            path.addLine(to: CGPoint(x: x, y: base - driftHeight(bank, at: x)))
        }
        path.addLine(to: CGPoint(x: right, y: base))
        path.closeSubpath()
        return path
    }

    /// Where the plough's blade is, while it is out.
    private func bladeX(at time: CGFloat) -> CGFloat? {
        guard let truck else { return nil }
        return Self.ploughStart + Self.bladeReach + Self.ploughPace * (time - truck.starts)
    }

    private static let ploughStart: CGFloat = -60
    private static let ploughPace: CGFloat = 150
    private static let bladeReach: CGFloat = 36

    /// Sends the plough across the bottom of the screen. Snow on window ledges tips off first, and
    /// the blade then clears the ground, the snowballs and anything that lands in front of it.
    func sendPlough() {
        guard kind == .snow, truck == nil, !isPaused, bounds.width > 0 else { return }
        let time = now
        let finish = bounds.width + 90
        let crossing = (finish - Self.ploughStart) / Self.ploughPace
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for clump in physics.shedLedgeSnow() { addClump(clump, at: time) }
        drawBanks(animated: false)

        let layer = CALayer()
        layer.contents = Sprite.truck
        layer.bounds = CGRect(x: 0, y: 0, width: 80, height: 48)
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.position = CGPoint(x: finish, y: bounds.height - 1)
        let drive = CABasicAnimation(keyPath: "position.x")
        drive.fromValue = Self.ploughStart
        drive.toValue = finish
        drive.duration = crossing
        layer.add(drive, forKey: "drive")
        props.addSublayer(layer)

        if let ground = bankShapes[0] {
            let heap = CALayer()
            heap.contents = Sprite.heap
            heap.bounds = CGRect(x: 0, y: 0, width: 62, height: 34)
            heap.anchorPoint = CGPoint(x: 0, y: 1)
            heap.position = CGPoint(x: 40 + Self.bladeReach - 5, y: 48)
            let gather = CABasicAnimation(keyPath: "transform.scale")
            gather.fromValue = 0.15
            gather.toValue = 1
            gather.duration = crossing
            heap.add(gather, forKey: "gather")
            layer.addSublayer(heap)

            let wipe = CALayer()
            wipe.backgroundColor = .white
            wipe.anchorPoint = .zero
            wipe.bounds = CGRect(x: 0, y: 0, width: bounds.width + 200, height: bounds.height)
            wipe.position = CGPoint(x: finish + Self.bladeReach, y: 0)
            let clear = CABasicAnimation(keyPath: "position.x")
            clear.fromValue = Self.ploughStart + Self.bladeReach
            clear.toValue = finish + Self.bladeReach
            clear.duration = crossing
            wipe.add(clear, forKey: "clear")
            ground.shape.mask = wipe
        }

        for (index, ball) in snowballs.placedBalls.enumerated() where index < ballLayers.count {
            let reach = max(0, ball.center.x - ball.radius - Self.bladeReach - Self.ploughStart) / Self.ploughPace
            let scoop = CABasicAnimation(keyPath: "opacity")
            scoop.fromValue = 1
            scoop.toValue = 0
            scoop.duration = 0.25
            scoop.beginTime = time + reach
            scoop.fillMode = .backwards
            ballLayers[index].add(scoop, forKey: "scoop")
            ballLayers[index].opacity = 0
        }
        sweptBalls += ballLayers
        ballLayers.removeAll()
        snowballs = Snowballs()
        rollingLayer?.removeFromSuperlayer()
        rollingLayer = nil
        truck = (layer, time, time + crossing)
        CATransaction.commit()
    }

    private func finishPlough() {
        truck?.layer.removeFromSuperlayer()
        truck = nil
        for layer in sweptBalls { layer.removeFromSuperlayer() }
        sweptBalls.removeAll()
        physics.clearGround()
        bankShapes[0]?.shape.mask = nil
        drawBanks(animated: false)
    }

    /// Wipes everything and waits before starting again from nothing: an empty sky, bare ledges and
    /// bare ground. Used when a display comes back into view, so the weather arrives afresh.
    func restart(after delay: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for particle in particles { recycle(particle.layer) }
        particles.removeAll()
        if truck != nil { finishPlough() }
        physics.clearSettledSnow()
        drawBanks(animated: false)
        banksDirty = false
        for layer in ballLayers { layer.removeFromSuperlayer() }
        ballLayers.removeAll()
        rollingLayer?.removeFromSuperlayer()
        rollingLayer = nil
        for ball in thrown { ball.layer.removeFromSuperlayer() }
        thrown.removeAll()
        snowballs = Snowballs()
        seeded = true
        holding = true
        holdUntil = CACurrentMediaTime() + delay
        spawnBudget = 0
        splashBudget = 0
        stillTime = 0
        attractor = nil
        rain?.lifetime = 0
        flash.removeAllAnimations()
        CATransaction.commit()
    }

    private func addBallLayer(for ball: Snowball) -> CALayer {
        let layer = CALayer()
        layer.contents = Sprite.snowball
        layer.bounds = CGRect(x: 0, y: 0, width: ball.radius * 2, height: ball.radius * 2)
        layer.position = ball.center
        props.addSublayer(layer)
        return layer
    }

    private func dress(_ ball: CALayer, with image: CGImage, after delay: CGFloat, frame: CGRect) {
        let layer = CALayer()
        layer.contents = image
        layer.frame = frame
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.duration = 0.3
        appear.beginTime = now + delay
        appear.fillMode = .backwards
        layer.add(appear, forKey: "appear")
        ball.addSublayer(layer)
    }

    /// Starts rolling a snowball at `point`.
    func beginRollingBall(at point: CGPoint) {
        snowballs.beginRolling(at: point)
        rollBall(to: point)
    }

    /// Moves the snowball being rolled to `point`.
    func rollBall(to point: CGPoint) {
        grip.append((point, CACurrentMediaTime()))
        if grip.count > 8 { grip.removeFirst() }
        snowballs.roll(to: point)
        guard let ball = snowballs.rollingBall else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let layer = rollingLayer ?? addBallLayer(for: ball)
        rollingLayer = layer
        layer.bounds = CGRect(x: 0, y: 0, width: ball.radius * 2, height: ball.radius * 2)
        layer.position = ball.center
        CATransaction.commit()
    }

    /// How fast the hand was moving as it let go, from where it was a moment earlier.
    private func releaseVelocity(at point: CGPoint) -> CGVector {
        let time = CACurrentMediaTime()
        defer { grip.removeAll() }
        guard let earlier = grip.last(where: { time - $0.time > 0.04 }), time - earlier.time < 0.25 else { return .zero }
        return CGVector(dx: (point.x - earlier.point.x) / (time - earlier.time), dy: (point.y - earlier.point.y) / (time - earlier.time))
    }

    /// A ball let go while the hand is moving fast is thrown: it flies in an arc under gravity and
    /// bursts where it comes down.
    private func throwBall(_ ball: Snowball, velocity: CGVector) {
        let stretch = CGFloat(max(0.05, rate))
        let floor = bounds.height - 4
        var position = ball.center
        var v = CGVector(dx: max(-2200, min(2200, velocity.dx)), dy: max(-2200, min(2200, velocity.dy)))
        var points = [position]
        let step: CGFloat = 1.0 / 30
        while position.y < floor, position.x > -60, position.x < bounds.width + 60, points.count < 240 {
            v.dy += Snowballs.gravity * step
            position.x += v.dx * step
            position.y += v.dy * step
            points.append(position)
        }
        let flight = CGFloat(points.count - 1) * step * stretch
        let time = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rollingLayer?.removeFromSuperlayer()
        rollingLayer = nil
        let layer = addBallLayer(for: ball)
        let arc = CAKeyframeAnimation(keyPath: "position")
        arc.values = points.map { NSValue(point: $0) }
        arc.calculationMode = .cubic
        arc.duration = flight
        layer.add(arc, forKey: "arc")
        layer.position = position
        let vanish = CABasicAnimation(keyPath: "opacity")
        vanish.fromValue = 1
        vanish.toValue = 1
        vanish.duration = flight
        layer.add(vanish, forKey: "vanish")
        layer.opacity = 0
        thrown.append((layer, time + flight))
        if position.y >= floor {
            for _ in 0..<Int(6 + ball.radius * 0.5) {
                let piece = SnowClump(position: CGPoint(x: position.x + .random(in: -ball.radius...ball.radius), y: floor - 3),
                                      velocity: CGVector(dx: v.dx * 0.25 + CGFloat.random(in: -170...170),
                                                         dy: -CGFloat.random(in: 70...300) - abs(v.dy) * 0.12),
                                      radius: .random(in: 1.2...2.6), sourceID: 0, fallsPastSource: false)
                addClump(piece, at: time + flight, appearing: true)
            }
        }
        CATransaction.commit()
    }

    /// Lets go of the snowball at `point`: dropped if the hand is slow, thrown if it is fast.
    func releaseBall(at point: CGPoint) {
        let velocity = releaseVelocity(at: point)
        if hypot(velocity.dx, velocity.dy) > 520 {
            snowballs.roll(to: point)
            if let ball = snowballs.removeRollingBall() { return throwBall(ball, velocity: velocity) }
        }
        let dropped = snowballs.dropBall(at: point, in: bounds.size, floorY: bounds.height - 6)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rollingLayer?.removeFromSuperlayer()
        rollingLayer = nil
        if let dropped {
            let layer = addBallLayer(for: dropped.ball)
            ballLayers.append(layer)
            let stretch = CGFloat(max(0.05, rate))
            let rise = dropped.ball.center.y - dropped.from.y
            let fall = sqrt(2 * abs(rise) / Snowballs.gravity) * stretch
            if fall > 0.01 * stretch {
                let drop = CABasicAnimation(keyPath: "position")
                drop.fromValue = NSValue(point: dropped.from)
                drop.toValue = NSValue(point: dropped.ball.center)
                drop.duration = fall
                drop.timingFunction = rise > 0 ? CAMediaTimingFunction(controlPoints: 1.0 / 3, 0, 2.0 / 3, 1.0 / 3)
                                               : CAMediaTimingFunction(name: .easeOut)
                layer.add(drop, forKey: "drop")
                let radius = dropped.ball.radius
                let give = min(0.16, 0.05 + rise / 2500)
                let settle = CAKeyframeAnimation(keyPath: "transform")
                settle.values = [(1, 1), (1 + give * 0.7, 1 - give), (1 - give * 0.2, 1 + give * 0.25), (1, 1)].map { wide, tall in
                    NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(0, radius * (1 - tall), 0), wide, tall, 1))
                }
                settle.keyTimes = [0, 0.3, 0.7, 1]
                settle.duration = 0.3 * stretch
                settle.beginTime = now + fall
                layer.add(settle, forKey: "settle")
            }
            for man in snowballs.snowmen where ballLayers[man.head].sublayers == nil {
                let radius = snowballs.placedBalls[man.head].radius
                let girth = snowballs.placedBalls[man.torso].radius
                dress(ballLayers[man.head], with: Sprite.face, after: fall,
                      frame: CGRect(x: 0, y: -radius * 0.75, width: radius * 2, height: radius * 2.75))
                dress(ballLayers[man.torso], with: Sprite.torso, after: fall,
                      frame: CGRect(x: -girth * 0.8, y: 0, width: girth * 3.6, height: girth * 2))
            }
        }
        CATransaction.commit()
    }

    private func makeRain() -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.renderMode = .unordered
        back.addSublayer(emitter)
        return emitter
    }

    private func makeRainCell(pace: CGFloat, perSecond: Float, size: CGFloat, alpha: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = Sprite.rain
        cell.contentsScale = 4
        cell.birthRate = perSecond
        cell.velocity = pace
        cell.velocityRange = pace * 0.1
        cell.emissionLongitude = atan2(-0.208, -0.978)
        cell.lifetime = Float((bounds.height + 90) / (pace * 0.9 * 0.978))
        cell.scale = size
        cell.scaleRange = size * 0.25
        cell.color = CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
        cell.alphaRange = 0.25
        return cell
    }
}
