import Foundation

/// Keeps this iPad's notes and the server in step. Pulls what others changed, pushes what changed here.
/// Everything is encrypted before it leaves the iPad. If the same note was edited on two devices,
/// the newer save wins and the older version stays in the server's history.
@MainActor
final class SyncEngine: ObservableObject {
    enum Status: Equatable {
        case off, idle, syncing, synced(Date), offline(String)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var storage: StatsResponse?
    var onUnauthorized: (() -> Void)?

    private struct State: Codable {
        var userID = ""
        var cursor = 0
        var lastSync = 0.0                       // milliseconds
        var versions: [String: Int] = [:]        // server version known for each object
        var dirtyNotes: Set<String> = []
        var deletedNotes: Set<String> = []
        var foldersDirty = false
        var uploadedImages: Set<String> = []
    }

    private var state = State()
    private var api: SyncAPI?
    private var master: Data?
    private weak var store: Store?
    private var running = false
    private var runAgain = false
    private var debounce: Task<Void, Never>?
    private var poll: Task<Void, Never>?

    private var stateURL: URL { Paths.root.appendingPathComponent("sync.json") }

    // MARK: Wiring

    func attach(store: Store) {
        self.store = store
        store.onNoteSaved = { [weak self] id in self?.noteChanged(id) }
        store.onNoteDeleted = { [weak self] id in self?.noteDeleted(id) }
        store.onFoldersChanged = { [weak self] in self?.foldersChanged() }
    }

