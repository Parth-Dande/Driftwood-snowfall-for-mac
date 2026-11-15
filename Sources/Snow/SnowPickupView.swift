import AppKit

@MainActor
final class SnowPickupView: NSView {
    var onBegin: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: ((CGPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onBegin?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onRelease?(NSEvent.mouseLocation) }
}
