import UIKit

/// Draws page objects into the current UIKit graphics context, for thumbnails and exports.
/// Mirrors the on-screen views in ObjectViews.swift.
enum ObjectDrawing {
    static func draw(_ o: PageObject) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        if o.opacity < 1 { ctx.setAlpha(CGFloat(o.opacity)) }
        if o.rotation != 0 {
            // Tilt around the middle of the object, like the on-screen view.
            let cx = CGFloat(o.x + o.width / 2)
            let cy = CGFloat(o.y + (o.layoutHeight ?? o.height) / 2)
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(o.rotation) * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)
        }
        drawBody(o)
        ctx.restoreGState()
    }

    private static func drawBody(_ o: PageObject) {
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
            let outline = UIBezierPath(cgPath: StampBorderShape(border: o.border).path(in: CGRect(origin: .zero, size: r.size)).cgPath)
            outline.apply(CGAffineTransform(translationX: x, y: y))
            outline.lineWidth = 3
            outline.stroke()
            let label = o.text.uppercased() as NSString
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: o.uiFont, .foregroundColor: ink, .paragraphStyle: style]
            let bound = label.boundingRect(with: CGSize(width: r.width - 12, height: 4000),
                                           options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
            label.draw(in: CGRect(x: r.minX + 6, y: r.midY - bound.height / 2, width: r.width - 12, height: bound.height),
                       withAttributes: attributes)
        }
    }

    private static func text(_ s: String, in rect: CGRect, _ o: PageObject, _ color: UIColor, strike: Bool = false) {
        guard !s.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [.font: o.uiFont, .foregroundColor: color]
        if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        (s as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
    }
}
