import SwiftUI

/// Thumbnail list of the note's pages: jump to a page, drag to reorder, duplicate, insert, delete.
struct PageManagerSheet: View {
    @Binding var note: Note
    var onJump: (UUID) -> Void
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(note.pages.enumerated()), id: \.element.id) { index, page in
                    HStack(spacing: 14) {
                        PageThumb(note: note, page: page)
                            .frame(width: 64, height: 90)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Page \(index + 1)").font(.headline)
                            Text("Tap to go to this page").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                        onJump(page.id)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Duplicate") { duplicate(index) }.tint(Theme.accent)
                        Button("Blank after") { insertBlank(after: index) }.tint(.gray)
                    }
                    .contextMenu {
                        Button("Duplicate page", systemImage: "plus.square.on.square") { duplicate(index) }
                        Button("Insert blank page after", systemImage: "doc.badge.plus") { insertBlank(after: index) }
                        Button("Delete page", systemImage: "trash", role: .destructive) { delete(IndexSet(integer: index)) }
                            .disabled(note.pages.count < 2)
                    }
                }
                .onMove { source, destination in
                    note.pages.move(fromOffsets: source, toOffset: destination)
                    onChange()
                }
                .onDelete(perform: delete)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button { insertBlank(after: note.pages.count - 1) } label: { Label("Add page", systemImage: "plus") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func delete(_ offsets: IndexSet) {
        guard note.pages.count > offsets.count else { return }
        note.pages.remove(atOffsets: offsets)
        onChange()
    }

    private func duplicate(_ index: Int) {
        var copy = note.pages[index]
        copy.id = UUID()
        copy.images = copy.images.map { var i = $0; i.id = UUID(); return i }
        copy.objects = copy.objects.map { var o = $0; o.id = UUID(); return o }
        note.pages.insert(copy, at: index + 1)
        onChange()
    }

    private func insertBlank(after index: Int) {
        note.pages.insert(NotePage(), at: min(index + 1, note.pages.count))
        onChange()
    }
}

struct PageThumb: View {
    let note: Note
    let page: NotePage
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image { Image(uiImage: image).resizable().scaledToFit() }
        }
        .overlay(Rectangle().stroke(Theme.hairline))
        .task(id: page.drawing.count &+ page.objects.count &+ page.images.count) {
            let n = note, p = page
            image = await Task.detached(priority: .utility) {
                PageRenderer.render(note: n, page: p, scale: 0.3)
            }.value
        }
    }
}