    func start(api: SyncAPI, master: Data, user: SyncUser) {
        self.api = api
        self.master = master
        loadState()
        if state.userID != user.id {
            state = State()
            state.userID = user.id
        }
        markUnsynced()
        status = .idle
        syncNow()
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.runSync()
            }
        }
    }

    func stop() {
        debounce?.cancel()
        poll?.cancel()
        api = nil
        master = nil
        storage = nil
        status = .off
    }

    func syncNow() {
        Task { await runSync() }
    }

    // MARK: Change tracking

    private func noteChanged(_ id: UUID) {
        guard api != nil else { return }
        state.dirtyNotes.insert(id.uuidString)
        state.deletedNotes.remove(id.uuidString)
        saveState()
        schedule()
    }

    private func noteDeleted(_ id: UUID) {
        guard api != nil else { return }
        state.dirtyNotes.remove(id.uuidString)
        if state.versions[id.uuidString] != nil { state.deletedNotes.insert(id.uuidString) }
        saveState()
        schedule()
    }

    private func foldersChanged() {
        guard api != nil else { return }
        state.foldersDirty = true
        saveState()
        schedule()
    }

    /// Anything never uploaded, or edited since the last sync (for example while signed out).
    private func markUnsynced() {
        guard let store else { return }
        for note in store.notes
        where state.versions[note.id.uuidString] == nil || note.modified.timeIntervalSince1970 * 1000 > state.lastSync {
            state.dirtyNotes.insert(note.id.uuidString)
        }
        if !store.folders.isEmpty && state.versions["folders"] == nil { state.foldersDirty = true }
        saveState()
    }

    private func schedule() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.runSync()
        }
    }

    // MARK: Running

    func runSync() async {
        guard api != nil, master != nil else { return }
        if running {
            runAgain = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            runAgain = false
            status = .syncing
            do {
                try await pull()
                try await push()
                state.lastSync = Date().timeIntervalSince1970 * 1000
                saveState()
                status = .synced(Date())
                storage = try? await api?.stats()
            } catch {
                handle(error)
                return
            }
        } while runAgain
    }

    private func handle(_ error: Error) {
        if let sync = error as? SyncError, sync.isUnauthorized {
            status = .offline("Signed out")
            onUnauthorized?()
            return
        }
        status = .offline(error.localizedDescription)
    }

    // MARK: Pulling

    private func pull() async throws {
        guard let api, let store else { return }
        var more = true
        while more {
            let page = try await api.changes(since: state.cursor)
            for change in page.changes { try await apply(change, api: api, store: store) }
            state.cursor = page.cursor
            more = page.more
            saveState()
        }
    }

    private func apply(_ change: ChangeItem, api: SyncAPI, store: Store) async throws {
        guard let master else { return }
        switch change.kind {
        case "note":
            if change.deleted == 1 {
                if let id = UUID(uuidString: change.id), !state.dirtyNotes.contains(change.id) { store.removeRemote(id) }
                state.versions[change.id] = change.version
                return
            }
            if (state.versions[change.id] ?? 0) >= change.version { return }
            if state.dirtyNotes.contains(change.id) {
                // Edited here too: keep ours. It is uploaded on top, and the other version stays in history.
                state.versions[change.id] = change.version
                return
            }
            do {
                let (sealed, version) = try await api.getBlob(change.id, version: change.version)
                let wire = try SyncCrypto.openJSON(WireNote.self, from: sealed, key: master, kind: "note", id: change.id)
                await downloadImages(for: wire, api: api, master: master)
                if let note = SyncMapper.note(from: wire) { store.applyRemote(note) }
                state.versions[change.id] = version
            } catch let error as SyncError where !error.isNotFound {
                throw error
            } catch {
                state.versions[change.id] = change.version   // unreadable note: skip it rather than stop syncing
            }

        case "folders":
            if (state.versions["folders"] ?? 0) >= change.version, change.deleted == 0 { return }
            do {
                let (sealed, version) = try await api.getBlob("folders", version: change.version)
                let wire = try SyncCrypto.openJSON(WireFolders.self, from: sealed, key: master, kind: "folders", id: "folders")
                let remote = wire.folders.compactMap { f in UUID(uuidString: f.id).map { Folder(id: $0, name: f.name) } }
                if state.foldersDirty {
                    store.mergeFolders(remote: remote)   // keep both sets; the merged list is uploaded next
                } else {
                    store.applyRemoteFolders(remote)
                }
                state.versions["folders"] = version
            } catch let error as SyncError where !error.isNotFound {
                throw error
            } catch {
                state.versions["folders"] = change.version
            }

        default:
            break   // pictures are fetched with the note that uses them
        }
    }

    private func downloadImages(for wire: WireNote, api: SyncAPI, master: Data) async {
        for blobID in SyncMapper.imageIDs(in: wire) {
            let url = Paths.images.appendingPathComponent(SyncMapper.file(forImageID: blobID))
            if !FileManager.default.fileExists(atPath: url.path) {
                guard
                    let (sealed, _) = try? await api.getBlob(blobID),
                    let bytes = try? SyncCrypto.openBlob(sealed, key: master, kind: "image", id: blobID)
                else { continue }
                try? bytes.write(to: url, options: .atomic)
            }
            state.uploadedImages.insert(blobID)
        }
    }

    // MARK: Pushing

    private func push() async throws {
        guard let api, let master, let store else { return }

        for id in Array(state.deletedNotes) {
            do {
                try await api.deleteBlob(id)
            } catch let error as SyncError where error.isNotFound {
                // already gone
            }
            state.deletedNotes.remove(id)
            saveState()
        }

        if state.foldersDirty {
            state.foldersDirty = false
            do {
                let wire = WireFolders(folders: store.folders.map { WireFolder(id: $0.id.uuidString, name: $0.name) })
                let sealed = try SyncCrypto.sealJSON(wire, key: master, kind: "folders", id: "folders")
                let result = try await api.putBlob("folders", kind: "folders", body: sealed, baseVersion: state.versions["folders"])
                state.versions["folders"] = result.version
                saveState()
            } catch {
                state.foldersDirty = true
                throw error
            }
        }

        for id in Array(state.dirtyNotes) {
            guard let uuid = UUID(uuidString: id), let note = store.note(uuid) else {
                state.dirtyNotes.remove(id)
                continue
            }
            state.dirtyNotes.remove(id)   // edits made while this uploads mark it dirty again
            do {
                try await uploadImages(for: note, api: api, master: master)
                let sealed = try SyncCrypto.sealJSON(SyncMapper.wire(from: note), key: master, kind: "note", id: id)
                let result = try await api.putBlob(id, kind: "note", body: sealed, baseVersion: state.versions[id])
                state.versions[id] = result.version
                saveState()
            } catch {
                state.dirtyNotes.insert(id)
                throw error
            }
        }
    }

    private func uploadImages(for note: Note, api: SyncAPI, master: Data) async throws {
        for file in note.imageFiles {
            let blobID = SyncMapper.imageID(forFile: file)
            guard !state.uploadedImages.contains(blobID) else { continue }
            guard let bytes = try? Data(contentsOf: Paths.images.appendingPathComponent(file)) else { continue }
            let sealed = try SyncCrypto.sealBlob(bytes, key: master, kind: "image", id: blobID)
            _ = try await api.putBlob(blobID, kind: "image", body: sealed, baseVersion: nil)
            state.uploadedImages.insert(blobID)
        }
    }

    // MARK: Saved state

    private func loadState() {
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        }
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    // MARK: Text for the screens

    var summary: String {
        switch status {
        case .off: "Not signed in"
        case .idle: "Waiting to sync"
        case .syncing: "Syncing…"
        case .synced(let date): "Up to date, " + date.formatted(.relative(presentation: .named))
        case .offline(let message): message
        }
    }

    var icon: String {
        switch status {
        case .off: "icloud.slash"
        case .idle, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .offline: "exclamationmark.icloud"
        }
    }
}
