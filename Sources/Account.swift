import Foundation

/// Who is signed in, and the steps for signing in, creating an account and recovering one.
/// The password both signs in and unlocks the notes; the server only ever receives a hash of the sign-in half.
@MainActor
final class AccountManager: ObservableObject {
    enum State { case signedOut, signedIn }

    struct PendingReset {
        let api: SyncAPI
        let session: SessionResponse
        let envelope: SyncCrypto.Envelope
        let version: Int
        let encKey: Data
    }

    private struct SavedSession: Codable {
        let token: String
        let expires: Double
        let user: SyncUser
        let server: String
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var user: SyncUser?
    @Published var serverURL: String
    /// Set after creating an account, resetting or making a new key. The screen shows it once.
    @Published var pendingRecoveryKey: String?
    /// Set when a password reset was accepted but the recovery key did not unlock the notes yet.
    @Published private(set) var pendingReset: PendingReset?
    @Published var notice: String?

    private(set) var api: SyncAPI?
    private(set) var master: Data?
    var email: String { user?.email ?? "" }

    /// Called when an account becomes active or is closed. The sync engine hooks in here.
    var onSignedIn: ((SyncAPI, Data, SyncUser) -> Void)?
    var onSignedOut: (() -> Void)?

    private static let minimumPassword = 10
    private static let serverKey = "inkwell.serverURL"
    private static let sessionKey = "session"
    private static let masterKey = "master"

