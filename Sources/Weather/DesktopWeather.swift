import AppKit
import CoreGraphics
import IOKit.ps
import QuartzCore

/// A panel that never takes keyboard focus, used for the weather overlay.
@MainActor
final class WeatherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Runs the weather on every display: creates the overlays, tracks windows and the pointer, and paces the work.
@MainActor
final class DesktopWeather {
    private struct WindowBounds: Sendable {
        let id: UInt32
        let rect: CGRect
        let layer: Int
        let isDock: Bool
        let isStageManagerWindow: Bool
    }

    private final class DisplayWeather {
        let panel: WeatherPanel
        let view: WeatherView
        var pickup: WeatherPanel?
        var geometryRevision = -1
        var lastGeometry = 0.0
        /// Set while a full-screen window or display sleep hides the weather.
        var obscured = false

        init(panel: WeatherPanel, view: WeatherView) {
            self.panel = panel
            self.view = view
        }
    }

    private static let idlePace = 0.25
    /// Seconds between routine looks at where every window is. Each look is a round trip to the
    /// window server, so this is the main cost of running and is kept as long as feels responsive.
    private static let surveyInterval = 0.4
    /// When to look again after something that usually opens, closes or minimises a window. A few
    /// well-timed looks catch the change as it settles, where looking continuously would cost far more.
    private static let followUpDelays = [0.08, 0.3, 0.6, 1.0]
    private static let pointerPace = 1.0 / 15
    private static let dragPace = 1.0 / 30
    private static let glidePace = 1.0 / 60

    private var displays: [CGDirectDisplayID: DisplayWeather] = [:]
    private var geometry: [WindowBounds] = []
    private var timer: Timer?
    private var pace = 0.0
    private var mouseMonitor: Any?
    private var lastScan = 0.0
    private var lastUpkeep = 0.0
    private var lastTick = 0.0
    private var lastMouse = NSEvent.mouseLocation
    private var lastMouseMove = 0.0
    private var geometryRevision = 0
    private var scanInProgress = false
    private var dragTarget: UInt32?
    private var dragStart = 0.0
    private var dragMovedWindow = false
    /// Where the dragged window and the pointer were at the last report from the window server.
    private var dragAnchor: (rect: CGRect, mouse: CGPoint)?
    /// True once the window has been seen moving exactly with the pointer: a move, not a resize.
    private var dragGlides = false
    private var dragScanInProgress = false
    private var wasDragging = false
    private var generation = 0
    private let windowQueue = DispatchQueue(label: "Driftwood.window-bounds", qos: .utility)
    private var lastPower = 0.0
    private var powerFactor = 1.0
    private var screens: [NSScreen] = []
    private var followsPointer = false
    /// How much weather falls.
    var density = 0.65
    /// How fast weather time runs; `0.42` is natural speed.
    var fallSpeed = 0.48
    /// Whether the weather is animating.
    var isMotionEnabled = true
    private var spaceObserver: NSObjectProtocol?
    private var appObservers: [NSObjectProtocol] = []
    /// The earliest time another round of follow-up looks may be scheduled.
    private var nextFollowUp = 0.0

    /// How long the sky stays empty after a display comes back into view.
    private static let returnDelay = 3.0

