import SwiftUI

/// Round colour buttons used by the notebook and whiteboard setup screens.
private struct SwatchRow: View {
    let items: [(name: String, hex: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.hex) { item in
                let selected = selection == item.hex
                Button { selection = item.hex } label: {
                    Circle()
                        .fill(Color(hex: item.hex))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 3 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New notebook

struct NotebookSetupView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID?
    var onCreate: (Note) -> Void

    @State private var title = "My notebook"
    @State private var coverHex = "#2F5BEA"
    @State private var preset: PaperPreset = .a4
    @State private var landscape = false
    @State private var template: TemplateKind = .ruled
    @State private var paperHex = "#FFFFFF"
    @State private var pageCount = 20
    @State private var pageNumbers = true

    private static let pageCounts = [1, 5, 10, 20, 50, 100, 200]

    private var paperSize: CGSize { preset.size(landscape: landscape) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Notebook name", text: $title)
                }

                Section("Cover colour") {
                    SwatchRow(items: PaperColours.cover, selection: $coverHex)
                }

                Section("Paper size") {
                    Picker("Size", selection: $preset) {
                        ForEach(PaperPreset.allCases) { Text("\($0.title)  ·  \($0.detail)").tag($0) }
                    }
                    Picker("Orientation", selection: $landscape) {
                        Text("Portrait").tag(false)
                        Text("Landscape").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Paper style") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(TemplateKind.allCases) { kind in
                                Button { template = kind } label: {
                                    VStack(spacing: 6) {
                                        Image(uiImage: kind.preview(paperHex: paperHex))
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 112, alignment: .top)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(RoundedRectangle(cornerRadius: 6)
                                                .stroke(template == kind ? Theme.accent : Theme.hairline, lineWidth: template == kind ? 3 : 1))
                                        Text(kind.title).font(.caption).lineLimit(1).frame(width: 90)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(template == kind ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    SwatchRow(items: PaperColours.paper, selection: $paperHex)
                    Toggle("Page numbers", isOn: $pageNumbers)
                }

                Section {
                    Picker("Number of pages", selection: $pageCount) {
                        ForEach(Self.pageCounts, id: \.self) { Text("\($0)").tag($0) }
                    }
                } header: {
                    Text("Pages")
                } footer: {
                    Text("You can add, remove and reorder pages whenever you like.")
                }

                Section("Preview") {
                    HStack {
                        Spacer()
                        Image(uiImage: template.image(size: paperSize, paperHex: paperHex))
                            .resizable()
                            .scaledToFit()
                            .frame(height: 220)
                            .overlay(alignment: .leading) { Rectangle().fill(Color(hex: coverHex)).frame(width: 10) }
                            .overlay(Rectangle().stroke(Theme.hairline))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                            .accessibilityHidden(true)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).fontWeight(.semibold) }
            }
        }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        var note = Note()
        note.title = trimmed.isEmpty ? "Notebook" : trimmed
        note.kind = .notebook
        note.folderID = folderID
        note.template = template
        note.pageWidth = paperSize.width
        note.pageHeight = paperSize.height
        note.coverHex = coverHex
        note.paperHex = paperHex
        note.pageNumbers = pageNumbers
        note.pages = (0..<pageCount).map { _ in NotePage() }
        store.update(note)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCreate(note) }
    }
}

// MARK: - New whiteboard

struct WhiteboardSetupView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID?
    var onCreate: (Note) -> Void

    @State private var title = "Whiteboard"
    @State private var size: WhiteboardSize = .medium
    @State private var background: TemplateKind = .blank
    @State private var paperHex = "#FFFFFF"

    private static let backgrounds: [TemplateKind] = [.blank, .grid, .dots]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Whiteboard name", text: $title)
                }

                Section {
                    Picker("Size", selection: $size) {
                        ForEach(WhiteboardSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Size")
                } footer: {
                    Text("\(Int(size.size.width)) × \(Int(size.size.height)) points. A whiteboard is one big page. Pinch to zoom and drag to move around.")
                }

                Section("Background") {
                    Picker("Background", selection: $background) {
                        ForEach(Self.backgrounds) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    SwatchRow(items: PaperColours.paper, selection: $paperHex)
                }

                Section("Preview") {
                    ZStack {
                        Color(hex: paperHex)
                        if let tile = TemplateKind.whiteboardTile(background, paperHex: paperHex) {
                            Image(uiImage: tile).resizable(resizingMode: .tile)
                        }
                    }
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                }
            }
            .navigationTitle("New whiteboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).fontWeight(.semibold) }
            }
        }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        var note = Note()
        note.title = trimmed.isEmpty ? "Whiteboard" : trimmed
        note.kind = .whiteboard
        note.folderID = folderID
        note.template = background
        note.pageWidth = size.size.width
        note.pageHeight = size.size.height
        note.paperHex = paperHex
        note.pageNumbers = false
        note.pages = [NotePage()]
        store.update(note)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCreate(note) }
    }
}
