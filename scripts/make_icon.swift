#!/usr/bin/env swift
//
// Generates Resources/AppIcon.icns.
//
// The icon is drawn in code rather than committed as an opaque binary so it can
// be reviewed, tweaked, and regenerated in a diff like everything else.
//
// The glyph is custom-drawn on purpose: SF Symbols are licensed for use *in* an
// interface, not as an application icon, so the menu bar can use `link` but this
// cannot.
//
// Usage:  swift scripts/make_icon.swift
//
import AppKit

// MARK: - Geometry

/// The rounded square covers ~81% of the canvas, with the margin carrying its
/// drop shadow.
///
/// Not a guess: measuring the opaque bounds of Slack's and Firefox's icns files
/// gives 832/1024 and 834/1024 — both 81%. Filling the canvas instead (100%)
/// renders visibly wrong next to them, and an inset plate *without* a shadow
/// reads as a small tile floating in space, because the margin then looks like
/// empty padding rather than the room the shadow needs.
let canvas: CGFloat = 1024
let plateInset: CGFloat = 96
let plateRect = CGRect(
    x: plateInset, y: plateInset,
    width: canvas - plateInset * 2, height: canvas - plateInset * 2
)
let cornerRadius: CGFloat = 186

/// One half of the chain link: a capsule outline.
let linkSize = CGSize(width: 424, height: 208)
let linkStroke: CGFloat = 46
/// Distance between the two capsule centres, measured along their shared long
/// axis. Kept large enough that the links meet only across their curved end
/// caps: both capsules share a centre line and a height, so any overlap of their
/// *straight* edges makes the two silhouettes fuse into one long pill instead of
/// reading as a chain.
let linkSeparation: CGFloat = 350
/// Width of the gap knocked out of the under-link so the two read as interlocked
/// rather than as one flat squiggle. Below ~20 it disappears at small sizes.
let interlockGap: CGFloat = 17

func capsulePath(center: CGPoint) -> NSBezierPath {
    let rect = CGRect(
        x: center.x - linkSize.width / 2,
        y: center.y - linkSize.height / 2,
        width: linkSize.width,
        height: linkSize.height
    )
    return NSBezierPath(roundedRect: rect, xRadius: linkSize.height / 2, yRadius: linkSize.height / 2)
}

// MARK: - Drawing

func drawIcon(into rep: NSBitmapImageRep) {
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    cg.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    // Plate: indigo→blue, lighter at the top like a surface lit from above.
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // The shadow is what makes the inset read as depth rather than as padding.
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 26
    shadow.set()
    NSColor.black.setFill()
    plate.fill()
    cg.restoreGState()

    cg.saveGState()
    plate.addClip()
    let gradient = NSGradient(
        colors: [
            NSColor(srgbRed: 0.35, green: 0.53, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.24, green: 0.28, blue: 0.85, alpha: 1),
        ]
    )
    gradient?.draw(in: plateRect, angle: -90)
    cg.restoreGState()

    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    cg.saveGState()
    // Rotate the whole glyph 45° about the centre. Everything below is drawn in
    // that rotated frame, where the capsules' long axis is simply horizontal —
    // so offsetting them is a matter of moving along x, not doing diagonal
    // trigonometry by hand.
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: -.pi / 4)
    cg.translateBy(x: -center.x, y: -center.y)

    let under = CGPoint(x: center.x + linkSeparation / 2, y: center.y)
    let over = CGPoint(x: center.x - linkSeparation / 2, y: center.y)

    let underPath = capsulePath(center: under)
    let overPath = capsulePath(center: over)

    underPath.lineWidth = linkStroke
    NSColor.white.setStroke()
    underPath.stroke()

    // Knock a gap out of the under-link wherever the over-link crosses it, then
    // draw the over-link into that gap. This is what sells the interlock.
    cg.saveGState()
    cg.setBlendMode(.clear)
    overPath.lineWidth = linkStroke + interlockGap * 2
    overPath.stroke()
    cg.restoreGState()

    overPath.lineWidth = linkStroke
    NSColor.white.setStroke()
    overPath.stroke()

    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Output

func render(size: CGFloat) -> NSBitmapImageRep {
    let full = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    drawIcon(into: full)
    guard size != canvas else { return full }

    // Draw the master down rather than redrawing at size: the stroke weights are
    // tuned for 1024 and scaling keeps them proportional at every step.
    let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current?.imageInterpolation = .high
    full.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return scaled
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// The set iconutil expects; each logical size at 1x and 2x.
let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    let rep = render(size: px)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconset.appendingPathComponent("\(name).png"))
}

// A standalone preview for the README.
if let png = render(size: 512).representation(using: .png, properties: [:]) {
    try png.write(to: root.appendingPathComponent("docs/icon-preview.png"))
}

// Also emit an asset catalog.
//
// Shipping only an .icns gets the icon containerized by macOS 26 — drawn shrunk
// inside a grey system plate. Apps that render natively (Firefox, for one)
// declare CFBundleIconName and ship a compiled Assets.car as well; macOS prefers
// that over the .icns. scripts/make_app.sh compiles this with actool.
let appiconset = root.appendingPathComponent("build/Assets.xcassets/AppIcon.appiconset")
try? fm.removeItem(at: root.appendingPathComponent("build/Assets.xcassets"))
try fm.createDirectory(at: appiconset, withIntermediateDirectories: true)

for (name, _) in sizes {
    try fm.copyItem(
        at: iconset.appendingPathComponent("\(name).png"),
        to: appiconset.appendingPathComponent("\(name).png")
    )
}

/// `icon_16x16@2x` is the 2x variant of the 16pt slot, and so on — the catalog
/// wants the logical point size plus a scale, not the pixel count.
let entries = sizes.map { name, _ -> String in
    let base = name.replacingOccurrences(of: "@2x", with: "")
    let points = base.replacingOccurrences(of: "icon_", with: "")
    let scale = name.hasSuffix("@2x") ? "2x" : "1x"
    return """
        {"idiom":"mac","size":"\(points)","scale":"\(scale)","filename":"\(name).png"}
    """
}
let contents = """
{"images":[\(entries.joined(separator: ","))],"info":{"author":"linkpaste","version":1}}
"""
try contents.write(to: appiconset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\"info\":{\"author\":\"linkpaste\",\"version\":1}}"
    .write(to: root.appendingPathComponent("build/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path,
    "-o", root.appendingPathComponent("Resources/AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

print("Wrote Resources/AppIcon.icns and docs/icon-preview.png")
