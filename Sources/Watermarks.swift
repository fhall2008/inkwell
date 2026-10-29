import SwiftUI

/// Draws a watermark. The same code makes the on-screen layer and the pictures in exports, so they match.
enum WatermarkRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    /// Draws into the current UIKit context, over a page of `size`.
    static func draw(_ wm: Watermark, in size: CGSize) {
        let label = wm.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !label.isEmpty, let ctx = UIGraphicsGetCurrentContext() else { return }

        let color = UIColor(hex: wm.colorHex)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(wm.size), weight: .bold),
            .foregroundColor: color,
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        let pad = wm.border == .none ? 0 : CGFloat(wm.size) * 0.25
        let box = CGRect(x: -textSize.width / 2 - pad, y: -textSize.height / 2 - pad * 0.6,
                         width: textSize.width + pad * 2, height: textSize.height + pad * 1.2)

        func stamp(at centre: CGPoint, fit: CGFloat) {
            ctx.saveGState()
            ctx.translateBy(x: centre.x, y: centre.y)
            ctx.rotate(by: CGFloat(wm.angle) * .pi / 180)
            ctx.scaleBy(x: fit, y: fit)
            ctx.setAlpha(CGFloat(wm.opacity))
            text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attributes)
            if wm.border != .none {
                let outline = UIBezierPath(cgPath: StampBorderShape(border: wm.border).path(in: box).cgPath)
                color.setStroke()
                outline.lineWidth = max(3, CGFloat(wm.size) / 14)
                outline.stroke()
            }
            ctx.restoreGState()
        }

        if wm.tiled {
            let stepX = box.width + CGFloat(wm.size)
            let stepY = box.height * 2.2
            var row = 0
            var y = -stepY
            while y < size.height + stepY {
                var x = (row.isMultiple(of: 2) ? 0 : stepX / 2) - stepX
                while x < size.width + stepX {
                    stamp(at: CGPoint(x: x, y: y), fit: 1)
                    x += stepX
                }
                y += stepY
                row += 1
            }
        } else {
            // One big watermark: shrink it if it would run off the page.
            let fit = min(1, size.width * 0.92 / max(box.width, 1))
            stamp(at: CGPoint(x: size.width / 2, y: size.height / 2), fit: fit)
        }
    }

    static func image(_ wm: Watermark, size: CGSize) -> UIImage {
        let key = "\(wm.text)|\(wm.colorHex)|\(wm.opacity)|\(wm.angle)|\(wm.size)|\(wm.border.rawValue)|\(wm.tiled)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = min(2, 3000 / max(size.width, size.height))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(wm, in: size) }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Set up the watermark for a whole note.
struct WatermarkSheet: View {
    @Binding var note: Note
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var on: Bool
    @State private var wm: Watermark

    private static let colours: [(name: String, hex: String)] = [
        ("Grey", "#8C99B3"), ("Red", "#C0392B"), ("Blue", "#2F5BEA"), ("Green", "#2E8B57"), ("Black", "#1B2430"),
    ]
    private static let quickPicks = ["DRAFT", "CONFIDENTIAL", "COPY", "SAMPLE", "DO NOT COPY", "FOR REVIEW"]

    init(note: Binding<Note>, onChange: @escaping () -> Void) {
        _note = note
        self.onChange = onChange
        let existing = note.wrappedValue.watermark
        _on = State(initialValue: true)   // opening this screen means you want one; switch it off to remove it
        _wm = State(initialValue: existing ?? Watermark(text: "DRAFT", border: .rounded))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show a watermark on every page", isOn: $on)
                } footer: {
                    Text("It sits behind your writing and appears in exports and printouts too.")
                }

                if on {
                    Section("Text") {
                        TextField("Watermark text", text: $wm.text)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Self.quickPicks, id: \.self) { pick in
                                    Button(pick) { wm.text = pick }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    Section("Look") {
                        HStack(spacing: 14) {
                            ForEach(Self.colours, id: \.hex) { item in
                                Button { wm.colorHex = item.hex } label: {
                                    Circle().fill(Color(hex: item.hex)).frame(width: 34, height: 34)
                                        .overlay(Circle().strokeBorder(wm.colorHex == item.hex ? Theme.accent : Theme.hairline,
                                                                       lineWidth: wm.colorHex == item.hex ? 3 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.name)
                            }
                        }
                        Picker("Border (makes it a stamp)", selection: $wm.border) {
                            ForEach(StampBorder.allCases) { Text($0.title).tag($0) }
                        }
                        slider("Strength", value: $wm.opacity, range: 0.05...0.6, step: 0.01, text: "\(Int(wm.opacity * 100))%")
                        slider("Angle", value: $wm.angle, range: -90...90, step: 1, text: "\(Int(wm.angle))°")
                        slider("Size", value: $wm.size, range: 30...300, step: 5, text: "\(Int(wm.size))")
                        Toggle("Repeat across the page", isOn: $wm.tiled)
                    }

                    Section("Preview") {
                        ZStack {
                            Color(hex: note.paperHex)
                            Image(uiImage: WatermarkRenderer.image(wm, size: note.pageSize))
                                .resizable()
                                .scaledToFit()
                        }
                        .frame(height: 280)
                        .overlay(Rectangle().stroke(Theme.hairline))
                        .accessibilityHidden(true)
                    }
                }
            }
            .navigationTitle("Watermark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply", action: apply).fontWeight(.semibold) }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(text).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }

    private func apply() {
        let hasText = !wm.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        note.watermark = (on && hasText) ? wm : nil
        onChange()
        dismiss()
    }
}
