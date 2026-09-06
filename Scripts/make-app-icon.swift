#!/usr/bin/env swift
// Renders the app icon and launch glyph into DevinMobile/Assets.xcassets. macOS only (CoreGraphics + ImageIO).
//
//   swift Scripts/make-app-icon.swift
//
// The PNGs in the catalog are build artifacts of this file: change the mark or the palette here, re-run,
// commit both. `AppIcon` is a single-size (1024 pt) set — actool derives every device size from it —
// with iOS 18 dark and tinted variants; `LaunchGlyph` is the same mark at 96 pt (@2x/@3x) for
// `UILaunchScreen.UIImageName`.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

// Palette. `accent`/`accentDark` mirror AccentColor.colorset; keep them in sync by hand.
let accent = RGB(0x2F5BEA)
let accentDark = RGB(0x6F8FFF)
let navyTop = RGB(0x10193F)
let navyBottom = RGB(0x1B2E7A)
let inkTop = RGB(0x05070F)
let inkBottom = RGB(0x111A3A)
let white = RGB(0xFFFFFF)
let tintedCursor = RGB(0xB8B8B8)

enum Variant: String, CaseIterable {
    case light, dark, tinted
}

/// Draws the mark — a prompt chevron and a cursor block — into a `size`-pt square, in unit-space
/// coordinates scaled by `size` so every output shares one geometry.
func drawMark(_ ctx: CGContext, size: CGFloat, variant: Variant) {
    let s = size / 1024
    ctx.saveGState()
    ctx.scaleBy(x: s, y: s)

    switch variant {
    case .light:
        fillGradient(ctx, from: navyTop, to: navyBottom)
    case .dark:
        fillGradient(ctx, from: inkTop, to: inkBottom)
    case .tinted:
        break // transparent; the system supplies the background and tints the greys
    }

    // Chevron ">" — CoreGraphics is y-up, so the point is at mid-height.
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: 318, y: 736))
    chevron.addLine(to: CGPoint(x: 548, y: 512))
    chevron.addLine(to: CGPoint(x: 318, y: 288))
    ctx.setLineWidth(132)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(white.cg())
    ctx.addPath(chevron)
    ctx.strokePath()

    // Cursor block sits on the chevron's baseline.
    let cursor = CGRect(x: 606, y: 288 - 66, width: 172, height: 132)
    let cursorColor: RGB = switch variant {
    case .light: accentDark
    case .dark: accentDark
    case .tinted: tintedCursor
    }
    ctx.setFillColor(cursorColor.cg())
    ctx.addPath(CGPath(roundedRect: cursor, cornerWidth: 28, cornerHeight: 28, transform: nil))
    ctx.fillPath()

    ctx.restoreGState()
}

func fillGradient(_ ctx: CGContext, from top: RGB, to bottom: RGB) {
    let colors = [top.cg(), bottom.cg()] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return }
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
}

func makeContext(pixels: Int) -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext") }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("destination \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write \(url.path)") }
    print("wrote \(url.path)")
}

/// App Store icons must be opaque; strip alpha by compositing onto the (already opaque) gradient.
func icon(_ variant: Variant) -> CGImage {
    let ctx = makeContext(pixels: 1024)
    drawMark(ctx, size: 1024, variant: variant)
    guard let image = ctx.makeImage() else { fatalError("icon \(variant)") }
    if variant == .tinted { return image }
    let opaque = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaque.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return opaque.makeImage()!
}

/// The icon at `points` pt with an iOS-style rounded mask, so the launch screen shows the same tile as the home screen.
func launchGlyph(points: CGFloat, scale: CGFloat, variant: Variant) -> CGImage {
    let pixels = points * scale
    let ctx = makeContext(pixels: Int(pixels))
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pixels * 0.2237, cornerHeight: pixels * 0.2237, transform: nil))
    ctx.clip()
    drawMark(ctx, size: pixels, variant: variant)
    return ctx.makeImage()!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("DevinMobile/Assets.xcassets")
let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
let glyphSet = assets.appendingPathComponent("LaunchGlyph.imageset")

for variant in Variant.allCases {
    writePNG(icon(variant), to: iconSet.appendingPathComponent("AppIcon-\(variant.rawValue).png"))
}
for (variant, suffix) in [(Variant.light, ""), (.dark, "-dark")] {
    for scale in [2, 3] as [CGFloat] {
        writePNG(launchGlyph(points: 96, scale: scale, variant: variant),
                 to: glyphSet.appendingPathComponent("LaunchGlyph\(suffix)@\(Int(scale))x.png"))
    }
}
