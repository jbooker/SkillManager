#!/usr/bin/swift
import AppKit
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon.png"
let pixels = 1024

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: pixels,
  pixelsHigh: pixels,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("Could not allocate bitmap\n", stderr)
  exit(1)
}

rep.size = NSSize(width: pixels, height: pixels)
NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
  fputs("Could not create graphics context\n", stderr)
  exit(1)
}
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

let inset: CGFloat = 88
let card = NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
let cardPath = NSBezierPath(roundedRect: card, xRadius: 214, yRadius: 214)
NSColor(srgbRed: 0.071, green: 0.082, blue: 0.106, alpha: 1).setFill()
cardPath.fill()

NSColor(srgbRed: 0.165, green: 0.192, blue: 0.251, alpha: 1).setStroke()
cardPath.lineWidth = 6
cardPath.stroke()

let mark = NSRect(x: 352, y: 352, width: 320, height: 320)
let markPath = NSBezierPath(roundedRect: mark, xRadius: 68, yRadius: 68)
let gradient = NSGradient(colors: [
  NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1),
  NSColor(srgbRed: 0.478, green: 0.635, blue: 1, alpha: 1),
  NSColor(srgbRed: 0.369, green: 0.878, blue: 0.753, alpha: 1),
  NSColor(srgbRed: 0.243, green: 0.812, blue: 0.557, alpha: 1),
  NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1),
])!
gradient.draw(in: markPath, angle: -150)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
  fputs("Could not encode PNG\n", stderr)
  exit(1)
}

let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: url)
print("Wrote \(output)")
