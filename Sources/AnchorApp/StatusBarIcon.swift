import AppKit

/// 菜单栏锚形图标：代码直绘的模板图（系统无 anchor SF Symbol；品牌 SVG 是彩色 logo
/// 不适合做模板）。`isTemplate` 自动适配菜单栏深浅色与按下高亮。
enum StatusBarIcon {

    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // 顶部圆环
            path.appendOval(in: NSRect(x: 7.2, y: 13.0, width: 3.6, height: 3.6))
            // 竖杆
            path.move(to: NSPoint(x: 9, y: 13.0))
            path.line(to: NSPoint(x: 9, y: 3.2))
            // 横杆
            path.move(to: NSPoint(x: 5.6, y: 10.8))
            path.line(to: NSPoint(x: 12.4, y: 10.8))
            // 底部锚臂（过底点的圆弧）
            path.move(to: NSPoint(x: 3.4, y: 7.0))
            path.appendArc(
                withCenter: NSPoint(x: 9, y: 9),
                radius: 6,
                startAngle: 200,
                endAngle: 340,
                clockwise: false
            )

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Anchor"
        return image
    }
}
