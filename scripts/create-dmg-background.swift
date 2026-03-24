#!/usr/bin/env swift
import AppKit

let width = 660
let height = 400

let img = NSImage(size: NSSize(width: width, height: height))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background gradient — dark blue-gray matching the app theme
let colors = [
    CGColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
    CGColor(red: 0.14, green: 0.14, blue: 0.20, alpha: 1.0)
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])

// Subtle grid pattern
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.03))
ctx.setLineWidth(0.5)
for x in stride(from: 0, to: width, by: 20) {
    ctx.move(to: CGPoint(x: x, y: 0))
    ctx.addLine(to: CGPoint(x: x, y: height))
}
for y in stride(from: 0, to: height, by: 20) {
    ctx.move(to: CGPoint(x: 0, y: y))
    ctx.addLine(to: CGPoint(x: width, y: y))
}
ctx.strokePath()

// Arrow in the middle pointing from app to Applications
let arrowY = CGFloat(height) / 2 - 10
let arrowX1: CGFloat = 260
let arrowX2: CGFloat = 400
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
ctx.setLineWidth(2.5)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Arrow line
ctx.move(to: CGPoint(x: arrowX1, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2, y: arrowY))
// Arrow head
ctx.move(to: CGPoint(x: arrowX2 - 12, y: arrowY - 10))
ctx.addLine(to: CGPoint(x: arrowX2, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2 - 12, y: arrowY + 10))
ctx.strokePath()

// "Drag to install" text
let textAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: NSColor(white: 1.0, alpha: 0.3)
]
let text = NSAttributedString(string: "Drag to install", attributes: textAttrs)
text.draw(at: NSPoint(x: 285, y: arrowY - 25))

// Bottom branding
let brandAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 10, weight: .regular),
    .foregroundColor: NSColor(white: 1.0, alpha: 0.15)
]
let brand = NSAttributedString(string: "OptaKube — Made by Souris.CLOUD", attributes: brandAttrs)
let brandSize = brand.size()
brand.draw(at: NSPoint(x: (CGFloat(width) - brandSize.width) / 2, y: 15))

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dmg-background.png"
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Background created: \(outputPath)")
