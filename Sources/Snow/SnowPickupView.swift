import AppKit

/// A strip along the bottom of the screen where a drag picks up snow to roll into a ball.
@MainActor
final class SnowPickupView: NSView {
    /// Called with the pointer's screen position when a drag starts.
    var onBegin: ((_ screenPosition: CGPoint) -> Void)?
    /// Called with the pointer's screen position as the drag moves.
    var onDrag: ((_ screenPosition: CGPoint) -> Void)?
    /// Called with the pointer's screen position when the drag ends.
    var onRelease: ((_ screenPosition: CGPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onBegin?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onRelease?(NSEvent.mouseLocation) }
}
