import SwiftUI
import PhotosUI

struct NoteEditorView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note
    @State private var activePageID: UUID?
    @State private var editMode = false
    @State private var selectedID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showExport = false
    @State private var showPages = false
    @State private var showTemplateMenu = false
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var jumpTo: UUID?
    @State private var alertText: String?
    @State private var saveTask: Task<Void, Never>?
    @StateObject private var dictation = Dictation()

    private static let stamps = ["APPROVED", "DRAFT", "DONE", "URGENT", "CONFIDENTIAL", "REVIEWED"]

    init(note: Note) { _note = State(initialValue: note) }

    private var pageSize: CGSize { PageRenderer.pageSize }
    private var hasObjects: Bool { note.pages.contains { !$0.images.isEmpty || !$0.objects.isEmpty } }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let scale = min(1, (geo.size.width - 40) / pageSize.width)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            ForEach($note.pages) { $page in
                                PageView(
                                    page: $page,
                                    template: note.template,
                                    editMode: editMode,
                                    selectedID: selectedID,
                                    onSelect: { selectedID = $0 },
                                    onActivate: { activePageID = page.id },
                                    onChange: scheduleSave
                                )
                                .frame(width: pageSize.width, height: pageSize.height)
                                .scaleEffect(scale, anchor: .top)
                                .frame(width: pageSize.width * scale, height: pageSize.height * scale)
                                .id(page.id)
                            }
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: jumpTo) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                        jumpTo = nil
                    }
                }
            }
            .background(Color(red: 0.914, green: 0.898, blue: 0.859))
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    dictationBar
                    inspector
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showExport) { ExportSheet(note: note) }
        .sheet(isPresented: $showPages) {
            PageManagerSheet(note: $note, onJump: { jumpTo = $0 }, onChange: scheduleSave)
        }
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
        .alert("Inkwell", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK") {}
        } message: { Text(alertText ?? "") }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    insert(image)
                }
                photoItem = nil
            }
        }
        .onChange(of: editMode) { _, on in if !on { selectedID = nil } }
        .onDisappear {
            saveTask?.cancel()
            store.update(note)
            InkSession.shared.hide()
            dictation.cancel()
        }
    }

    // MARK: Toolbar

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

            Menu {
                Button("Text box", systemImage: ObjectKind.text.icon) { addObject(.text) }
                Menu("Shapes", systemImage: "square.on.circle") {
                    ForEach(ObjectKind.shapes) { kind in
                        Button(kind.title, systemImage: kind.icon) { addObject(kind) }
                    }
                }
                Button("Sticky note", systemImage: ObjectKind.sticky.icon) { addObject(.sticky) }
                Button("Checklist", systemImage: ObjectKind.checklist.icon) { addObject(.checklist) }
                Button("Table", systemImage: ObjectKind.table.icon) { addObject(.table) }
                Menu("Stamp", systemImage: ObjectKind.stamp.icon) {
                    ForEach(Self.stamps, id: \.self) { s in Button(s) { addObject(.stamp, text: s) } }
                    Button(Date.now.formatted(date: .abbreviated, time: .omitted)) {
                        addObject(.stamp, text: Date.now.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            } label: { Image(systemName: "plus.square.on.square") }
                .accessibilityLabel("Insert")

            Button {
                if dictation.isListening { dictation.cancel() } else { dictation.start() }
            } label: { Image(systemName: dictation.isListening ? "mic.fill" : "mic") }
                .accessibilityLabel("Dictate text")

            if hasObjects {
                Toggle(isOn: $editMode) { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Edit images and objects")
            }

            Menu {
                Button("Pages", systemImage: "square.stack") { showPages = true }
                Button("Add page", systemImage: "plus.square") {
                    note.pages.append(NotePage())
                    scheduleSave()
                }
                Button("Handwriting to text", systemImage: "text.viewfinder") { convertHandwriting() }
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

    // MARK: Bottom bars

    @ViewBuilder
    private var inspector: some View {
        if editMode, let id = selectedID, let current = findObject(id) {
            ObjectInspector(
                o: Binding(get: { findObject(id) ?? current }, set: { setObject($0) }),
                onDuplicate: { duplicateObject(id) },
                onDelete: { deleteObject(id) }
            )
        }
    }

    @ViewBuilder
    private var dictationBar: some View {
        if dictation.isListening || dictation.errorText != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: dictation.isListening ? "waveform" : "exclamationmark.triangle")
                    Text(dictation.isListening ? "Listening…" : "Dictation").font(.headline)
                    Spacer()
                }
                Text(dictation.errorText ?? (dictation.transcript.isEmpty ? "Start speaking" : dictation.transcript))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(dictation.transcript.isEmpty ? .secondary : .primary)
                HStack {
                    Button(dictation.isListening ? "Cancel" : "OK", role: .cancel) { dictation.cancel() }
                    Spacer()
                    if dictation.isListening {
                        Button("Insert as text", action: finishDictation).buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(20)
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            store.update(note)
        }
    }

    // MARK: Pages

    private func activeIndex() -> Int {
        note.pages.firstIndex { $0.id == activePageID } ?? 0
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

    // MARK: Images

    private func insert(_ image: UIImage) {
        guard let file = store.saveImage(image) else { return }
        let w = min(320, Double(image.size.width))
        let h = w * Double(image.size.height / image.size.width)
        let placed = PlacedImage(file: file, x: (pageSize.width - w) / 2, y: 200, width: w, height: h)
        note.pages[activeIndex()].images.append(placed)
        editMode = true   // let the user position it straight away
        scheduleSave()
    }

    // MARK: Objects

    private func addObject(_ kind: ObjectKind, text: String = "") {
        var object = PageObject.make(kind, text: text)
        let page = activeIndex()
        let offset = Double(note.pages[page].objects.count % 8) * 36
        object.x += offset
        object.y += offset
        note.pages[page].objects.append(object)
        editMode = true
        selectedID = object.id
        scheduleSave()
    }

    private func findObject(_ id: UUID) -> PageObject? {
        for page in note.pages {
            if let o = page.objects.first(where: { $0.id == id }) { return o }
        }
        return nil
    }

    private func setObject(_ object: PageObject) {
        for p in note.pages.indices {
            if let i = note.pages[p].objects.firstIndex(where: { $0.id == object.id }) {
                note.pages[p].objects[i] = object
                scheduleSave()
                return
            }
        }
    }

    private func duplicateObject(_ id: UUID) {
        for p in note.pages.indices {
            if var copy = note.pages[p].objects.first(where: { $0.id == id }) {
                copy.id = UUID()
                copy.x += 24
                copy.y += 24
                note.pages[p].objects.append(copy)
                selectedID = copy.id
                scheduleSave()
                return
            }
        }
    }

    private func deleteObject(_ id: UUID) {
        for p in note.pages.indices { note.pages[p].objects.removeAll { $0.id == id } }
        selectedID = nil
        scheduleSave()
    }

    // MARK: Speech and handwriting

    private func finishDictation() {
        let text = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        dictation.stop()
        if !text.isEmpty { addObject(.text, text: text) }
    }

    private func convertHandwriting() {
        let snapshot = note
        let page = snapshot.pages[activeIndex()]
        Task {
            let text = await Task.detached(priority: .userInitiated) {
                Recognizer.text(in: PageRenderer.render(note: snapshot, page: page, scale: 2, includeTemplate: false, includeImages: false))
            }.value
            if text.isEmpty {
                alertText = "No handwriting was found on this page."
            } else {
                addObject(.text, text: text)
            }
        }
    }
}

// MARK: - Page

struct PageView: View {
    @Binding var page: NotePage
    let template: TemplateKind
    let editMode: Bool
    let selectedID: UUID?
    var onSelect: (UUID?) -> Void
    var onActivate: () -> Void
    var onChange: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: page.background.flatMap { ImageCache.image($0) } ?? template.image).resizable()
            if editMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(nil) }
            }
            ForEach($page.images) { $placed in
                PlacedImageView(
                    placed: $placed,
                    editable: editMode,
                    onDelete: {
                        page.images.removeAll { $0.id == placed.id }
                        onChange()
                    },
                    onChange: onChange
                )
            }
            ForEach($page.objects) { $object in
                ObjectChrome(
                    o: $object,
                    editable: editMode,
                    selected: selectedID == object.id,
                    onSelect: { onSelect(object.id) },
                    onDuplicate: {
                        var copy = object
                        copy.id = UUID()
                        copy.x += 24
                        copy.y += 24
                        page.objects.append(copy)
                        onSelect(copy.id)
                        onChange()
                    },
                    onDelete: {
                        page.objects.removeAll { $0.id == object.id }
                        onSelect(nil)
                        onChange()
                    },
                    onChange: onChange
                )
            }
            InkCanvas(data: $page.drawing, allowsInput: !editMode, onActivate: onActivate, onChange: onChange)
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
