#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-icns-path> [optional-preview-png-path]\n", stderr)
    exit(1)
}

let icnsURL = URL(fileURLWithPath: CommandLine.arguments[1])
let previewURL = CommandLine.arguments.count >= 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, alpha])!
}

func renderIcon(pixelSize: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let ctx = nsCtx.cgContext
    let s = CGFloat(pixelSize)

    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let sx = s / 100.0
    let sy = s / 100.0
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * sx, y: y * sy)
    }

    let inkBlack = color(0x121417)
    let slateBlue = color(0x263B63)
    let skyBlue = color(0x72B2D4)
    let creamPaper = color(0xF2EAD9)
    let vermilion = color(0xCF4636)
    let warmOchre = color(0xD9A74A)

    let bgRect = CGRect(x: 7 * sx, y: 7 * sy, width: 86 * sx, height: 86 * sy)
    let squircle = CGPath(roundedRect: bgRect, cornerWidth: 19 * sx, cornerHeight: 19 * sy, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    ctx.setFillColor(inkBlack)
    ctx.fill(bgRect)

    ctx.beginPath()
    ctx.move(to: pt(0, 0))
    ctx.addLine(to: pt(65, 0))
    ctx.addLine(to: pt(34, 100))
    ctx.addLine(to: pt(0, 100))
    ctx.closePath()
    ctx.setFillColor(slateBlue)
    ctx.fillPath()

    ctx.beginPath()
    ctx.move(to: pt(75, 0))
    ctx.addLine(to: pt(100, 0))
    ctx.addLine(to: pt(100, 100))
    ctx.addLine(to: pt(65, 100))
    ctx.closePath()
    ctx.setFillColor(color(0xF2EAD9, alpha: 0.92))
    ctx.fillPath()

    for stripeX in [79.0, 83.2, 87.4] {
        ctx.beginPath()
        ctx.move(to: pt(stripeX, 0))
        ctx.addLine(to: pt(stripeX + 1.5, 0))
        ctx.addLine(to: pt(stripeX - 9.0, 100))
        ctx.addLine(to: pt(stripeX - 10.5, 100))
        ctx.closePath()
        ctx.setFillColor(vermilion)
        ctx.fillPath()
    }

    let steppedFrame = CGMutablePath()
    let m1: CGFloat = 13.5
    let m2: CGFloat = 19.5
    let m3: CGFloat = 25.5
    steppedFrame.move(to: pt(m3, m1))
    steppedFrame.addLine(to: pt(100 - m3, m1))
    steppedFrame.addLine(to: pt(100 - m3, m2))
    steppedFrame.addLine(to: pt(100 - m2, m2))
    steppedFrame.addLine(to: pt(100 - m2, m3))
    steppedFrame.addLine(to: pt(100 - m1, m3))
    steppedFrame.addLine(to: pt(100 - m1, 100 - m3))
    steppedFrame.addLine(to: pt(100 - m2, 100 - m3))
    steppedFrame.addLine(to: pt(100 - m2, 100 - m2))
    steppedFrame.addLine(to: pt(100 - m3, 100 - m2))
    steppedFrame.addLine(to: pt(100 - m3, 100 - m1))
    steppedFrame.addLine(to: pt(m3, 100 - m1))
    steppedFrame.addLine(to: pt(m3, 100 - m2))
    steppedFrame.addLine(to: pt(m2, 100 - m2))
    steppedFrame.addLine(to: pt(m2, 100 - m3))
    steppedFrame.addLine(to: pt(m1, 100 - m3))
    steppedFrame.addLine(to: pt(m1, m3))
    steppedFrame.addLine(to: pt(m2, m3))
    steppedFrame.addLine(to: pt(m2, m2))
    steppedFrame.addLine(to: pt(m3, m2))
    steppedFrame.closeSubpath()

    ctx.addPath(steppedFrame)
    ctx.setStrokeColor(inkBlack)
    ctx.setLineWidth(3.2 * sx)
    ctx.strokePath()

    ctx.addPath(steppedFrame)
    ctx.setStrokeColor(creamPaper)
    ctx.setLineWidth(1.5 * sx)
    ctx.strokePath()

    let pad: CGFloat = 0.62
    let offset: CGFloat = (100.0 - 100.0 * pad) / 2.0
    func ept(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        pt(offset + x * pad, offset + y * pad)
    }

    func fillPoly(_ points: [(CGFloat, CGFloat)], fill: CGColor) {
        ctx.beginPath()
        ctx.move(to: ept(points[0].0, points[0].1))
        for p in points.dropFirst() {
            ctx.addLine(to: ept(p.0, p.1))
        }
        ctx.closePath()
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    for i in 0..<3 {
        let y = 55.0 + CGFloat(i) * 8.0
        let leftOuter = 2.0 + CGFloat(i) * 5.0
        let rightOuter = 98.0 - CGFloat(i) * 5.0
        let barH: CGFloat = 4.5

        fillPoly(
            [(leftOuter, y), (34, y), (32, y + barH), (leftOuter + 3.2, y + barH)],
            fill: i == 0 ? skyBlue : (i == 1 ? creamPaper : warmOchre)
        )
        fillPoly(
            [(66, y), (rightOuter, y), (rightOuter - 3.2, y + barH), (68, y + barH)],
            fill: i == 0 ? vermilion : (i == 1 ? inkBlack : warmOchre)
        )
    }

    fillPoly([(28, 71), (72, 71), (72, 77.5), (28, 77.5)], fill: warmOchre)
    fillPoly([(50, 5), (15, 89), (34, 89), (50, 44)], fill: creamPaper)
    fillPoly([(50, 5), (85, 89), (66, 89), (50, 44)], fill: vermilion)
    fillPoly([(48.5, 20), (22.5, 84), (25.5, 84), (48.5, 27.5)], fill: inkBlack)
    fillPoly([(50, 51), (57, 61.5), (50, 68.5), (43, 61.5)], fill: skyBlue)
    fillPoly([(15, 92.5), (85, 92.5), (85, 96.5), (15, 96.5)], fill: creamPaper)

    ctx.restoreGState()

    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xF2EAD9, alpha: 0.35))
    ctx.setLineWidth(1.5 * sx)
    ctx.strokePath()

    return rep.representation(using: .png, properties: [:])
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var big = value.bigEndian
    withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
}

let icnsEntries: [(String, Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512)
]

var renderedBySize: [Int: Data] = [:]
for size in Set(icnsEntries.map(\.1)) {
    if let png = renderIcon(pixelSize: size) {
        renderedBySize[size] = png
    }
}

if let previewURL, let png512 = renderedBySize[512] {
    try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png512.write(to: previewURL)
}

var body = Data()
for (fourCC, size) in icnsEntries {
    guard let png = renderedBySize[size] else { continue }
    body.append(contentsOf: fourCC.utf8.prefix(4))
    appendUInt32BE(UInt32(8 + png.count), to: &body)
    body.append(png)
}

var icns = Data()
icns.append(contentsOf: "icns".utf8)
appendUInt32BE(UInt32(8 + body.count), to: &icns)
icns.append(body)

try FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try icns.write(to: icnsURL)
