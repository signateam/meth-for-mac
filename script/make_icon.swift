import AppKit

let output = CommandLine.arguments[1]
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
bounds.fill()

let background = NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 222, yRadius: 222)
NSColor(calibratedRed: 0.10, green: 0.075, blue: 0.14, alpha: 1).setFill()
background.fill()

let eye = NSBezierPath()
eye.move(to: NSPoint(x: 125, y: 512))
eye.curve(to: NSPoint(x: 899, y: 512), controlPoint1: NSPoint(x: 308, y: 832), controlPoint2: NSPoint(x: 714, y: 832))
eye.curve(to: NSPoint(x: 125, y: 512), controlPoint1: NSPoint(x: 714, y: 192), controlPoint2: NSPoint(x: 308, y: 192))
eye.close()
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
eye.fill()
NSColor(calibratedRed: 0.91, green: 0.88, blue: 0.91, alpha: 1).setStroke()
eye.lineWidth = 12
eye.stroke()

let pupil = NSBezierPath(ovalIn: NSRect(x: 436, y: 374, width: 152, height: 276))
NSColor(calibratedRed: 0.87, green: 0.15, blue: 0.22, alpha: 1).setFill()
pupil.fill()

let outline = NSBezierPath()
outline.move(to: NSPoint(x: 125, y: 512))
outline.curve(to: NSPoint(x: 899, y: 512), controlPoint1: NSPoint(x: 308, y: 832), controlPoint2: NSPoint(x: 714, y: 832))
outline.curve(to: NSPoint(x: 125, y: 512), controlPoint1: NSPoint(x: 714, y: 192), controlPoint2: NSPoint(x: 308, y: 192))
outline.close()
outline.lineWidth = 38
outline.lineJoinStyle = .round
NSColor(calibratedRed: 0.13, green: 0.08, blue: 0.16, alpha: 1).setStroke()
outline.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
try data.write(to: URL(fileURLWithPath: output))
