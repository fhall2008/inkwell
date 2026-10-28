// Generates a placeholder 1024x1024 app icon (no alpha, as App Store Connect requires).
// Usage: swift Tools/make_icon.swift <output.png>
// Replace Assets.xcassets/AppIcon.appiconset/icon.png with real artwork whenever you like.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

ctx.setFillColor(CGColor(red: 0.184, green: 0.357, blue: 0.918, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// A white pencil at 45 degrees.
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: .pi / 4)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addPath(CGPath(roundedRect: CGRect(x: -70, y: -90, width: 140, height: 430), cornerWidth: 24, cornerHeight: 24, transform: nil))
ctx.fillPath()
ctx.move(to: CGPoint(x: -70, y: -110))
ctx.addLine(to: CGPoint(x: 70, y: -110))
ctx.addLine(to: CGPoint(x: 0, y: -330))
ctx.closePath()
ctx.fillPath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write icon") }
