import UIKit

/// Draws page objects into the current UIKit graphics context, for thumbnails and exports.
/// Mirrors the on-screen views in ObjectViews.swift.
enum ObjectDrawing {
    static func draw(_ o: PageObject) {
        let ink = UIColor(hex: o.colorHex)
        let x = CGFloat(o.x), y = CGFloat(o.y), w = CGFloat(o.width)

        switch o.kind {
        case .text:
            text(o.formattedText, in: CGRect(x: x, y: y, width: w, height: 4000), o, ink)

        case .line, .arrow, .rectangle, .ellipse, .triangle, .star:
            let size = CGSize(width: w, height: CGFloat(o.height))
            let path = UIBezierPath(cgPath: ObjectShape(kind: o.kind).path(in: CGRect(origin: .zero, size: size)).cgPath)
            path.apply(CGAffineTransform(translationX: x, y: y))
            if let fill = o.fillHex, o.kind != .line, o.kind != .arrow {
                UIColor(hex: fill).setFill()
                path.fill()
            }
            ink.setStroke()
            path.lineWidth = CGFloat(o.lineWidth)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case .sticky:
            let r = CGRect(x: x, y: y, width: w, height: CGFloat(o.height))
            UIColor(hex: o.fillHex ?? "#FFE98A").setFill()
            UIBezierPath(roundedRect: r, cornerRadius: 6).fill()
            text(o.text, in: r.insetBy(dx: 12, dy: 12), o, ink)

        case .checklist:
            let rh = CGFloat(o.rowHeight)
            let box = CGFloat(o.fontSize)
            for (i, item) in o.items.enumerated() {
                let rowY = y + CGFloat(i) * rh
                let b = CGRect(x: x, y: rowY + (rh - box) / 2, width: box, height: box)
                ink.setStroke()
                let outline = UIBezierPath(roundedRect: b, cornerRadius: 3)
                outline.lineWidth = 1.5
                outline.stroke()
                if item.done {
                    let tick = UIBezierPath()
                    tick.move(to: CGPoint(x: b.minX + box * 0.22, y: b.midY))
                    tick.addLine(to: CGPoint(x: b.minX + box * 0.43, y: b.maxY - box * 0.25))
                    tick.addLine(to: CGPoint(x: b.maxX - box * 0.2, y: b.minY + box * 0.25))
                    tick.lineWidth = 2
                    tick.lineCapStyle = .round
                    tick.stroke()
                }
                let textX = x + box + 10
                text(item.text, in: CGRect(x: textX, y: rowY + (rh - o.uiFont.lineHeight) / 2, width: w - box - 10, height: rh), o, ink, strike: item.done)
            }

        case .table:
            let rows = o.cells.count
            let cols = o.cells.first?.count ?? 0
            guard cols > 0 else { return }
            let cw = w / CGFloat(cols)
            let rh = CGFloat(o.rowHeight)
            for r in 0..<rows {
                for c in 0..<cols {
                    let cell = CGRect(x: x + CGFloat(c) * cw, y: y + CGFloat(r) * rh, width: cw, height: rh)
                    ink.setStroke()
                    let border = UIBezierPath(rect: cell)
                    border.lineWidth = 1
                    border.stroke()
                    let value = o.cells[r].indices.contains(c) ? o.cells[r][c] : ""
                    text(value, in: CGRect(x: cell.minX + 6, y: cell.minY + (rh - o.uiFont.lineHeight) / 2, width: cw - 12, height: rh), o, ink)
                }
            }

        case .stamp:
            let r = CGRect(x: x, y: y, width: w, height: CGFloat(o.height))
            ink.setStroke()
            let border = UIBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 8)
            border.lineWidth = 3
            border.stroke()
            let label = o.text.uppercased()
            let size = (label as NSString).size(withAttributes: [.font: o.uiFont])
            text(label, in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width + 2, height: size.height), o, ink)
        }
    }

    private static func text(_ s: String, in rect: CGRect, _ o: PageObject, _ color: UIColor, strike: Bool = false) {
        guard !s.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [.font: o.uiFont, .foregroundColor: color]
        if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        (s as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
    }
}
