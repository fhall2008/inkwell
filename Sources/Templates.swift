import UIKit

enum TemplateCategory: String, CaseIterable, Identifiable {
    case basic = "Basic", planning = "Planning", study = "Study", church = "Church"
    var id: String { rawValue }
}

/// Page backgrounds. Drawn in code so they stay sharp on screen, in exports and in thumbnails.
enum TemplateKind: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, grid, dots, cornell, meeting, planner, sermon

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
        }
    }

    var category: TemplateCategory {
        switch self {
        case .blank, .ruled, .grid, .dots: .basic
        case .meeting, .planner: .planning
        case .cornell: .study
        case .sermon: .church
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

    /// Draws into the current UIKit graphics context.
    func draw(size: CGSize) {
        let w = size.width, h = size.height
        let rule = UIColor(red: 0.80, green: 0.85, blue: 0.94, alpha: 1)
        let strong = UIColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1)

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
