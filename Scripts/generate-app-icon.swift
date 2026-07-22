#!/usr/bin/env swift

import AppKit

let size = NSSize(width: 1024, height: 1024)
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

let image = NSImage(size: size)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

let colors = [
    CGColor(red: 0.22, green: 0.47, blue: 0.98, alpha: 1),
    CGColor(red: 0.10, green: 0.32, blue: 0.82, alpha: 1)
]
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: colors as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 1024),
    end: CGPoint(x: 1024, y: 0),
    options: []
)

let symbolConfig = NSImage.SymbolConfiguration(pointSize: 500, weight: .medium)
guard let symbol = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) else {
    fputs("Failed to load SF Symbol\n", stderr)
    exit(1)
}

let symbolSize = symbol.size
let rect = NSRect(
    x: (1024 - symbolSize.width) / 2,
    y: (1024 - symbolSize.height) / 2,
    width: symbolSize.width,
    height: symbolSize.height
)

NSColor.white.withAlphaComponent(0.95).setFill()
symbol.draw(in: rect)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Saved app icon to \(outputPath)")
