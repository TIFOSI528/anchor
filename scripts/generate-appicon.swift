#!/usr/bin/env swift
// 生成 AppIcon.icns：与菜单栏 StatusBarIcon / Brand SVG 同一几何。
// 用法：swift scripts/generate-appicon.swift  → Assets/Brand/AppIcon.icns

import AppKit

let designSize: CGFloat = 240

func draw(in size: CGFloat) -> NSImage {
    let scale = size / designSize
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.scaleBy(x: scale, y: scale)

        // 圆角方块底（macOS 图标网格：边距 ~8/240）
        let tile = CGPath(
            roundedRect: CGRect(x: 8, y: 8, width: 224, height: 224),
            cornerWidth: 52, cornerHeight: 52, transform: nil
        )
        ctx.addPath(tile)
        ctx.setFillColor(CGColor(red: 0x0F/255, green: 0x17/255, blue: 0x2A/255, alpha: 1))
        ctx.fillPath()

        // 锚形（SVG 同坐标，y 向下）
        ctx.setStrokeColor(CGColor(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255, alpha: 1))
        ctx.setLineWidth(14)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.addEllipse(in: CGRect(x: 120 - 19, y: 56 - 19, width: 38, height: 38)) // 圆环
        ctx.move(to: CGPoint(x: 120, y: 75)); ctx.addLine(to: CGPoint(x: 120, y: 200)) // 竖杆
        ctx.move(to: CGPoint(x: 80, y: 102)); ctx.addLine(to: CGPoint(x: 160, y: 102)) // 横杆
        // 锚臂：圆心 (120,138) r66，自左端经底部到右端
        ctx.addArc(center: CGPoint(x: 120, y: 138), radius: 66,
                   startAngle: .pi, endAngle: 0, clockwise: true) // flipped 上下文里 clockwise=true 走下半圆
        ctx.strokePath()
        return true
    }
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw NSError(domain: "appicon", code: 1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = image.size
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
    try writePNG(draw(in: CGFloat(base)), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(draw(in: CGFloat(base * 2)), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", "Assets/Brand/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "✓ Assets/Brand/AppIcon.icns" : "iconutil failed \(task.terminationStatus)")