    /// Starts `kind` of weather on each of `screens`, replacing whatever was running.
    func start(_ kind: WeatherKind, on screens: [NSScreen]) {
        stop()
        self.screens = screens
        lastScan = 0
        lastPower = 0
        lastUpkeep = 0
        do {
            followsPointer = kind == .leaves || kind == .snow || kind == .cash
            for screen in screens {
                let view = WeatherView(kind: kind)
                let panel = WeatherPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.isExcludedFromWindowsMenu = true
                panel.contentView = view
                panel.setFrame(screen.frame, display: false)
                let display = DisplayWeather(panel: panel, view: view)
                if kind == .snow { display.pickup = makeSnowPickup(on: screen, view: view) }
                displays[screen.displayID] = display
            }
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                MainActor.assumeIsolated {
                    let now = ProcessInfo.processInfo.systemUptime
                    if event.type == .leftMouseDown {
                        self?.lastMouseMove = now
                        self?.setPace(Self.dragPace)
                    } else {
                        self?.surveySoon()
                    }
                }
            }
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                         NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                appObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.surveySoon()
                    }
                })
            }
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.surveyNow() }
            }
            setPace(Self.idlePace)
            tick()
        }
    }

    /// Called when the active Space changes. Each display can have its own Spaces, and macOS does
    /// not say which display switched, so a display counts as changed when the set of windows on it
    /// is different from a moment ago. Only those displays start afresh.
    private func surveyNow() {
        guard timer != nil else { return }
        let before = windowsByDisplay()
        generation += 1
        scanInProgress = false
        dragScanInProgress = false
        geometry = Self.windowBounds()
        geometryRevision += 1
        let after = windowsByDisplay()
        let now = ProcessInfo.processInfo.systemUptime
        lastScan = now
        lastUpkeep = now

        var changed = Set(screens.map(\.displayID))
        if NSScreen.screensHaveSeparateSpaces {
            changed = changed.filter { before[$0] != after[$0] }
            if changed.isEmpty, let pointer = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
                // Two empty desktops look alike; the switch then happened where the pointer is.
                changed = [pointer.displayID]
            }
        }
        for id in changed {
            guard let display = displays[id] else { continue }
            display.obscured = false
            display.view.restart(after: Self.returnDelay)
        }
        upkeep(now: now)
        applyGeometry(now: now)
    }

    private func windowsByDisplay() -> [CGDirectDisplayID: Set<UInt32>] {
        var result: [CGDirectDisplayID: Set<UInt32>] = [:]
        for screen in screens {
            let frame = screen.quartzFrame
            result[screen.displayID] = Set(geometry.filter { $0.layer == 0 && $0.rect.intersects(frame) }.map(\.id))
        }
        return result
    }

    /// Stops the weather and closes its overlays.
    func stop() {
        generation += 1
        geometry = []
        timer?.invalidate()
        timer = nil
        pace = 0
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        for observer in appObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        appObservers.removeAll()
        for display in displays.values {
            display.pickup?.close()
            display.panel.close()
        }
        displays.removeAll()
    }

    /// Sends a plough across each display.
    func sendPlough() {
        for display in displays.values { display.view.sendPlough() }
    }

    /// Applies a changed setting now instead of at the next upkeep.
    func applySettings() {
        lastUpkeep = 0
        tick()
    }

    private func setPace(_ interval: Double) {
        guard interval != pace, timer != nil || pace == 0 else { return }
        pace = interval
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        guard timer != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation
        let elapsed = min(0.5, max(0.001, now - lastTick))
        let velocity = CGVector(dx: (mouse.x - lastMouse.x) / elapsed, dy: (lastMouse.y - mouse.y) / elapsed)
        if mouse != lastMouse { lastMouseMove = now }
        lastTick = now
        lastMouse = mouse
        let held = NSEvent.pressedMouseButtons != 0
        if !held {
            dragStart = 0
            dragTarget = nil
            dragMovedWindow = false
            dragAnchor = nil
            dragGlides = false
        }
        var dragging = held && now - lastMouseMove < 0.4
        if dragging {
            if dragStart == 0 {
                dragStart = now
                dragTarget = window(under: mouse)
            }
            if let dragTarget, dragMovedWindow || now - dragStart < 0.35 {
                follow(dragTarget, mouse: mouse)
                if dragGlides, let anchor = dragAnchor {
                    place(dragTarget, at: anchor.rect.offsetBy(dx: mouse.x - anchor.mouse.x, dy: anchor.mouse.y - mouse.y), now: now)
                }
            } else {
                dragging = false
            }
        }
        if !(dragging && dragGlides) {
            scanWindows(now: now, minimumInterval: wasDragging && !dragging ? 0 : Self.surveyInterval)
        }
        wasDragging = dragging
        if now - lastUpkeep >= Self.idlePace * 0.9 {
            lastUpkeep = now
            upkeep(now: now)
        }
        applyGeometry(now: now)
        for screen in screens {
            guard let display = displays[screen.displayID], !display.view.isPaused else { continue }
            if !held {
                display.view.pointerMoved(to: CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y),
                                     velocity: velocity, elapsed: elapsed)
            }
            display.view.advance()
        }
        setPace(dragging ? (dragGlides ? Self.glidePace : Self.dragPace) : followsPointer ? Self.pointerPace : Self.idlePace)
    }

    private func applyGeometry(now: Double) {
        for screen in screens {
            guard let display = displays[screen.displayID], !display.view.isPaused,
                  display.geometryRevision != geometryRevision else { continue }
            display.geometryRevision = geometryRevision
            let surfaces = surfaces(on: screen)
            display.view.update(surfaces: surfaces, masks: surfaces.map(\.rect),
                                elapsed: display.lastGeometry == 0 ? 1 : now - display.lastGeometry)
            display.lastGeometry = now
        }
    }

    /// Slow-changing state: power source, and which displays are worth animating at all.
    private func upkeep(now: Double) {
        if now - lastPower > 5 {
            let powerSnapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
            let source = IOPSGetProvidingPowerSourceType(powerSnapshot)?.takeUnretainedValue()
            let onBattery = (source as String?) == kIOPSBatteryPowerValue
            powerFactor = onBattery || ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.5 : 1
            lastPower = now
        }
        for screen in screens {
            let frame = screen.quartzFrame
            let covered = geometry.contains {
                $0.layer == 0 && !$0.isStageManagerWindow && abs($0.rect.minX - frame.minX) <= 8 && abs($0.rect.minY - frame.minY) <= 8
                    && abs($0.rect.width - frame.width) <= 8 && abs($0.rect.height - frame.height) <= 8
            }
            let visible = !covered && CGDisplayIsAsleep(screen.displayID) == 0
            guard let display = displays[screen.displayID] else { continue }
            display.view.density = density * powerFactor
            display.view.timeScale = fallSpeed / 0.42
            if !visible { display.obscured = true }
            guard visible && isMotionEnabled else {
                display.view.isPaused = true
                if display.panel.isVisible { display.panel.orderOut(nil); display.pickup?.orderOut(nil) }
                continue
            }
            if !display.panel.isVisible {
                display.panel.orderFrontRegardless()
                display.pickup?.orderFrontRegardless()
            }
            if display.obscured {
                display.obscured = false
                display.view.restart(after: Self.returnDelay)
            }
            display.view.isPaused = false
        }
    }

    /// Includes windows whose top edge is offscreen: they still hide weather behind their contents.
    /// `WeatherPhysics` separately decides which top edges can catch particles.
    private func surfaces(on screen: NSScreen) -> [WeatherSurface] {
        let frame = screen.quartzFrame
        return geometry.compactMap { window -> WeatherSurface? in
            let localFrame = window.rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
            guard window.rect.intersects(frame) else { return nil }
            let nearEdge = localFrame.minX < 65 || localFrame.maxX > frame.width - 65
            let thumbnail = nearEdge && localFrame.width < min(235, frame.width * 0.23)
                && localFrame.height < frame.height * 0.52
            guard !window.isStageManagerWindow, !window.isDock, !thumbnail else { return nil }
            return WeatherSurface(id: window.id, rect: localFrame)
        }
    }

    private func window(under mouse: CGPoint) -> UInt32? {
        guard let height = NSScreen.screens.first?.frame.height else { return nil }
        let point = CGPoint(x: mouse.x, y: height - mouse.y)
        return geometry.first { $0.layer == 0 && !$0.isStageManagerWindow && $0.rect.insetBy(dx: -10, dy: -10).contains(point) }?.id
    }

    private func follow(_ id: UInt32, mouse: CGPoint) {
        guard !dragScanInProgress else { return }
        dragScanInProgress = true
        let requestedGeneration = generation
        windowQueue.async { [weak self] in
            let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first
            let rect = info.flatMap(Self.bounds(of:))?.rect
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dragScanInProgress = false
                guard self.generation == requestedGeneration, self.dragTarget == id, let rect else { return }
                if let anchor = self.dragAnchor, anchor.rect != rect {
                    self.dragMovedWindow = true
                    let drift = abs(rect.minX - anchor.rect.minX - (mouse.x - anchor.mouse.x))
                        + abs(rect.minY - anchor.rect.minY - (anchor.mouse.y - mouse.y))
                    self.dragGlides = rect.size == anchor.rect.size && drift < 4
                }
                self.dragAnchor = (rect, mouse)
                if !self.dragGlides { self.place(id, at: rect, now: ProcessInfo.processInfo.systemUptime) }
            }
        }
    }

    private func place(_ id: UInt32, at rect: CGRect, now: Double) {
        guard let index = geometry.firstIndex(where: { $0.id == id }), geometry[index].rect != rect else { return }
        let old = geometry[index]
        geometry[index] = WindowBounds(id: id, rect: rect, layer: old.layer, isDock: old.isDock, isStageManagerWindow: old.isStageManagerWindow)
        geometryRevision += 1
        applyGeometry(now: now)
    }

    /// Schedules a few extra looks at the windows over the next second.
    private func surveySoon() {
        let now = ProcessInfo.processInfo.systemUptime
        guard timer != nil, now >= nextFollowUp else { return }
        nextFollowUp = now + 0.5
        let scheduled = generation
        for delay in Self.followUpDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == scheduled, self.timer != nil else { return }
                self.scanWindows(now: ProcessInfo.processInfo.systemUptime, minimumInterval: 0.05)
            }
        }
    }

    private func scanWindows(now: Double, minimumInterval: Double) {
        guard !scanInProgress, now - lastScan >= minimumInterval else { return }
        lastScan = now
        scanInProgress = true
        let requestedGeneration = generation
        windowQueue.async { [weak self] in
            let result = Self.windowBounds()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanInProgress = false
                guard self.generation == requestedGeneration else { return }
                self.geometry = result
                self.geometryRevision += 1
                self.applyGeometry(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func makeSnowPickup(on screen: NSScreen, view: WeatherView) -> WeatherPanel {
        let frame = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 28)
        let panel = WeatherPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.white.withAlphaComponent(0.012)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let pickup = SnowPickupView(frame: CGRect(origin: .zero, size: frame.size))
        let local: (CGPoint) -> CGPoint = { CGPoint(x: $0.x - screen.frame.minX, y: screen.frame.maxY - $0.y) }
        pickup.onBegin = { [weak view] point in view?.beginRollingBall(at: local(point)) }
        pickup.onDrag = { [weak view] point in view?.rollBall(to: local(point)) }
        pickup.onRelease = { [weak view] point in view?.releaseBall(at: local(point)) }
        panel.contentView = pickup
        return panel
    }

    nonisolated private static func windowBounds() -> [WindowBounds] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap(bounds(of:))
    }

    nonisolated private static func bounds(of item: [String: Any]) -> WindowBounds? {
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        guard let layer = item[kCGWindowLayer as String] as? Int,
              let id = item[kCGWindowNumber as String] as? UInt32,
              let bounds = item[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
              w >= 70, h >= 28, (item[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0.2
        else { return nil }
        let owner = item[kCGWindowOwnerName as String] as? String
        let systemDock = owner == "Dock"
        let isStageManagerWindow = owner == "WindowManager"
            || (systemDock && w <= 300 && h >= 45 && h <= 350 && layer != dockLevel)
        let isDock = systemDock && layer == dockLevel
        guard isStageManagerWindow || isDock || (layer == 0 && !systemDock) else { return nil }
        return WindowBounds(id: id, rect: CGRect(x: x, y: y, width: w, height: h), layer: layer,
                            isDock: isDock, isStageManagerWindow: isStageManagerWindow)
    }
}
