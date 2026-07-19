import AppKit
import CoreGraphics
import Foundation

// Generates Sources/Macscout/Resources/AppIcon.icns (docs/DESIGN.md — Icon):
// dark (#050507) rounded square, a centered black notch-pill, and inside it a
// pixel-art blood drop (#E8483F blocks) with a white pixel glucose trace.
//
// Run: swift scripts/make-icon.swift

let size: CGFloat = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let workDir = root.appendingPathComponent(".build/icon-work")
let iconset = workDir.appendingPathComponent("icon.iconset")
let output = root.appendingPathComponent("Sources/Macscout/Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: workDir)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// MARK: - Pixel art (R = drop, W = glucose trace, . = empty)

// 11×16 blood drop with the trace overlaid on its middle rows.
let art: [String] = [
    ".....R.....",
    "....RRR....",
    "....RRR....",
    "...RRRRR...",
    "...RRRRR...",
    "..RRRRRRR..",
    "..RRRRRRR..",
    ".RRRRRRRRR.",
    ".RRRWRRRRR.",
    ".WWW.W.WWW.",
    "RRRRRWRRRRR",
    "RRRRRRRRRRR",
    ".RRRRRRRRR.",
    "..RRRRRRR..",
    "...RRRRR...",
    "....RRR....",
]
let artRows = art.count
let artCols = art[0].count

guard let context = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create graphics context")
}

// MARK: Background — dark rounded square (#050507)
context.setFillColor(CGColor(red: 0x05 / 255, green: 0x05 / 255, blue: 0x07 / 255, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                       cornerWidth: 224, cornerHeight: 224, transform: nil))
context.fillPath()

// MARK: Pill — black, notch-shaped (bottom corners deeply rounded)
let pillRect = CGRect(x: 232, y: 372, width: 560, height: 280)
let topR: CGFloat = 20
let bottomR: CGFloat = 84
let pill = CGMutablePath()
pill.move(to: CGPoint(x: pillRect.minX + topR, y: pillRect.maxY))
pill.addArc(tangent1End: CGPoint(x: pillRect.minX, y: pillRect.maxY),
            tangent2End: CGPoint(x: pillRect.minX, y: pillRect.maxY - topR), radius: topR)
pill.addLine(to: CGPoint(x: pillRect.minX, y: pillRect.minY + bottomR))
pill.addArc(tangent1End: CGPoint(x: pillRect.minX, y: pillRect.minY),
            tangent2End: CGPoint(x: pillRect.minX + bottomR, y: pillRect.minY), radius: bottomR)
pill.addLine(to: CGPoint(x: pillRect.maxX - bottomR, y: pillRect.minY))
pill.addArc(tangent1End: CGPoint(x: pillRect.maxX, y: pillRect.minY),
            tangent2End: CGPoint(x: pillRect.maxX, y: pillRect.minY + bottomR), radius: bottomR)
pill.addLine(to: CGPoint(x: pillRect.maxX, y: pillRect.maxY - topR))
pill.addArc(tangent1End: CGPoint(x: pillRect.maxX, y: pillRect.maxY),
            tangent2End: CGPoint(x: pillRect.maxX - topR, y: pillRect.maxY), radius: topR)
pill.closeSubpath()
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.addPath(pill)
context.fillPath()
// Hairline stroke (white 8%).
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
context.setLineWidth(2)
context.addPath(pill)
context.strokePath()

// MARK: Pixel art inside the pill (crisp blocks, no antialiasing)
let cell = floor(min(pillRect.width * 0.60 / CGFloat(artCols),
                     pillRect.height * 0.92 / CGFloat(artRows)))
let artWidth = cell * CGFloat(artCols)
let artHeight = cell * CGFloat(artRows)
let artOrigin = CGPoint(x: pillRect.midX - artWidth / 2,
                        y: pillRect.midY - artHeight / 2)

let red = CGColor(red: 0xE8 / 255, green: 0x48 / 255, blue: 0x3F / 255, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
context.setAllowsAntialiasing(false)
for (row, line) in art.enumerated() {
    for (col, ch) in line.enumerated() {
        let color: CGColor?
        switch ch {
        case "R": color = red
        case "W": color = white
        default: color = nil
        }
        if let color {
            context.setFillColor(color)
            // CG y-axis is bottom-up: flip row order.
            let rect = CGRect(x: artOrigin.x + CGFloat(col) * cell,
                              y: artOrigin.y + CGFloat(artRows - 1 - row) * cell,
                              width: cell, height: cell)
            context.fill(rect)
        }
    }
}
context.setAllowsAntialiasing(true)

guard let image = context.makeImage() else {
    fatalError("could not render icon")
}

let png1024 = workDir.appendingPathComponent("icon-1024.png")
guard let destination = CGImageDestinationCreateWithURL(
    png1024 as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("could not create image destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("could not write \(png1024.path)")
}

// MARK: - iconset via sips, icns via iconutil

func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("\(launchPath) \(arguments) failed with \(process.terminationStatus)")
    }
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for entry in sizes {
    let dest = iconset.appendingPathComponent(entry.name)
    try run("/usr/bin/sips", ["-z", "\(entry.pixels)", "\(entry.pixels)",
                              png1024.path, "--out", dest.path])
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path])

print("Wrote \(output.path)")
