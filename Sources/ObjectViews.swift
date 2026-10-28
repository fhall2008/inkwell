import SwiftUI

// MARK: - Colour and font helpers (shared with ObjectDrawing)

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count != 6 { s = "1B2430" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
    var hex: String { UIColor(self).hexString }
}

extension TextDesign {
    var swiftUI: Font.Design {
        switch self {
        case .sans: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }

    var uiKit: UIFontDescriptor.SystemDesign {
        switch self {
        case .sans: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
}

extension PageObject {
    var swiftUIFont: Font {
        let f = Font.system(size: fontSize, weight: bold ? .bold : .regular, design: design.swiftUI)
        return italic ? f.italic() : f
    }

    var uiFont: UIFont {
        var d = UIFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular).fontDescriptor
        if let withDesign = d.withDesign(design.uiKit) { d = withDesign }
        if italic, let withItalic = d.withSymbolicTraits(d.symbolicTraits.union(.traitItalic)) { d = withItalic }
        return UIFont(descriptor: d, size: fontSize)
    }

    var rowHeight: Double { fontSize * 1.6 + 8 }

    /// Text with bullets or numbers added line by line.
    var formattedText: String {
        let lines = text.components(separatedBy: "\n")
        switch list {
        case .none: return text
        case .bullet: return lines.map { "• " + $0 }.joined(separator: "\n")
        case .numbered: return lines.enumerated().map { "\($0.offset + 1). " + $0.element }.joined(separator: "\n")
        }
    }

    /// Fixed height for kinds that size themselves from their rows; nil for auto-height text.
    var layoutHeight: Double? {
        switch kind {
        case .text: nil
        case .checklist: max(rowHeight, Double(items.count) * rowHeight)
        case .table: max(rowHeight, Double(cells.count) * rowHeight)
        default: height
        }
    }

    var resizesHeight: Bool {
        switch kind {
        case .text, .checklist, .table: false
        default: true
        }
    }
}

// MARK: - Shapes

struct ObjectShape: Shape {
    let kind: ObjectKind

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .line:
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        case .arrow:
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.move(to: CGPoint(x: r.maxX - 16, y: r.midY - 10))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - 16, y: r.midY + 10))
        case .rectangle:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 6, height: 6))
        case .ellipse:
            p.addEllipse(in: r)
        case .triangle:
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        case .star:
            let c = CGPoint(x: r.midX, y: r.midY)
            let outer = min(r.width, r.height) / 2
            let inner = outer * 0.4
            for i in 0..<10 {
                let radius = i.isMultiple(of: 2) ? outer : inner
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let pt = CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        default:
            break
        }
        return p
    }
}

// MARK: - Object content

struct ObjectContent: View {
    @Binding var o: PageObject
    let size: CGSize
    let editable: Bool
    var onChange: () -> Void

    private var ink: Color { Color(hex: o.colorHex) }

    var body: some View {
        switch o.kind {
        case .text: textBody
        case .line, .arrow, .rectangle, .ellipse, .triangle, .star: shapeBody
        case .sticky: stickyBody
        case .checklist: checklistBody
        case .table: tableBody
        case .stamp: stampBody
        }
    }

    private var textBody: some View {
        Group {
            if editable {
                TextField("Type here", text: $o.text, axis: .vertical)
                    .onChange(of: o.text) { onChange() }
            } else {
                Text(o.formattedText)
            }
        }
        .font(o.swiftUIFont)
        .foregroundStyle(ink)
        .frame(width: size.width, alignment: .topLeading)
    }

