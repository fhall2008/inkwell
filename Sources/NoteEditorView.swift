import SwiftUI
import PhotosUI

struct NoteEditorView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note
    @State private var activePageID: UUID?
    @State private var moveImages = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showExport = false
    @State private var showTemplateMenu = false
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var saveTask: Task<Void, Never>?

    init(note: Note) { _note = State(initialValue: note) }

    private var pageSize: CGSize { PageRenderer.pageSize }
    private var hasImages: Bool { note.pages.contains { !$0.images.isEmpty } }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let scale = min(1, (geo.size.width - 40) / pageSize.width)
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach($note.pages) { $page in
                            PageView(
                                page: $page,
                                template: note.template,
                                moveImages: moveImages,
                                onActivate: { activePageID = page.id },
                                onChange: scheduleSave
                            )
                            .frame(width: pageSize.width, height: pageSize.height)
                            .scaleEffect(scale, anchor: .top)
                            .frame(width: pageSize.width * scale, height: pageSize.height * scale)
                        }
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(red: 0.914, green: 0.898, blue: 0.859))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showExport) { ExportSheet(note: note) }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onImage: insert).ignoresSafeArea() }
        .confirmationDialog("Change template", isPresented: $showTemplateMenu) {
            ForEach(TemplateKind.allCases) { kind in
                Button(kind.title) { note.template = kind; scheduleSave() }
            }
        }
        .alert("Save page as template", isPresented: $showSaveTemplate) {
            TextField("Template name", text: $templateName)
            Button("Save") { saveAsTemplate() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    insert(image)
                }
                photoItem = nil
            }
        }
        .onDisappear {
            saveTask?.cancel()
            store.update(note)
            InkSession.shared.hide()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { saveTask?.cancel(); store.update(note); dismiss() } label: {
                Label("Library", systemImage: "chevron.left")
            }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                TextField("Title", text: $note.title)
                    .font(.system(.headline, design: .serif))
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
                    .onChange(of: note.title) { scheduleSave() }
                Text("\(note.template.title) · \(note.pages.count) page\(note.pages.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { InkSession.shared.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .accessibilityLabel("Undo")
            Button { InkSession.shared.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .accessibilityLabel("Redo")

            PhotosPicker(selection: $photoItem, matching: .images) { Image(systemName: "photo") }
                .accessibilityLabel("Insert photo from library")
            Button { showCamera = true } label: { Image(systemName: "camera") }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityLabel("Take photo")
            if hasImages {
                Toggle(isOn: $moveImages) { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Move and resize images")
            }

            Menu {
                Button("Add page", systemImage: "plus.square") {
                    note.pages.append(NotePage())
                    scheduleSave()
                }
                Button("Change template", systemImage: "square.grid.2x2") { showTemplateMenu = true }
                Button("Save page as template", systemImage: "square.and.arrow.down") {
                    templateName = ""
                    showSaveTemplate = true
                }
                Button("Delete page", systemImage: "trash", role: .destructive) { deleteActivePage() }
                    .disabled(note.pages.count < 2)
            } label: { Image(systemName: "ellipsis.circle") }

            Button("Export") { saveTask?.cancel(); store.update(note); showExport = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Actions

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            store.update(note)
        }
    }

    private func activeIndex() -> Int {
        note.pages.firstIndex { $0.id == activePageID } ?? 0
    }

    private func insert(_ image: UIImage) {
        guard let file = store.saveImage(image) else { return }
        let w = min(320, Double(image.size.width))
        let h = w * Double(image.size.height / image.size.width)
        let placed = PlacedImage(file: file, x: (pageSize.width - w) / 2, y: 200, width: w, height: h)
        note.pages[activeIndex()].images.append(placed)
        moveImages = true   // let the user position it straight away
        scheduleSave()
    }

    private func deleteActivePage() {
        guard note.pages.count > 1 else { return }
        note.pages.remove(at: activeIndex())
        activePageID = nil
        scheduleSave()
    }

    private func saveAsTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.saveTemplate(name: name, from: note, page: note.pages[activeIndex()])
    }
}

// MARK: - Page

struct PageView: View {
    @Binding var page: NotePage
    let template: TemplateKind
    let moveImages: Bool
    var onActivate: () -> Void
    var onChange: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: template.image).resizable()
            ForEach($page.images) { $placed in
                PlacedImageView(
                    placed: $placed,
                    editable: moveImages,
                    onDelete: {
                        page.images.removeAll { $0.id == placed.id }
                        onChange()
                    },
                    onChange: onChange
                )
            }
            InkCanvas(data: $page.drawing, allowsInput: !moveImages, onActivate: onActivate, onChange: onChange)
        }
        .coordinateSpace(name: "page")
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
}

struct PlacedImageView: View {
    @Binding var placed: PlacedImage
    let editable: Bool
    var onDelete: () -> Void
    var onChange: () -> Void

    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1

    var body: some View {
        let w = placed.width * pinch
        let h = placed.height * pinch
        Group {
            if let ui = ImageCache.image(placed.file) {
                Image(uiImage: ui).resizable().scaledToFit()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: w, height: h)
        .overlay {
            if editable { Rectangle().stroke(Theme.accent, lineWidth: 2) }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(coordinateSpace: .named("page"))
                .onChanged { drag = $0.translation }
                .onEnded {
                    placed.x += $0.translation.width
                    placed.y += $0.translation.height
                    drag = .zero
                    onChange()
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { pinch = $0.magnification }
                .onEnded {
                    let m = $0.magnification
                    placed.x -= placed.width * (m - 1) / 2
                    placed.y -= placed.height * (m - 1) / 2
                    placed.width *= m
                    placed.height *= m
                    pinch = 1
                    onChange()
                }
        )
        .contextMenu {
            Button("Delete image", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .allowsHitTesting(editable)
        .position(x: placed.x + placed.width / 2 + drag.width, y: placed.y + placed.height / 2 + drag.height)
    }
}
