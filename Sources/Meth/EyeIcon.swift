import AppKit

enum EyeIcon {
    enum State { case off, caffeinate, meth }

    static func make(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 19), flipped: false) { rect in
            let color = state == .meth ? NSColor.systemRed : NSColor.labelColor
            let ink = state == .meth ? NSColor.labelColor : color
            ink.setStroke()

            let upper = NSBezierPath()
            let lower = NSBezierPath()
            if state == .off {
                upper.move(to: NSPoint(x: 1.5, y: 8.8))
                upper.curve(to: NSPoint(x: 19.5, y: 8.8), controlPoint1: NSPoint(x: 7, y: 14.5), controlPoint2: NSPoint(x: 14, y: 14.5))
                lower.move(to: NSPoint(x: 1.5, y: 8.8))
                lower.curve(to: NSPoint(x: 19.5, y: 8.8), controlPoint1: NSPoint(x: 7, y: 4.4), controlPoint2: NSPoint(x: 14, y: 4.4))
            } else {
                upper.move(to: NSPoint(x: 1.5, y: 9.5))
                upper.curve(to: NSPoint(x: 19.5, y: 9.5), controlPoint1: NSPoint(x: 6.0, y: 19.0), controlPoint2: NSPoint(x: 15.0, y: 19.0))
                lower.move(to: NSPoint(x: 1.5, y: 9.5))
                lower.curve(to: NSPoint(x: 19.5, y: 9.5), controlPoint1: NSPoint(x: 6.0, y: 0.0), controlPoint2: NSPoint(x: 15.0, y: 0.0))
            }
            for path in [upper, lower] {
                path.lineWidth = 1.65
                path.lineCapStyle = .round
                path.stroke()
            }

            let irisRect = state == .off
                ? NSRect(x: 8.6, y: 6.1, width: 3.8, height: 5.0)
                : NSRect(x: 7.8, y: 5.1, width: 5.4, height: 8.8)
            let iris = NSBezierPath(ovalIn: irisRect)
            iris.lineWidth = 1.25
            iris.stroke()
            NSBezierPath(ovalIn: NSRect(x: 9.7, y: 8.15, width: 1.6, height: 2.4)).fill()

            if state == .meth {
                color.setStroke()
                let veins: [(NSPoint, NSPoint, NSPoint)] = [
                    (.init(x: 2.3, y: 9.5), .init(x: 5.5, y: 9.0), .init(x: 6.4, y: 11.1)),
                    (.init(x: 4.8, y: 15.4), .init(x: 7.2, y: 12.8), .init(x: 7.6, y: 11.7)),
                    (.init(x: 18.7, y: 9.5), .init(x: 15.5, y: 9.2), .init(x: 14.8, y: 11.0)),
                    (.init(x: 16.0, y: 3.8), .init(x: 14.7, y: 6.2), .init(x: 13.7, y: 7.0))
                ]
                for (start, bend, end) in veins {
                    let line = NSBezierPath()
                    line.move(to: start)
                    line.line(to: bend)
                    line.line(to: end)
                    line.lineWidth = 0.85
                    line.lineCapStyle = .round
                    line.lineJoinStyle = .round
                    line.stroke()
                }
            }
            return true
        }
        image.isTemplate = state != .meth
        return image
    }
}
