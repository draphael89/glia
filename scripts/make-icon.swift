// Generates the AppIcon masters: a detailed 1024 constellation for large
// sizes, and a simplified 256 variant for small sizes (a 7-star icon
// downsampled to 16px is mush — HIG says simplify, not shrink).
// Run: swift scripts/make-icon.swift [simple]
import AppKit
import CoreGraphics

let simple = CommandLine.arguments.contains("simple")
let size = simple ? 256 : 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let S = CGFloat(size)

// macOS icon shape: full-bleed rounded rect (squircle-ish)
let inset: CGFloat = S * 0.086
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: S * 0.19, cornerHeight: S * 0.19, transform: nil)
ctx.addPath(path)
ctx.clip()

// deep space background with center bloom
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.075, green: 0.086, blue: 0.13, alpha: 1),
    CGColor(red: 0.024, green: 0.027, blue: 0.045, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bg, startCenter: CGPoint(x: S * 0.46, y: S * 0.58), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.5, y: S * 0.5), endRadius: S * 0.75, options: [])
let bloom = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.30, green: 0.24, blue: 0.55, alpha: 0.55),
    CGColor(red: 0.30, green: 0.24, blue: 0.55, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: S * 0.47, y: S * 0.56), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.47, y: S * 0.56), endRadius: S * 0.52, options: [])

// constellation: hub + satellites
struct Star { let p: CGPoint; let r: CGFloat; let c: (CGFloat, CGFloat, CGFloat) }
let violet: (CGFloat, CGFloat, CGFloat) = (0.486, 0.361, 1.0)
let green: (CGFloat, CGFloat, CGFloat) = (0.32, 0.84, 0.54)
let rose: (CGFloat, CGFloat, CGFloat) = (0.88, 0.35, 0.45)
let gold: (CGFloat, CGFloat, CGFloat) = (0.90, 0.78, 0.31)
let teal: (CGFloat, CGFloat, CGFloat) = (0.31, 0.76, 0.76)

let stars: [Star] = simple
    ? [ // small sizes: hub + three satellites, larger and bolder
        Star(p: CGPoint(x: S * 0.46, y: S * 0.54), r: S * 0.150, c: violet),
        Star(p: CGPoint(x: S * 0.24, y: S * 0.72), r: S * 0.085, c: green),
        Star(p: CGPoint(x: S * 0.72, y: S * 0.70), r: S * 0.075, c: rose),
        Star(p: CGPoint(x: S * 0.62, y: S * 0.28), r: S * 0.090, c: teal),
      ]
    : [
        Star(p: CGPoint(x: S * 0.47, y: S * 0.56), r: S * 0.088, c: violet),   // hub
        Star(p: CGPoint(x: S * 0.27, y: S * 0.70), r: S * 0.052, c: green),
        Star(p: CGPoint(x: S * 0.70, y: S * 0.71), r: S * 0.044, c: rose),
        Star(p: CGPoint(x: S * 0.31, y: S * 0.36), r: S * 0.040, c: gold),
        Star(p: CGPoint(x: S * 0.66, y: S * 0.33), r: S * 0.056, c: teal),
        Star(p: CGPoint(x: S * 0.80, y: S * 0.52), r: S * 0.028, c: green),
        Star(p: CGPoint(x: S * 0.19, y: S * 0.53), r: S * 0.026, c: rose),
      ]

// edges
ctx.setLineWidth(S * (simple ? 0.030 : 0.012))
ctx.setStrokeColor(CGColor(red: 0.62, green: 0.65, blue: 0.80, alpha: 0.42))
for i in 1..<stars.count {
    ctx.move(to: stars[0].p)
    ctx.addLine(to: stars[i].p)
}
ctx.strokePath()
if !simple {
    ctx.setLineWidth(S * 0.008)
    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.65, blue: 0.80, alpha: 0.22))
    ctx.move(to: stars[1].p); ctx.addLine(to: stars[6].p)
    ctx.move(to: stars[3].p); ctx.addLine(to: stars[4].p)
    ctx.move(to: stars[4].p); ctx.addLine(to: stars[5].p)
    ctx.strokePath()
}

// stars with glow
for s in stars {
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: s.c.0, green: s.c.1, blue: s.c.2, alpha: 0.42),
        CGColor(red: s.c.0, green: s.c.1, blue: s.c.2, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: s.p, startRadius: s.r * 0.7,
                           endCenter: s.p, endRadius: s.r * 1.9, options: [])
    // body
    let body = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: min(s.c.0 * 1.25, 1), green: min(s.c.1 * 1.25, 1), blue: min(s.c.2 * 1.25, 1), alpha: 1),
        CGColor(red: s.c.0 * 0.82, green: s.c.1 * 0.82, blue: s.c.2 * 0.82, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: s.p.x - s.r, y: s.p.y - s.r, width: s.r * 2, height: s.r * 2))
    ctx.clip()
    ctx.drawRadialGradient(body, startCenter: CGPoint(x: s.p.x - s.r * 0.3, y: s.p.y + s.r * 0.35),
                           startRadius: 0, endCenter: s.p, endRadius: s.r * 1.4, options: [])
    ctx.restoreGState()
    // rim
    ctx.setLineWidth(s.r * 0.14)
    ctx.setStrokeColor(CGColor(red: min(s.c.0 * 1.4, 1), green: min(s.c.1 * 1.4, 1), blue: min(s.c.2 * 1.4, 1), alpha: 0.75))
    ctx.strokeEllipse(in: CGRect(x: s.p.x - s.r * 0.93, y: s.p.y - s.r * 0.93, width: s.r * 1.86, height: s.r * 1.86))
}

let img = ctx.makeImage()!
let name = simple ? "AppIconSimple256.png" : "AppIcon1024.png"
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: "Glia/Resources/\(simple ? "IconMasters/" : "Assets.xcassets/AppIcon.appiconset/")\(name)") as CFURL,
    "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("\(name) written")
