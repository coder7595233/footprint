import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: generate_app_icon.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = NSSize(width: 1024, height: 1024)

func aspectFit(_ source: NSSize, in target: NSRect) -> NSRect {
    guard source.width > 0, source.height > 0 else { return target }
    let scale = min(target.width / source.width, target.height / source.height)
    let width = source.width * scale
    let height = source.height * scale
    return NSRect(
        x: target.midX - width / 2,
        y: target.midY - height / 2,
        width: width,
        height: height
    )
}

let image = NSImage(size: size)
image.lockFocus()

NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

guard let baseSymbol = NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: "Footprint") else {
    fputs("Failed to load SF Symbol scribble.variable\n", stderr)
    exit(1)
}

let symbol = baseSymbol.withSymbolConfiguration(
    NSImage.SymbolConfiguration(pointSize: 660, weight: .regular)
) ?? baseSymbol

NSColor.black.setFill()
let rect = aspectFit(
    symbol.size,
    in: NSRect(x: 170, y: 170, width: 684, height: 684)
)
symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to generate icon image\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
