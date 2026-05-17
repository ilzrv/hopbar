import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: make_icon.swift <input.svg> <output.icns>\n".utf8))
    exit(64)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let iconsetURL = outputURL
    .deletingPathExtension()
    .appendingPathExtension("iconset")

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: outputURL)

guard let sourceImage = NSImage(contentsOf: inputURL) else {
    FileHandle.standardError.write(Data("Could not read SVG at \(inputURL.path)\n".utf8))
    exit(1)
}

for size in sizes {
    let pixels = Int(size.points * size.scale)
    let canvasSize = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    let padding = CGFloat(pixels) * 0.16
    let drawRect = NSRect(
        x: padding,
        y: padding,
        width: CGFloat(pixels) - padding * 2,
        height: CGFloat(pixels) - padding * 2
    )
    sourceImage.draw(in: drawRect)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Could not render \(size.name)\n".utf8))
        exit(1)
    }

    try png.write(to: iconsetURL.appendingPathComponent(size.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "--convert", "icns",
    "--output", outputURL.path,
    iconsetURL.path
]

try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    exit(process.terminationStatus)
}

try? fileManager.removeItem(at: iconsetURL)
