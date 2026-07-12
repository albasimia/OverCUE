#!/usr/bin/env swift

import AppKit
import Foundation

private let targetSize = NSSize(width: 1200, height: 630)
private let colorLevels = 48
private let rootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let imageDirectory = rootURL.appendingPathComponent("docs/assets/ogp")
private let imageNames = ["ja.png", "en.png", "zh-CN.png"]

private func optimize(_ imageURL: URL) throws {
    guard let image = NSImage(contentsOf: imageURL),
          let bitmap = NSBitmapImageRep(
              bitmapDataPlanes: nil,
              pixelsWide: Int(targetSize.width),
              pixelsHigh: Int(targetSize.height),
              bitsPerSample: 8,
              samplesPerPixel: 4,
              hasAlpha: true,
              isPlanar: false,
              colorSpaceName: .deviceRGB,
              bytesPerRow: 0,
              bitsPerPixel: 0
          ),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "OverCUEOGP", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not load or prepare \(imageURL.lastPathComponent).",
        ])
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(
        in: NSRect(origin: .zero, size: targetSize),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.current = previousContext

    guard let pixels = bitmap.bitmapData else {
        throw NSError(domain: "OverCUEOGP", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Could not access pixels for \(imageURL.lastPathComponent).",
        ])
    }

    let maximumLevel = colorLevels - 1
    for y in 0 ..< bitmap.pixelsHigh {
        let row = pixels.advanced(by: y * bitmap.bytesPerRow)
        for x in 0 ..< bitmap.pixelsWide {
            let pixel = row.advanced(by: x * bitmap.samplesPerPixel)
            for channel in 0 ..< 3 {
                let value = Int(pixel[channel])
                let level = (value * maximumLevel + 127) / 255
                pixel[channel] = UInt8((level * 255 + maximumLevel / 2) / maximumLevel)
            }
        }
    }

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "OverCUEOGP", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Could not encode \(imageURL.lastPathComponent).",
        ])
    }
    try data.write(to: imageURL, options: .atomic)
    print("Optimized docs/assets/ogp/\(imageURL.lastPathComponent)")
}

for imageName in imageNames {
    try optimize(imageDirectory.appendingPathComponent(imageName))
}
