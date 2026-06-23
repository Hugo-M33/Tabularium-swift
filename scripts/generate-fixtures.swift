import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

func hsv(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let i = floor(h * 6); let f = h * 6 - i
    let p = v * (1 - s); let q = v * (1 - f * s); let t = v * (1 - (1 - f) * s)
    switch Int(i) % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}

let W = 828, H = 1792
let dir = "/tmp/fixtures"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let count = 60

for i in 1...count {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    let (r, g, b) = hsv(Double(i - 1) / Double(count), 0.62, 0.92)
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 360, nil)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let attrs: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: white,
    ]
    let attr = NSAttributedString(string: "\(i)", attributes: attrs)
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (Double(W) - Double(bounds.width)) / 2 - Double(bounds.minX),
                               y: (Double(H) - Double(bounds.height)) / 2 - Double(bounds.minY))
    CTLineDraw(line, ctx)

    guard let img = ctx.makeImage() else { continue }
    let url = URL(fileURLWithPath: "\(dir)/fix_\(String(format: "%03d", i)).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}
print("generated \(count) numbered fixtures in \(dir)")
