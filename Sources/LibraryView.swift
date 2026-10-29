import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case all
    case folder(UUID)
}

struct OpenNote: Identifiable {
    let id: UUID
}

struct LibraryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var sync: SyncEngine
    @State private var showAccount = false
    @State private var selection: SidebarItem? = .all
    @State private var search = ""
    @State private var showTemplates = false
    @State private var showNotebookSetup = false
    @State private var showWhiteboardSetup = false
    @State private var openNote: OpenNote?
    @State private var showNewFolder = false
    @State private var folderName = ""
    @State private var renaming: Folder?
    @State private var importing = false
    @State private var importError: String?

    private var currentFolder: Folder? {
        if case .folder(let id) = selection { return store.folders.first { $0.id == id } }
        return nil
    }

    private var visibleNotes: [Note] {
        store.notes
            .filter { note in
                if case .folder(let id) = selection { return note.folderID == id }
                return true
            }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.modified > $1.modified }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showAccount) {
            if account.state == .signedIn { AccountView() } else { AuthView() }
        }
        .sheet(isPresented: $showTemplates) {
            TemplatePickerView(folderID: currentFolder?.id) { note in
                openNote = OpenNote(id: note.id)
            }
        }
        .sheet(isPresented: $showNotebookSetup) {
            NotebookSetupView(folderID: currentFolder?.id) { note in openNote = OpenNote(id: note.id) }
        }
        .sheet(isPresented: $showWhiteboardSetup) {
            WhiteboardSetupView(folderID: currentFolder?.id) { note in openNote = OpenNote(id: note.id) }
        }
        .fullScreenCover(item: $openNote) { open in
            if let note = store.note(open.id) {
                NoteEditorView(note: note)
            }
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Name", text: $folderName)
            Button("Create") { store.addFolder(folderName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $folderName)
            Button("Rename") { if let f = renaming { store.rename(f, to: folderName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: { Text(importError ?? "") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .data]) { result in
            guard case .success(let url) = result else { return }
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" || ext == "docx" {
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let note = ext == "pdf"
                            ? try await store.importPDF(from: url, folder: currentFolder?.id)
                            : try await store.importDocx(from: url, folder: currentFolder?.id)
                        openNote = OpenNote(id: note.id)
                    } catch {
                        importError = ext == "pdf" ? "That PDF couldn't be read." : "That Word file couldn't be read. Only .docx files work, not older .doc files."
                    }
                }
            } else {
                do { try store.importBackup(from: url) } catch { importError = "That file is not an Inkwell backup." }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label("All notes", systemImage: "doc.text")
                .badge(store.notes.count)
                .tag(SidebarItem.all)
            Section("Folders") {
                ForEach(store.folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .badge(store.notes.filter { $0.folderID == folder.id }.count)
                        .tag(SidebarItem.folder(folder.id))
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                folderName = folder.name
                                renaming = folder
                            }
                            Button("Delete folder", systemImage: "trash", role: .destructive) {
                                if selection == .folder(folder.id) { selection = .all }
                                store.delete(folder)
                            }
                        }
                }
                Button { folderName = ""; showNewFolder = true } label: {
                    Label("New folder", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Inkwell")
    }

    private var detail: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 20)], spacing: 24) {
                ForEach(visibleNotes) { note in
                    NoteCard(note: note) { openNote = OpenNote(id: note.id) }
                }
            }
            .padding(24)
            if visibleNotes.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No notes yet" : "No matches",
                    systemImage: "pencil.and.scribble",
                    description: Text(search.isEmpty ? "Tap New note to start writing with Apple Pencil." : "Try a different title.")
                )
                .padding(.top, 80)
            }
        }
        .background(Theme.paper)
        .navigationTitle(currentFolder?.name ?? "All notes")
        .searchable(text: $search, prompt: "Search note titles")
        .toolbar {
            ToolbarItem {
                Button { showAccount = true } label: {
                    Label(account.state == .signedIn ? "Sync: \(sync.summary)" : "Sign in to sync", systemImage: sync.icon)
                }
                .accessibilityLabel(account.state == .signedIn ? "Account and sync" : "Sign in to sync")
            }
            ToolbarItem {
                Button { importing = true } label: { Label("Import PDF, Word or backup", systemImage: "square.and.arrow.down") }
            }
            ToolbarItem {
                Menu {
                    Button { showTemplates = true } label: { Label("New note", systemImage: "doc.text") }
                    Button { showNotebookSetup = true } label: { Label("New notebook…", systemImage: "book.closed") }
                    Button { showWhiteboardSetup = true } label: { Label("New whiteboard…", systemImage: "rectangle.and.pencil.and.ellipsis") }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("New note, notebook or whiteboard")
            }
        }
    }
}

struct NoteCard: View {
    @EnvironmentObject private var store: Store
    let note: Note
    let open: () -> Void

    private var folderName: String {
        store.folders.first { $0.id == note.folderID }?.name ?? "No folder"
    }

    private var kindLabel: String {
        switch note.kind {
        case .note: ""
        case .notebook: "Notebook · "
        case .whiteboard: "Whiteboard · "
        }
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(note: note)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(folderName) · \(kindLabel)\(note.modified.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Move to folder", systemImage: "folder") {
                Button("No folder") { store.move(note, to: nil) }
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.move(note, to: folder.id) }
                }
            }
            Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(note) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(note) }
        }
    }
}

struct ThumbnailView: View {
    let note: Note
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(hex: note.paperHex)
            if let image {
                if note.pageWidth > note.pageHeight {
                    // Landscape pages and whiteboards: show the whole thing.
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .overlay(alignment: .leading) {
            // A notebook's cover colour runs down its spine.
            if note.kind == .notebook, let hex = note.coverHex {
                Rectangle().fill(Color(hex: hex)).frame(width: 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if note.kind != .note {
                Image(systemName: note.kind == .whiteboard ? "rectangle.and.pencil.and.ellipsis" : "book.closed.fill")
                    .font(.caption)
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
            }
        }
        .task(id: note.modified) {
            let snapshot = note
            image = await Task.detached(priority: .utility) {
                PageRenderer.render(note: snapshot, page: snapshot.pages[0], scale: 0.5)
            }.value
        }
    }
}