    init() {
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "InkwellServerURL") as? String) ?? ""
        serverURL = UserDefaults.standard.string(forKey: Self.serverKey) ?? bundled
    }

    /// Reopens the saved session, if there is one. Called once the sync engine is listening.
    func restore() {
        guard
            let sessionData = Keychain.get(Self.sessionKey),
            let master = Keychain.get(Self.masterKey),
            let saved = try? JSONDecoder().decode(SavedSession.self, from: sessionData),
            saved.expires / 1000 > Date().timeIntervalSince1970,
            let api = SyncAPI(address: saved.server, token: saved.token)
        else { return }
        activate(api: api, master: master, user: saved.user, expires: saved.expires, save: false)
    }

    // MARK: Signing in

    func signIn(email: String, password: String) async throws {
        let api = try makeAPI()
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pre = try await api.prelogin(email: address)
        let stretched = try await Self.stretched(password: password, salt: pre.salt, iterations: pre.iterations)
        let session = try await api.login(email: address, loginKey: stretched.loginKey)
        api.token = session.token

        if let found = try await fetchEnvelope(api) {
            let master = try SyncCrypto.unwrap(found.envelope, password: stretched.encKey)
            activate(api: api, master: master, user: session.user, expires: session.expires, save: true)
        } else {
            // An account with no key yet, for example after an interrupted sign-up.
            let made = try SyncCrypto.createEnvelope(encKey: stretched.encKey)
            try await putEnvelope(api, made.envelope, version: nil)
            pendingRecoveryKey = made.recoveryKey
            activate(api: api, master: made.master, user: session.user, expires: session.expires, save: true)
        }
    }

    func register(invite: String, email: String, password: String, confirm: String) async throws {
        try Self.checkPassword(password, confirm: confirm)
        let api = try makeAPI()
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pre = try await api.prelogin(email: address)
        let salt = SyncCrypto.newSalt()
        let stretched = try await Self.stretched(password: password, salt: salt, iterations: pre.iterations)
        let made = try SyncCrypto.createEnvelope(encKey: stretched.encKey)
        let session = try await api.register(invite: invite.trimmingCharacters(in: .whitespaces), email: address,
                                             salt: salt, loginKey: stretched.loginKey)
        api.token = session.token
        try await putEnvelope(api, made.envelope, version: nil)
        pendingRecoveryKey = made.recoveryKey
        activate(api: api, master: made.master, user: session.user, expires: session.expires, save: true)
    }

    // MARK: Forgotten password

    /// Uses a reset code from the administrator, then the recovery key to re-open the notes under a new password.
    func resetPassword(email: String, code: String, recoveryKey: String, newPassword: String, confirm: String) async throws {
        try Self.checkPassword(newPassword, confirm: confirm)
        _ = try SyncCrypto.decodeRecoveryKey(recoveryKey)   // check the format before the code is used up
        let api = try makeAPI()
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pre = try await api.prelogin(email: address)
        let salt = SyncCrypto.newSalt()
        let stretched = try await Self.stretched(password: newPassword, salt: salt, iterations: pre.iterations)
        let session = try await api.reset(invite: code.trimmingCharacters(in: .whitespaces), email: address,
                                          salt: salt, loginKey: stretched.loginKey)
        api.token = session.token
        guard let found = try await fetchEnvelope(api) else { throw SyncCrypto.CryptoError.corrupt }
        pendingReset = PendingReset(api: api, session: session, envelope: found.envelope, version: found.version, encKey: stretched.encKey)
        try await completeReset(recoveryKey: recoveryKey)
    }

    /// The reset code is already used up, so a wrong recovery key can be retried without it.
    func completeReset(recoveryKey: String) async throws {
        guard let pending = pendingReset else { return }
        let master = try SyncCrypto.unwrap(pending.envelope, recoveryKey: recoveryKey)
        let envelope = try SyncCrypto.rewrap(pending.envelope, master: master, newEncKey: pending.encKey)
        try await putEnvelope(pending.api, envelope, version: pending.version)
        pendingReset = nil
        activate(api: pending.api, master: master, user: pending.session.user, expires: pending.session.expires, save: true)
    }

    func cancelReset() { pendingReset = nil }

    // MARK: Account changes

    func changePassword(current: String, new: String, confirm: String) async throws {
        try Self.checkPassword(new, confirm: confirm)
        guard let api, let master else { return }
        let pre = try await api.prelogin(email: email)
        let old = try await Self.stretched(password: current, salt: pre.salt, iterations: pre.iterations)
        let salt = SyncCrypto.newSalt()
        let next = try await Self.stretched(password: new, salt: salt, iterations: pre.iterations)
        guard let found = try await fetchEnvelope(api) else { throw SyncCrypto.CryptoError.corrupt }
        // Keep both passwords able to unlock until the change has gone through, in case the connection drops.
        let pending = try SyncCrypto.addPending(found.envelope, master: master, newEncKey: next.encKey)
        let first = try await putEnvelopeReturningVersion(api, pending, version: found.version)
        try await api.changePassword(currentLoginKey: old.loginKey, newLoginKey: next.loginKey, newSalt: salt)
        let final = try SyncCrypto.rewrap(pending, master: master, newEncKey: next.encKey)
        try await putEnvelope(api, final, version: first)
    }

    func makeNewRecoveryKey() async throws {
        guard let api, let master else { return }
        guard let found = try await fetchEnvelope(api) else { throw SyncCrypto.CryptoError.corrupt }
        let (envelope, key) = try SyncCrypto.replaceRecovery(found.envelope, master: master)
        try await putEnvelope(api, envelope, version: found.version)
        pendingRecoveryKey = key
    }

    func signOut(message: String? = nil) {
        let old = api
        Task { await old?.logout() }
        Keychain.delete(Self.sessionKey)
        Keychain.delete(Self.masterKey)
        api = nil
        master = nil
        user = nil
        state = .signedOut
        notice = message
        onSignedOut?()
    }

    // MARK: Helpers

    /// Stretching the password takes about a second, so it runs off the main thread to keep the screen responsive.
    private static func stretched(password: String, salt: String, iterations: Int) async throws -> SyncCrypto.Stretched {
        try await Task.detached(priority: .userInitiated) {
            try SyncCrypto.stretch(password: password, salt: salt, iterations: iterations)
        }.value
    }

    private func activate(api: SyncAPI, master: Data, user: SyncUser, expires: Double, save: Bool) {
        self.api = api
        self.master = master
        self.user = user
        state = .signedIn
        UserDefaults.standard.set(api.base, forKey: Self.serverKey)
        serverURL = api.base
        if save {
            let saved = SavedSession(token: api.token ?? "", expires: expires, user: user, server: api.base)
            if let data = try? JSONEncoder().encode(saved) { Keychain.set(data, for: Self.sessionKey) }
            Keychain.set(master, for: Self.masterKey)
        }
        onSignedIn?(api, master, user)
    }

    private func makeAPI() throws -> SyncAPI {
        guard let api = SyncAPI(address: serverURL) else { throw SyncError.badAddress }
        return api
    }

    private static func checkPassword(_ password: String, confirm: String) throws {
        guard password.count >= minimumPassword else {
            throw SyncError.offline("Use a password of at least \(minimumPassword) characters. A few random words works well.")
        }
        guard password == confirm else { throw SyncError.offline("The two passwords do not match.") }
    }

    private func fetchEnvelope(_ api: SyncAPI) async throws -> (envelope: SyncCrypto.Envelope, version: Int)? {
        do {
            let (data, version) = try await api.getBlob("envelope")
            return (try JSONDecoder().decode(SyncCrypto.Envelope.self, from: data), version)
        } catch let error as SyncError where error.isNotFound {
            return nil
        }
    }

    private func putEnvelope(_ api: SyncAPI, _ envelope: SyncCrypto.Envelope, version: Int?) async throws {
        _ = try await putEnvelopeReturningVersion(api, envelope, version: version)
    }

    private func putEnvelopeReturningVersion(_ api: SyncAPI, _ envelope: SyncCrypto.Envelope, version: Int?) async throws -> Int {
        let body = try JSONEncoder().encode(envelope)
        return try await api.putBlob("envelope", kind: "envelope", body: body, baseVersion: version).version
    }
}
