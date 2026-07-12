#!/usr/bin/env swift

import AppKit
import Foundation

private struct OGPVariant {
    let outputName: String
    let screenshotName: String
    let fontName: String
    let headline: String
    let subheadline: String
}

private let variants = [
    OGPVariant(
        outputName: "ja.png",
        screenshotName: "overcue-ja.png",
        fontName: "Hiragino Sans W6",
        headline: "ACK05を\nCUE仕込みデバイスへ",
        subheadline: "片手だけで、快適なCUE打ちを。"
    ),
    OGPVariant(
        outputName: "en.png",
        screenshotName: "overcue-en.png",
        fontName: "Helvetica Neue Bold",
        headline: "Turn ACK05 into a\nCUE Prep Controller",
        subheadline: "One-handed cue preparation for rekordbox."
    ),
    OGPVariant(
        outputName: "zh-CN.png",
        screenshotName: "overcue-zh-Hans.png",
        fontName: "PingFang SC Semibold",
        headline: "将 ACK05 变成\nCUE 设置控制器",
        subheadline: "单手轻松完成 rekordbox CUE 设置。"
    ),
]

private let canvasSize = NSSize(width: 1200, height: 630)
private let rootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let imageDirectory = rootURL.appendingPathComponent("docs/assets/images")
private let outputDirectory = rootURL.appendingPathComponent("docs/assets/ogp")

private func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasSize.height - y - height, width: width, height: height)
}

private func font(named name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    lineHeight: CGFloat? = nil
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    ).draw(in: rect)
}

private func drawRoundedImage(_ image: NSImage, in rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.2).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    border.lineWidth = 2
    border.stroke()
}

private func generate(_ variant: OGPVariant, icon: NSImage) throws {
    guard let screenshot = NSImage(
        contentsOf: imageDirectory.appendingPathComponent(variant.screenshotName)
    ) else {
        throw NSError(domain: "OverCUEOGP", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Missing screenshot: \(variant.screenshotName)",
        ])
    }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "OverCUEOGP", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Could not create bitmap context.",
        ])
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvas = NSRect(origin: .zero, size: canvasSize)
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.015, green: 0.018, blue: 0.025, alpha: 1),
            NSColor(calibratedRed: 0.025, green: 0.08, blue: 0.18, alpha: 1),
        ]
    )!.draw(in: canvas, angle: 0)

    NSColor(calibratedRed: 0.08, green: 0.35, blue: 0.85, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: 840, y: 180, width: 520, height: 520)).fill()
    NSColor(calibratedRed: 0.1, green: 0.48, blue: 1, alpha: 0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: -170, y: -240, width: 560, height: 560)).fill()

    drawRoundedImage(icon, in: topRect(x: 68, y: 54, width: 92, height: 92), radius: 20)
    drawText(
        "OverCUE",
        in: topRect(x: 182, y: 64, width: 420, height: 64),
        font: NSFont.systemFont(ofSize: 48, weight: .bold),
        color: .white
    )

    NSColor(calibratedRed: 0.18, green: 0.5, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: topRect(x: 70, y: 174, width: 84, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

    drawText(
        variant.headline,
        in: topRect(x: 68, y: 205, width: 550, height: 190),
        font: font(named: variant.fontName, size: 48, weight: .bold),
        color: .white,
        lineHeight: 63
    )
    drawText(
        variant.subheadline,
        in: topRect(x: 70, y: 418, width: 545, height: 76),
        font: font(named: variant.fontName, size: 23, weight: .medium),
        color: NSColor.white.withAlphaComponent(0.76),
        lineHeight: 32
    )
    drawText(
        "rekordbox × XPPen ACK05  •  macOS",
        in: topRect(x: 70, y: 532, width: 540, height: 32),
        font: NSFont.systemFont(ofSize: 17, weight: .semibold),
        color: NSColor(calibratedRed: 0.48, green: 0.7, blue: 1, alpha: 1)
    )
    drawText(
        "albasimia.github.io/OverCUE",
        in: topRect(x: 70, y: 576, width: 540, height: 26),
        font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
        color: NSColor.white.withAlphaComponent(0.58)
    )

    let screenshotRect = topRect(x: 660, y: 108, width: 474, height: 318)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: screenshotRect, xRadius: 18, yRadius: 18).fill()
    NSGraphicsContext.restoreGraphicsState()
    drawRoundedImage(screenshot, in: screenshotRect, radius: 18)

    drawText(
        "OPEN SOURCE  •  UNIVERSAL BINARY",
        in: topRect(x: 720, y: 465, width: 400, height: 30),
        font: NSFont.systemFont(ofSize: 15, weight: .bold),
        color: NSColor.white.withAlphaComponent(0.72)
    )

    context.flushGraphics()
    NSGraphicsContext.current = previousContext

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "OverCUEOGP", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Could not encode \(variant.outputName).",
        ])
    }
    try data.write(to: outputDirectory.appendingPathComponent(variant.outputName), options: .atomic)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
guard let icon = NSImage(contentsOf: imageDirectory.appendingPathComponent("overcue-icon.png")) else {
    fatalError("Missing OverCUE icon.")
}

for variant in variants {
    try generate(variant, icon: icon)
    print("Generated docs/assets/ogp/\(variant.outputName)")
}
