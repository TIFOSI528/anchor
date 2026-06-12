#!/usr/bin/env swift
// 生成 AppIcon.icns：直接光栅化品牌 SVG（单一艺术源，与 README 顶部所见逐像素一致）。
// 用法：swift scripts/generate-appicon.swift  → Assets/Brand/AppIcon.icns

import AppKit

let svgURL = URL(fileURLWithPath: "Assets/Brand/anchor-logo.svg")
guard let source = NSImage(contentsOf: svgURL) else {
    print("无法读取 \(svgURL.path)（需要 macOS 11+ 的 SVG 支持）")
    exit(1)
}

func renderPNG(size: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw NSError(domain: "appicon", code: 1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero, operation: .copy, fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "appicon", code: 2)
    }
    try data.write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "Assets/Brand/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try renderPNG(size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderPNG(size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", "Assets/Brand/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "✓ Assets/Brand/AppIcon.icns（源：anchor-logo.svg）" : "iconutil failed \(task.terminationStatus)")