    private var shapeBody: some View {
        ZStack {
            if let fill = o.fillHex, o.kind != .line, o.kind != .arrow {
                ObjectShape(kind: o.kind).fill(Color(hex: fill))
            }
            ObjectShape(kind: o.kind)
                .stroke(ink, style: StrokeStyle(lineWidth: o.lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height)
    }

    private var stickyBody: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: o.fillHex ?? "#FFE98A"))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            Group {
                if editable {
                    TextField("Note", text: $o.text, axis: .vertical)
                        .onChange(of: o.text) { onChange() }
                } else {
                    Text(o.text)
                }
            }
            .font(o.swiftUIFont)
            .foregroundStyle(ink)
            .padding(12)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var checklistBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach($o.items) { $item in
                HStack(spacing: 10) {
                    Button {
                        item.done.toggle()
                        onChange()
                    } label: {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: o.fontSize))
                    }
                    .buttonStyle(.plain)
                    if editable {
                        TextField("Item", text: $item.text)
                            .onChange(of: item.text) { onChange() }
                    } else {
                        Text(item.text).strikethrough(item.done)
                    }
                }
                .frame(height: o.rowHeight)
            }
        }
        .font(o.swiftUIFont)
        .foregroundStyle(ink)
        .frame(width: size.width, alignment: .topLeading)
    }

    private var tableBody: some View {
        let rows = o.cells.count
        let cols = o.cells.first?.count ?? 0
        return VStack(spacing: 0) {
            if cols > 0 {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            cell(r, c)
                                .padding(.horizontal, 6)
                                .frame(width: size.width / CGFloat(cols), height: o.rowHeight, alignment: .leading)
                                .overlay(Rectangle().stroke(ink, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .font(o.swiftUIFont)
        .foregroundStyle(ink)
        .frame(width: size.width, alignment: .topLeading)
    }

    @ViewBuilder
    private func cell(_ r: Int, _ c: Int) -> some View {
        let binding = Binding<String>(
            get: { o.cells.indices.contains(r) && o.cells[r].indices.contains(c) ? o.cells[r][c] : "" },
            set: {
                guard o.cells.indices.contains(r), o.cells[r].indices.contains(c) else { return }
                o.cells[r][c] = $0
                onChange()
            }
        )
        if editable { TextField("", text: binding).lineLimit(1) } else { Text(binding.wrappedValue).lineLimit(1) }
    }

    private var stampBody: some View {
        Text(o.text.uppercased())
            .font(o.swiftUIFont)
            .foregroundStyle(ink)
            .frame(width: size.width, height: size.height)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink, lineWidth: 3))
    }
}

// MARK: - Selection chrome (move, resize, menu)

struct ObjectChrome: View {
    @Binding var o: PageObject
    let editable: Bool
    let selected: Bool
    var onSelect: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onChange: () -> Void

    @State private var drag: CGSize = .zero
    @State private var resize: CGSize = .zero

    var body: some View {
        let width = max(60, o.width + resize.width)
        let height = o.layoutHeight.map { max(24, $0 + (o.resizesHeight ? resize.height : 0)) }

        ObjectContent(o: $o, size: CGSize(width: width, height: height ?? 0), editable: editable, onChange: onChange)
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay {
                if editable {
                    Rectangle()
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: [6, 4]))
                        .opacity(selected ? 1 : 0.5)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if editable && selected {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 28)
                        .background(Theme.accent, in: Capsule())
                        .offset(y: -34)
                        .gesture(
                            DragGesture(coordinateSpace: .named("page"))
                                .onChanged { drag = $0.translation }
                                .onEnded {
                                    o.x += $0.translation.width
                                    o.y += $0.translation.height
                                    drag = .zero
                                    onChange()
                                }
                        )
                        .accessibilityLabel("Drag to move")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if editable && selected {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                        .offset(x: 16, y: 16)
                        .gesture(
                            DragGesture(coordinateSpace: .named("page"))
                                .onChanged { resize = $0.translation }
                                .onEnded {
                                    o.width = max(60, o.width + $0.translation.width)
                                    if o.resizesHeight { o.height = max(24, o.height + $0.translation.height) }
                                    resize = .zero
                                    onChange()
                                }
                        )
                        .accessibilityLabel("Drag to resize")
                }
            }
            .simultaneousGesture(TapGesture().onEnded { if editable { onSelect() } })
            .contextMenu {
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .allowsHitTesting(editable)
            .offset(x: o.x + drag.width, y: o.y + drag.height)
    }
}

// MARK: - Inspector bar

struct ObjectInspector: View {
    @Binding var o: PageObject
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Label(o.kind.title, systemImage: o.kind.icon).font(.headline)
                controls
                Divider().frame(height: 28)
                Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                    .accessibilityLabel("Duplicate")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .accessibilityLabel("Delete")
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .frame(maxWidth: 900)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var inkColor: some View {
        ColorPicker("Colour", selection: Binding(get: { Color(hex: o.colorHex) }, set: { o.colorHex = $0.hex }), supportsOpacity: false)
            .labelsHidden()
    }

    private var sizeStepper: some View {
        Stepper("Size \(Int(o.fontSize))", value: $o.fontSize, in: 10...72, step: 2).fixedSize()
    }

    private var widthStepper: some View {
        Stepper("Line \(Int(o.lineWidth))", value: $o.lineWidth, in: 1...14).fixedSize()
    }

    @ViewBuilder
    private var controls: some View {
        switch o.kind {
        case .text:
            Picker("Font", selection: $o.design) {
                ForEach(TextDesign.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            sizeStepper
            Toggle(isOn: $o.bold) { Image(systemName: "bold") }.toggleStyle(.button)
            Toggle(isOn: $o.italic) { Image(systemName: "italic") }.toggleStyle(.button)
            Picker("List", selection: $o.list) {
                ForEach(ListStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            inkColor
        case .line, .arrow:
            inkColor
            widthStepper
        case .rectangle, .ellipse, .triangle, .star:
            inkColor
            widthStepper
            Toggle("Fill", isOn: Binding(
                get: { o.fillHex != nil },
                set: { o.fillHex = $0 ? (o.fillHex ?? "#BFD3FF") : nil }
            ))
            .fixedSize()
            if let fill = o.fillHex {
                ColorPicker("Fill colour", selection: Binding(get: { Color(hex: fill) }, set: { o.fillHex = $0.hex }), supportsOpacity: false)
                    .labelsHidden()
            }
        case .sticky:
            ColorPicker("Paper", selection: Binding(get: { Color(hex: o.fillHex ?? "#FFE98A") }, set: { o.fillHex = $0.hex }), supportsOpacity: false)
                .labelsHidden()
            sizeStepper
            inkColor
        case .checklist:
            inkColor
            sizeStepper
            Button("Add item") { o.items.append(CheckItem()) }
            Button("Remove last") { if !o.items.isEmpty { o.items.removeLast() } }
        case .table:
            inkColor
            sizeStepper
            Button("+ Row") { o.cells.append(Array(repeating: "", count: o.cells.first?.count ?? 3)) }
            Button("− Row") { if o.cells.count > 1 { o.cells.removeLast() } }
            Button("+ Column") { o.cells = o.cells.map { $0 + [""] } }
            Button("− Column") { if (o.cells.first?.count ?? 0) > 1 { o.cells = o.cells.map { Array($0.dropLast()) } } }
        case .stamp:
            TextField("Stamp text", text: $o.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            inkColor
            sizeStepper
        }
    }
}
