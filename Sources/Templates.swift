import UIKit

enum TemplateCategory: String, CaseIterable, Identifiable {
    case basic = "Basic", art = "Art guides", planning = "Planning", study = "Study", church = "Church"
    var id: String { rawValue }
}

/// Page backgrounds. Drawn in code so they stay sharp on screen, in exports and in thumbnails.
enum TemplateKind: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, grid, dots, cornell, meeting, planner, sermon
    case onePoint, twoPoint, face, figure, colourWheel, valueScale, thirds, isometric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .ruled: "Ruled"
        case .grid: "Grid"
        case .dots: "Dot grid"
        case .cornell: "Cornell notes"
        case .meeting: "Meeting minutes"
        case .planner: "Weekly planner"
        case .sermon: "Sermon outline"
        case .onePoint: "One-point perspective"
        case .twoPoint: "Two-point perspective"
        case .face: "Face proportions"
        case .figure: "Figure (8 heads)"
        case .colourWheel: "Colour wheel"
        case .valueScale: "Value scale"
        case .thirds: "Composition guides"
        case .isometric: "Isometric grid"
        }
    }

    var category: TemplateCategory {
        switch self {
        case .blank, .ruled, .grid, .dots: .basic
        case .meeting, .planner: .planning
        case .cornell: .study
        case .sermon: .church
        case .onePoint, .twoPoint, .face, .figure, .colourWheel, .valueScale, .thirds, .isometric: .art
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Cached background image at page size.
    var image: UIImage {
        if let hit = Self.cache.object(forKey: rawValue as NSString) { return hit }
        let size = PageRenderer.pageSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            draw(size: size)
        }
        Self.cache.setObject(img, forKey: rawValue as NSString)
        return img
    }

    /// Cached background image for a page of any size. Layouts are designed for A4's width and are scaled
    /// to the page's width, so A5, A6 and B5 (which have the same proportions) look exactly like A4.
    func image(size: CGSize, paperHex: String) -> UIImage {
        let key = "\(rawValue)-\(Int(size.width))x\(Int(size.height))-\(paperHex)" as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(hex: paperHex).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            drawFitted(size: size)
        }
        Self.cache.setObject(img, forKey: key)
        return img
    }

    /// A small A4-shaped preview for pickers, so showing all sixteen doesn't keep sixteen full-size images in memory.
    func preview(paperHex: String) -> UIImage {
        let key = "preview-\(rawValue)-\(paperHex)" as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }
        let size = PageRenderer.pageSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 0.35
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(hex: paperHex).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            draw(size: size)
        }
        Self.cache.setObject(img, forKey: key)
        return img
    }

    /// Draws the template into the current context, scaled so its A4-wide layout fills a page of `size`.
    func drawFitted(size: CGSize) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let scale = size.width / 794
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        draw(size: CGSize(width: 794, height: size.height / scale))
        ctx.restoreGState()
    }

    /// A small repeating tile for whiteboards, so a 6000-point board doesn't need a 6000-point image.
    /// Only grid and dots repeat; everything else is a plain board.
    static func whiteboardTile(_ kind: TemplateKind, paperHex: String) -> UIImage? {
        guard kind == .grid || kind == .dots else { return nil }
        let key = "tile-\(kind.rawValue)-\(paperHex)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let side: CGFloat = 28
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIColor(hex: paperHex).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            if kind == .grid {
                UIColor(red: 0.80, green: 0.85, blue: 0.94, alpha: 1).setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: side, height: 0.8))
                UIRectFill(CGRect(x: 0, y: 0, width: 0.8, height: side))
            } else {
                UIColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: side / 2 - 1.2, y: side / 2 - 1.2, width: 2.4, height: 2.4)).fill()
            }
        }
        cache.setObject(img, forKey: key)
        return img
    }

    /// Draws into the current UIKit graphics context.
    func draw(size: CGSize) {
        let w = size.width, h = size.height
        let rule = UIColor(red: 0.80, green: 0.85, blue: 0.94, alpha: 1)
        let strong = UIColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1)
        let guide = UIColor(red: 0.62, green: 0.72, blue: 0.93, alpha: 1)
        let clay = UIColor(red: 0.93, green: 0.72, blue: 0.62, alpha: 1)

        switch self {
        case .blank:
            break
        case .ruled:
            for y in stride(from: CGFloat(96), to: h - 40, by: 32) { line(36, y, w - 36, y, rule) }
            line(84, 0, 84, h, UIColor(red: 0.94, green: 0.72, blue: 0.72, alpha: 1))
        case .grid:
            for x in stride(from: CGFloat(0), through: w, by: 28) { line(x, 0, x, h, rule, 0.8) }
            for y in stride(from: CGFloat(0), through: h, by: 28) { line(0, y, w, y, rule, 0.8) }
        case .dots:
            strong.setFill()
            for x in stride(from: CGFloat(28), to: w, by: 28) {
                for y in stride(from: CGFloat(28), to: h, by: 28) {
                    UIBezierPath(ovalIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)).fill()
                }
            }
        case .cornell:
            label("Topic", 36, 30)
            line(36, 72, w - 36, 72, strong, 1.5)
            let bottom = h - 230
            line(230, 72, 230, bottom, strong, 1.5)
            label("Cues", 36, 84)
            label("Notes", 246, 84)
            for y in stride(from: CGFloat(128), to: bottom, by: 32) { line(246, y, w - 36, y, rule) }
            line(36, bottom, w - 36, bottom, strong, 1.5)
            label("Summary", 36, bottom + 12)
            for y in stride(from: bottom + 64, to: h - 36, by: 32) { line(36, y, w - 36, y, rule) }
        case .meeting:
            label("Meeting", 36, 30)
            line(120, 52, w - 260, 52, strong)
            label("Date", w - 240, 30)
            line(w - 200, 52, w - 36, 52, strong)
            label("Attendees", 36, 84)
            for y in [CGFloat(130), 162] { line(36, y, w - 36, y, rule) }
            label("Agenda", 36, 190)
            for y in stride(from: CGFloat(238), to: 430, by: 32) { line(36, y, w - 36, y, rule) }
            label("Notes", 36, 450)
            for y in stride(from: CGFloat(498), to: 790, by: 32) { line(36, y, w - 36, y, rule) }
            label("Actions", 36, 810)
            for y in stride(from: CGFloat(858), to: h - 40, by: 32) {
                line(64, y, w - 36, y, rule)
                strong.setStroke()
                let box = UIBezierPath(rect: CGRect(x: 36, y: y - 18, width: 16, height: 16))
                box.lineWidth = 1
                box.stroke()
            }
        case .planner:
            label("Week of", 36, 30)
            line(110, 52, w - 36, 52, strong)
            let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
            for (i, d) in days.enumerated() {
                let r = CGRect(x: 36, y: 76 + CGFloat(i) * 150, width: w - 72, height: 140)
                box(r, strong)
                label(d, r.minX + 10, r.minY + 8)
            }
            let half = (w - 72 - 14) / 2
            for (i, d) in ["Saturday", "Sunday"].enumerated() {
                let r = CGRect(x: 36 + CGFloat(i) * (half + 14), y: 76 + 5 * 150, width: half, height: h - 76 - 5 * 150 - 36)
                box(r, strong)
                label(d, r.minX + 10, r.minY + 8)
            }
        case .onePoint:
            let horizon: CGFloat = 480
            let vp = CGPoint(x: w / 2, y: horizon)
            for x in stride(from: CGFloat(0), through: w, by: 66) {
                line(vp.x, vp.y, x, 0, guide, 0.8)
                line(vp.x, vp.y, x, h, guide, 0.8)
            }
            for y in stride(from: CGFloat(0), through: h, by: 66) {
                line(vp.x, vp.y, 0, y, guide, 0.8)
                line(vp.x, vp.y, w, y, guide, 0.8)
            }
            line(0, horizon, w, horizon, strong, 1.6)
            dot(vp, 5, strong)
            label("Horizon line", 36, horizon - 22)
            label("Vanishing point", vp.x + 12, horizon + 10)
        case .twoPoint:
            let horizon: CGFloat = 520
            let v1 = CGPoint(x: 40, y: horizon), v2 = CGPoint(x: w - 40, y: horizon)
            for x in stride(from: CGFloat(99), to: w, by: 99) { line(x, 0, x, h, rule, 0.6) }
            for y in stride(from: CGFloat(0), through: h, by: 70) {
                line(v1.x, v1.y, w, y, guide, 0.8)
                line(v2.x, v2.y, 0, y, clay, 0.8)
            }
            line(0, horizon, w, horizon, strong, 1.6)
            dot(v1, 5, strong)
            dot(v2, 5, strong)
            label("VP 1", v1.x + 8, horizon + 10)
            label("VP 2", v2.x - 46, horizon + 10)
            label("Horizon line", w / 2 - 40, horizon - 22)
        case .face:
            let cx = w / 2, top: CGFloat = 190, fh: CGFloat = 560, fw: CGFloat = 400
            let oval = UIBezierPath(ovalIn: CGRect(x: cx - fw / 2, y: top, width: fw, height: fh))
            oval.lineWidth = 1.5
            strong.setStroke()
            oval.stroke()
            line(cx, top - 30, cx, top + fh + 30, strong, 1)
            let marks: [(String, CGFloat)] = [("Top of head", 0), ("Hairline", 0.14), ("Brow", 0.38), ("Eye line", 0.5), ("Nose base", 0.74), ("Mouth", 0.85), ("Chin", 1)]
            for (name, f) in marks {
                let y = top + fh * f
                line(cx - fw / 2 - 30, y, cx + fw / 2 + 30, y, guide, 0.9)
                label(name, 36, y - 14)
            }
            for i in 1..<5 {
                let x = cx - fw / 2 + fw * CGFloat(i) / 5
                line(x, top + fh * 0.5 - 22, x, top + fh * 0.5 + 22, strong, 1)
            }
            label("Eyes sit halfway down. Five eye-widths across.", 36, 60)
        case .figure:
            let top: CGFloat = 70, unit: CGFloat = 120, cx = w / 2
            line(cx, top - 10, cx, top + unit * 8 + 10, strong, 1)
            let names = ["Chin", "Nipples", "Navel", "Crotch", "Mid thigh", "Knee", "Calf", "Feet"]
            for i in 0...8 {
                let y = top + unit * CGFloat(i)
                let edge = i == 0 || i == 8
                line(cx - 180, y, cx + 180, y, edge ? strong : guide, edge ? 1.4 : 0.9)
                if i < 8 { label("\(i + 1)", cx + 192, y + 4) }
                if i > 0 { label(names[i - 1], 36, y - 14) }
            }
            let head = UIBezierPath(ovalIn: CGRect(x: cx - 45, y: top + 8, width: 90, height: unit - 16))
            head.lineWidth = 1
            guide.setStroke()
            head.stroke()
        case .colourWheel:
            let c = CGPoint(x: w / 2, y: 400)
            let r: CGFloat = 300, inner: CGFloat = 90
            for i in 0..<12 {
                let a0 = CGFloat(i) / 12 * 2 * .pi - .pi / 2 - .pi / 12
                let a1 = a0 + 2 * .pi / 12
                let wedge = UIBezierPath()
                wedge.move(to: c)
                wedge.addArc(withCenter: c, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
                wedge.close()
                UIColor(hue: CGFloat(i) / 12, saturation: 0.75, brightness: 0.95, alpha: 0.55).setFill()
                wedge.fill()
                strong.setStroke()
                wedge.lineWidth = 0.8
                wedge.stroke()
            }
            let hole = UIBezierPath(ovalIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            UIColor.white.setFill()
            hole.fill()
            strong.setStroke()
            hole.lineWidth = 1
            hole.stroke()
            label("Colour wheel", 36, 36)
            for y in stride(from: CGFloat(780), to: h - 40, by: 32) { line(36, y, w - 36, y, rule) }
        case .valueScale:
            let n = 9
            let bw = (w - 72) / CGFloat(n)
            label("Value scale: row 1 is the guide, fill the rest yourself", 36, 36)
            for row in 0..<5 {
                let y = 70 + CGFloat(row) * 130
                for i in 0..<n {
                    let r = CGRect(x: 36 + bw * CGFloat(i), y: y, width: bw, height: 100)
                    if row == 0 {
                        UIColor(white: 1 - CGFloat(i) / CGFloat(n - 1), alpha: 1).setFill()
                        UIRectFill(r)
                    }
                    let b = UIBezierPath(rect: r)
                    b.lineWidth = 0.8
                    strong.setStroke()
                    b.stroke()
                    label("\(i + 1)", r.minX + 4, y + 104)
                }
            }
            for y in stride(from: CGFloat(780), to: h - 40, by: 32) { line(36, y, w - 36, y, rule) }
        case .thirds:
            let inset: CGFloat = 36
            let r = CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset)
            let frame = UIBezierPath(rect: r)
            frame.lineWidth = 1.5
            strong.setStroke()
            frame.stroke()
            for i in 1...2 {
                let f = CGFloat(i) / 3
                line(r.minX + r.width * f, r.minY, r.minX + r.width * f, r.maxY, strong, 1)
                line(r.minX, r.minY + r.height * f, r.maxX, r.minY + r.height * f, strong, 1)
            }
            line(r.minX, r.minY, r.maxX, r.maxY, guide, 0.8)
            line(r.maxX, r.minY, r.minX, r.maxY, guide, 0.8)
            for i in 1...2 {
                for j in 1...2 {
                    let p = CGPoint(x: r.minX + r.width * CGFloat(i) / 3, y: r.minY + r.height * CGFloat(j) / 3)
                    let ring = UIBezierPath(ovalIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28))
                    ring.lineWidth = 1.5
                    clay.setStroke()
                    ring.stroke()
                }
            }
            label("Rule of thirds, power points and diagonals", inset + 6, 12)
        case .isometric:
            let step: CGFloat = 46
            let slope: CGFloat = 0.57735
            for x in stride(from: CGFloat(0), through: w, by: step * 0.8660254) { line(x, 0, x, h, rule, 0.7) }
            let lower = -Int(w * slope / step) - 1
            let upper = Int(h / step) + 1
            for k in lower...upper {
                let y0 = CGFloat(k) * step
                line(0, y0, w, y0 + w * slope, rule, 0.7)
                line(0, y0 + w * slope, w, y0, rule, 0.7)
            }
        case .sermon:
            let sections: [(String, Int)] = [("Text and theme", 2), ("Big idea", 2), ("Point 1", 4), ("Point 2", 4), ("Point 3", 4), ("Application", 3), ("Prayer", 2)]
            var y: CGFloat = 36
            for (name, lines) in sections {
                label(name, 36, y)
                y += 40
                for _ in 0..<lines {
                    y += 32
                    line(36, y, w - 36, y, rule)
                }
                y += 14
            }
        }
    }

    // MARK: Drawing helpers

    private func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ color: UIColor, _ width: CGFloat = 1) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        p.lineWidth = width
        color.setStroke()
        p.stroke()
    }

    private func dot(_ p: CGPoint, _ radius: CGFloat, _ color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    private func box(_ rect: CGRect, _ color: UIColor) {
        let p = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        p.lineWidth = 1.2
        color.setStroke()
        p.stroke()
    }

    private func label(_ text: String, _ x: CGFloat, _ y: CGFloat) {
        (text.uppercased() as NSString).draw(
            at: CGPoint(x: x, y: y),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor(red: 0.36, green: 0.40, blue: 0.45, alpha: 1),
                .kern: 1.0,
            ]
        )
    }
}
