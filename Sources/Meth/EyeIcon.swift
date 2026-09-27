import AppKit

enum EyeIcon {
    enum State { case off, caffeinate, meth }

    static func make(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 19), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: 1.5, y: 9.5))
            eye.curve(to: NSPoint(x: 19.5, y: 9.5), controlPoint1: NSPoint(x: 6, y: 18), controlPoint2: NSPoint(x: 15, y: 18))
            eye.curve(to: NSPoint(x: 1.5, y: 9.5), controlPoint1: NSPoint(x: 15, y: 1), controlPoint2: NSPoint(x: 6, y: 1))
            eye.lineWidth = 1.65
            eye.lineCapStyle = .round
            eye.lineJoinStyle = .round
            eye.stroke()

            let pupil = NSBezierPath(ovalIn: NSRect(x: 8.1, y: 5.2, width: 4.8, height: 8.6))
            if state == .off {
                pupil.lineWidth = 1.35
                pupil.stroke()
            } else {
                (state == .meth ? NSColor.systemRed : NSColor.labelColor).setFill()
                pupil.fill()
            }
            return true
        }
        image.isTemplate = state != .meth
        return image
    }
}
