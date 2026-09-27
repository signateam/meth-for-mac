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

let iris = NSBezierPath(ovalIn: NSRect(x: 368, y: 334, width: 288, height: 356))
NSColor(calibratedRed: 0.68, green: 0.10, blue: 0.18, alpha: 1).setFill()
iris.fill()
let irisInner = NSBezierPath(ovalIn: NSRect(x: 424, y: 390, width: 176, height: 244))
NSColor(calibratedRed: 0.91, green: 0.30, blue: 0.34, alpha: 1).setFill()
irisInner.fill()
let pupil = NSBezierPath(ovalIn: NSRect(x: 473, y: 405, width: 78, height: 212))
NSColor(calibratedRed: 0.12, green: 0.07, blue: 0.15, alpha: 1).setFill()
pupil.fill()
NSColor(calibratedWhite: 1, alpha: 0.95).setFill()
NSBezierPath(ovalIn: NSRect(x: 447, y: 575, width: 46, height: 64)).fill()

NSColor(calibratedRed: 0.78, green: 0.14, blue: 0.20, alpha: 0.9).setStroke()
let veins: [[NSPoint]] = [
    [.init(x: 149, y: 512), .init(x: 266, y: 497), .init(x: 336, y: 550)],
    [.init(x: 217, y: 640), .init(x: 305, y: 579), .init(x: 365, y: 565)],
    [.init(x: 258, y: 372), .init(x: 318, y: 452), .init(x: 366, y: 463)],
    [.init(x: 874, y: 512), .init(x: 754, y: 489), .init(x: 676, y: 543)],
    [.init(x: 801, y: 633), .init(x: 717, y: 565), .init(x: 653, y: 568)],
    [.init(x: 771, y: 363), .init(x: 708, y: 447), .init(x: 658, y: 460)]
]
for points in veins {
    let path = NSBezierPath()
    path.move(to: points[0])
    path.line(to: points[1])
    path.line(to: points[2])
    path.lineWidth = 12
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

let outline = NSBezierPath()
outline.move(to: NSPoint(x: 125, y: 512))
outline.curve(to: NSPoint(x: 899, y: 512), controlPoint1: NSPoint(x: 308, y: 832), controlPoint2: NSPoint(x: 714, y: 832))
outline.curve(to: NSPoint(x: 125, y: 512), controlPoint1: NSPoint(x: 714, y: 192), controlPoint2: NSPoint(x: 308, y: 192))
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
