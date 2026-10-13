import AppKit

// 生成 iTabs 图标:参考 SAP Tabs 的结构(圆角梯形主体 + 顶部页签栏横条),
// 但配色更浅(浅蓝渐变),横条上放四个彩色小方块(红/蓝/绿/黄),
// 呼应菜单栏那个 2x2 四色图标,寓意"多 app 通用页签栏"。
func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    let s = size

    // 梯形主体:顶边宽、底边窄,底边两端向内收(与 SAP GUI Tabs 同形)
    let left = s * 0.10
    let right = s * 0.90
    let top = s * 0.74
    let bottom = s * 0.26
    let slant = s * 0.16
    let radius = s * 0.05

    let trapezoid = CGMutablePath()
    let pts = [
        CGPoint(x: left, y: top),
        CGPoint(x: right, y: top),
        CGPoint(x: right - slant, y: bottom),
        CGPoint(x: left + slant, y: bottom)
    ]
    trapezoid.addRoundedPolygon(points: pts, radius: radius)

    // 浅蓝渐变(比 SAP GUI Tabs 明显更浅)
    ctx.saveGState()
    ctx.addPath(trapezoid)
    ctx.clip()
    let colors = [
        NSColor(red: 0.55, green: 0.80, blue: 0.96, alpha: 1).cgColor, // 顶部浅亮蓝
        NSColor(red: 0.33, green: 0.63, blue: 0.90, alpha: 1).cgColor  // 底部中蓝
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    ctx.restoreGState()

    // 顶部横条(页签栏)
    let barHeight = (top - bottom) * 0.30
    let barInset = s * 0.08
    let barRect = CGRect(x: left + barInset,
                         y: top - barHeight - (top - bottom) * 0.10,
                         width: (right - left) - barInset * 2,
                         height: barHeight)
    let barCorner = barHeight * 0.35
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: barCorner, cornerHeight: barCorner, transform: nil))
    ctx.fillPath()

    // 横条上四个彩色小方块(红/蓝/绿/黄),与菜单栏 2x2 图标同配色
    let tabCount = 4
    let tabGap = barRect.width * 0.05
    let tabW = (barRect.width - tabGap * CGFloat(tabCount + 1)) / CGFloat(tabCount)
    let tabH = barRect.height * 0.5
    let tabY = barRect.midY - tabH / 2
    let tabColors: [NSColor] = [
        NSColor(red: 0.90, green: 0.26, blue: 0.21, alpha: 1), // 红
        NSColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1), // 蓝
        NSColor(red: 0.18, green: 0.74, blue: 0.42, alpha: 1), // 绿
        NSColor(red: 0.95, green: 0.77, blue: 0.06, alpha: 1), // 黄
    ]
    for i in 0..<tabCount {
        let x = barRect.minX + tabGap + (tabW + tabGap) * CGFloat(i)
        let r = CGRect(x: x, y: tabY, width: tabW, height: tabH)
        ctx.setFillColor(tabColors[i].cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: tabH * 0.25, cornerHeight: tabH * 0.25, transform: nil))
        ctx.fillPath()
    }

    img.unlockFocus()
    return img
}

extension CGMutablePath {
    func addRoundedPolygon(points: [CGPoint], radius: CGFloat) {
        guard points.count >= 3 else { return }
        let n = points.count
        for i in 0..<n {
            let prev = points[(i + n - 1) % n]
            let curr = points[i]
            let next = points[(i + 1) % n]
            if i == 0 {
                move(to: CGPoint(x: (curr.x + prev.x) / 2, y: (curr.y + prev.y) / 2))
            }
            addArc(tangent1End: curr, tangent2End: next, radius: radius)
        }
        closeSubpath()
    }
}

func pngData(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = "/tmp/iTabs.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in specs {
    let data = pngData(px: spec.px)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(spec.name).png"))
}
print("iconset written to \(iconset)")
