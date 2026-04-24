#!/usr/bin/env swift
// Rasterizes icon.svg at all .iconset sizes and produces MyCommander.icns.
//
//   swift icon/make_icns.swift
//
// Requires macOS 13+ (NSImage can load SVG).

import AppKit
import Foundation

let here = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent()
let svg = here.appendingPathComponent("icon.svg")
let iconset = here.appendingPathComponent("MyCommander.iconset")
let icns = here.appendingPathComponent("MyCommander.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let img = NSImage(contentsOf: svg) else {
    FileHandle.standardError.write("could not load SVG\n".data(using: .utf8)!)
    exit(1)
}

func rasterize(_ size: Int, filename: String) throws {
    let pxSize = NSSize(width: size, height: size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 32)!
    rep.size = pxSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(origin: .zero, size: pxSize),
             from: .zero,
             operation: .sourceOver,
             fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "png", code: 1)
    }
    try data.write(to: iconset.appendingPathComponent(filename))
}

// Apple's required iconset layout.
let entries: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in entries {
    try rasterize(size, filename: name)
    print("  • \(name) (\(size)×\(size))")
}

// Build the .icns via iconutil (shipped with macOS).
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()

print("\nWrote \(icns.path)")
