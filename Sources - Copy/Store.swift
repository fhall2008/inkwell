import SwiftUI

enum Paths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Inkwell", isDirectory: true)
        for sub in ["notes", "images"] {
            try? FileManager.default.createDirectory(at: url.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return url
    }()
    static var notes: URL { root.appendingPathComponent("notes", isDirectory: true) }
    static var images: URL { root.appendingPathComponent("images", isDirectory: true) }
    static var meta: URL { root.appendingPathComponent("meta.json") }
}

enum ImageCache {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ file: String) -> UIImage? {
        if let hit = cache.object(forKey: file as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: Paths.images.appendingPathComponent(file).path) else { return nil }
        cache.setObject(img, forKey: file as NSString)
        return img
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var folders: [Folder] = []
    @Published var notes: [Note] = []
    @Published var customTemplates: [CustomTemplate] = []

    private let io = DispatchQueue(label: "inkwell.io", qos: .utility)
    private struct Meta: Codable {
        var folders: [Folder]
        var customTemplates: [CustomTemplate]
    }

    init() { load() }

    // MARK: Persistence

    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: Paths.meta), let meta = try? decoder.decode(Meta.self, from: data) {
            folders = meta.folders
            customTemplates = meta.customTemplates
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.notes, includingPropertiesForKeys: nil)) ?? []
        notes = files.filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Note.self, from: $0) } }
        if folders.isEmpty && notes.isEmpty {
            folders = ["Meetings", "Sketches", "Study"].map { Folder(name: $0) }
            saveMeta()
        }
    }

    private func saveMeta() {
        let meta = Meta(folders: folders, customTemplates: customTemplates)
        io.async { try? JSONEncoder().encode(meta).write(to: Paths.meta, options: .atomic) }
    }

    private func write(_ note: Note) {
        let url = Paths.notes.appendingPathComponent("\(note.id.uuidString).json")
        io.async { try? JSONEncoder().encode(note).write(to: url, options: .atomic) }
    }

    // MARK: Notes

    func update(_ note: Note) {
        var note = note
        note.modified = Date()
        if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note } else { notes.append(note) }
        write(note)
    }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func addNote(template: TemplateKind, folder: UUID?, drawing: Data? = nil) -> Note {
        var note = Note(folderID: folder, template: template)
        if let drawing { note.pages[0].drawing = drawing }
        update(note)
        return note
    }

    func duplicate(_ note: Note) {
        var copy = note
        copy.id = UUID()
        copy.title += " copy"
        update(copy)
    }

    func move(_ note: Note, to folder: UUID?) {
        var n = note
        n.folderID = folder
        update(n)
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        let url = Paths.notes.appendingPathComponent("\(note.id.uuidString).json")
        io.async { try? FileManager.default.removeItem(at: url) }
        let stillUsed = notes.reduce(into: Set<String>()) { $0.formUnion($1.imageFiles) }
        for file in note.imageFiles where !stillUsed.contains(file) {
            try? FileManager.default.removeItem(at: Paths.images.appendingPathComponent(file))
        }
    }

    // MARK: Folders

    func addFolder(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        folders.append(Folder(name: trimmed))
        saveMeta()
    }

    func rename(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = folders.firstIndex(of: folder) else { return }
        folders[i].name = trimmed
        saveMeta()
    }

    func delete(_ folder: Folder) {
        for note in notes where note.folderID == folder.id { move(note, to: nil) }
        folders.removeAll { $0.id == folder.id }
        saveMeta()
    }

    // MARK: Templates

    func saveTemplate(name: String, from note: Note, page: NotePage) {
        customTemplates.append(CustomTemplate(name: name, base: note.template, drawing: page.drawing))
        saveMeta()
    }

    func delete(_ template: CustomTemplate) {
        customTemplates.removeAll { $0.id == template.id }
        saveMeta()
    }

    // MARK: Images and backups

    func saveImage(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 2000
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do { try data.write(to: Paths.images.appendingPathComponent(name)) } catch { return nil }
        return name
    }

    /// Imports a PDF as a new note, one page per PDF page, ready to annotate.
    func importPDF(from url: URL, folder: UUID?) async throws -> Note {
        let result = try await Task.detached(priority: .userInitiated) { try PDFImporter.pages(from: url) }.value
        var note = Note(folderID: folder, template: .blank)
        note.title = result.title
        note.pages = result.pages
        update(note)
        return note
    }

    func importBackup(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var backup = try JSONDecoder().decode(NoteBackup.self, from: Data(contentsOf: url))
        for (name, data) in backup.images {
            try data.write(to: Paths.images.appendingPathComponent(name))
        }
        backup.note.id = UUID()
        update(backup.note)
    }
}
