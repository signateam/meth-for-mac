import AppKit

// Renders Meth's 1024x1024 app icon: a macOS-style squircle on the standard
// 824pt icon grid with a soft drop shadow, a deep plum gradient, and the eye
// mark (the 21x19 logo path) with a red pupil.

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
let cg = context.cgContext
let space = CGColorSpace(name: CGColorSpace.sRGB)!
cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha)
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: space,
        colors: stops.map { rgb($0.0, $0.1) } as CFArray,
        locations: stops.map { $0.2 })!
}

// Superellipse ("squircle") matching the macOS continuous-corner icon shape.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / n), c)
        let y = cy + b * copysign(pow(abs(s), 2 / n), s)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = squircle(in: tile)

// Drop shadow under the tile.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.32))
cg.addPath(tilePath)
cg.setFillColor(rgb(0x1a1322))
cg.fillPath()
cg.restoreGState()

// Tile body: vertical plum gradient plus a soft top glow.
cg.saveGState()
cg.addPath(tilePath)
cg.clip()
cg.drawLinearGradient(
    gradient([(0x3a2a4a, 1, 0), (0x21172c, 1, 0.55), (0x140e1b, 1, 1)]),
    start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
cg.drawRadialGradient(
    gradient([(0xe5322d, 0.20, 0), (0xe5322d, 0, 1)]),
    startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 500), endRadius: 420, options: [])
cg.restoreGState()

// Hairline inner edge: lighter at the top, for a glassy rim.
cg.saveGState()
cg.addPath(tilePath)
cg.clip()
cg.setLineWidth(6)
cg.addPath(tilePath)
cg.replacePathWithStrokedPath()
cg.clip()
cg.drawLinearGradient(
    gradient([(0xffffff, 0.22, 0), (0xffffff, 0.04, 0.5), (0x000000, 0.25, 1)]),
    start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
cg.restoreGState()

// Eye: logo path "M1.5 9.5C6 1 15 1 19.5 9.5C15 18 6 18 1.5 9.5Z" in a 21x19 box,
// scaled so the 18-unit width spans 600px, centered in the tile.
let scale: CGFloat = 600 / 18
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    // SVG y grows downward; flip around the eye's midline (9.5).
    CGPoint(x: 512 + (x - 10.5) * scale, y: 512 - (y - 9.5) * scale)
}
let eye = CGMutablePath()
eye.move(to: p(1.5, 9.5))
eye.addCurve(to: p(19.5, 9.5), control1: p(6, 1), control2: p(15, 1))
eye.addCurve(to: p(1.5, 9.5), control1: p(15, 18), control2: p(6, 18))
eye.closeSubpath()

// Eye white with a shadow onto the tile.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.45))
cg.addPath(eye)
cg.setFillColor(rgb(0xf6f2ee))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(eye)
cg.clip()
cg.drawLinearGradient(
    gradient([(0xffffff, 1, 0), (0xf3eee9, 1, 0.6), (0xd9d1cc, 1, 1)]),
    start: p(10.5, 3), end: p(10.5, 16), options: [])
// Inner shade under the upper lid.
cg.setLineWidth(40)
cg.addPath(eye)
cg.setStrokeColor(rgb(0x6b5a73, 0.16))
cg.strokePath()

// Pupil: ellipse cx 10.5 cy 9.5 rx 2.4 ry 4.3, brand red with depth.
let pupilRect = CGRect(x: 512 - 2.4 * scale, y: 512 - 4.3 * scale, width: 4.8 * scale, height: 8.6 * scale)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: rgb(0x5a0a0a, 0.45))
cg.addEllipse(in: pupilRect)
cg.setFillColor(rgb(0xe5322d))
cg.fillPath()
cg.restoreGState()
cg.saveGState()
cg.addEllipse(in: pupilRect)
cg.clip()
cg.drawLinearGradient(
    gradient([(0xff5a4e, 1, 0), (0xe5322d, 1, 0.5), (0xa81c1a, 1, 1)]),
    start: CGPoint(x: 512, y: pupilRect.maxY), end: CGPoint(x: 512, y: pupilRect.minY), options: [])
cg.restoreGState()
// Catchlight.
cg.addEllipse(in: CGRect(x: 512 - 34, y: 512 + 38, width: 30, height: 50))
cg.setFillColor(rgb(0xffffff, 0.85))
cg.fillPath()
cg.restoreGState()

// Dark lid outline.
cg.saveGState()
cg.addPath(eye)
cg.setLineWidth(30)
cg.setLineJoin(.round)
cg.setStrokeColor(rgb(0x120c18))
cg.strokePath()
cg.restoreGState()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
try data.write(to: URL(fileURLWithPath: output))
