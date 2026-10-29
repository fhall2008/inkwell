import Foundation
import CryptoKit
import CommonCrypto

/// Encryption for sync. Mirrors web/js/crypto.js exactly, so the iPad and the web portal read each other's data.
///
///   password --PBKDF2-SHA256--> 64 bytes: first 32 = encKey (stays on the device), last 32 = loginKey (sent to the server)
///   A random master key encrypts every note. It is stored in an "envelope", wrapped by encKey and by a recovery key.
///   A sealed blob is: 12-byte nonce + AES-256-GCM ciphertext + 16-byte tag, with "<kind>:<id>" as authenticated data.
enum SyncCrypto {
    enum CryptoError: LocalizedError {
        case wrongPassword, wrongRecoveryKey, badRecoveryKey(String), corrupt

        var errorDescription: String? {
            switch self {
            case .wrongPassword: "Could not unlock your notes with that password."
            case .wrongRecoveryKey: "That recovery key does not match this account."
            case .badRecoveryKey(let why): why
            case .corrupt: "The encrypted data could not be read."
            }
        }
    }

    // MARK: Encoding

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromB64url(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    static func newSalt() -> String { b64url(randomBytes(16)) }

    // MARK: Password stretching

    struct Stretched {
        let encKey: Data
        let loginKey: String
    }

    static func stretch(password: String, salt: String, iterations: Int) throws -> Stretched {
        guard let saltData = fromB64url(salt) else { throw CryptoError.corrupt }
        let normalized = password.precomposedStringWithCompatibilityMapping   // NFKC, like the web portal
        var derived = [UInt8](repeating: 0, count: 64)
        let status = saltData.withUnsafeBytes { raw -> Int32 in
            let saltPtr = raw.bindMemory(to: UInt8.self).baseAddress!
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                normalized, normalized.utf8.count,
                saltPtr, saltData.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == Int32(kCCSuccess) else { throw CryptoError.corrupt }
        return Stretched(encKey: Data(derived[0..<32]), loginKey: Data(derived[32..<64]).base64EncodedString())
    }

    // MARK: AES-GCM

    static func seal(_ plaintext: Data, key: Data, aad: String) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: Data(aad.utf8))
        guard let combined = box.combined else { throw CryptoError.corrupt }
        return combined
    }

    static func open(_ sealed: Data, key: Data, aad: String) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: sealed)
        return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(aad.utf8))
    }

    static func sealBlob(_ data: Data, key: Data, kind: String, id: String) throws -> Data {
        try seal(data, key: key, aad: "\(kind):\(id)")
    }

    static func openBlob(_ sealed: Data, key: Data, kind: String, id: String) throws -> Data {
        try open(sealed, key: key, aad: "\(kind):\(id)")
    }

    static func sealJSON<T: Encodable>(_ value: T, key: Data, kind: String, id: String) throws -> Data {
        try sealBlob(JSONEncoder().encode(value), key: key, kind: kind, id: id)
    }

    static func openJSON<T: Decodable>(_ type: T.Type, from sealed: Data, key: Data, kind: String, id: String) throws -> T {
        try JSONDecoder().decode(T.self, from: openBlob(sealed, key: key, kind: kind, id: id))
    }

    // MARK: Recovery key text (32 bytes <-> 13 groups of 4 characters)

    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func encodeRecoveryKey(_ bytes: Data) -> String {
        var bits = 0, value = 0
        var out = [Character]()
        for byte in bytes {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
                value &= (1 << bits) - 1
            }
        }
        if bits > 0 { out.append(alphabet[(value << (5 - bits)) & 31]) }
        return stride(from: 0, to: out.count, by: 4)
            .map { String(out[$0..<min($0 + 4, out.count)]) }
            .joined(separator: "-")
    }

    static func decodeRecoveryKey(_ text: String) throws -> Data {
        let clean = text.uppercased().filter { $0.isLetter || $0.isNumber }
        var bits = 0, value = 0
        var out = [UInt8]()
        for ch in clean {
            guard let index = alphabet.firstIndex(of: ch) else {
                throw CryptoError.badRecoveryKey("That recovery key has a character that is not allowed.")
            }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 255))
                bits -= 8
                value &= (1 << bits) - 1
            }
        }
        guard out.count >= 32 else { throw CryptoError.badRecoveryKey("That recovery key is too short.") }
        return Data(out.prefix(32))
    }

    // MARK: Envelope

    struct Envelope: Codable {
        var v = 1
        var pw: String
        var pw2: String?
        var rec: String
    }

    private static let aadPassword = "inkwell-envelope-v1:pw"
    private static let aadRecovery = "inkwell-envelope-v1:rec"

    struct NewKeys {
        let master: Data
        let envelope: Envelope
        let recoveryKey: String
    }

    static func createEnvelope(encKey: Data) throws -> NewKeys {
        let master = randomBytes(32)
        let recovery = randomBytes(32)
        let envelope = Envelope(
            pw: try seal(master, key: encKey, aad: aadPassword).base64EncodedString(),
            rec: try seal(master, key: recovery, aad: aadRecovery).base64EncodedString()
        )
        return NewKeys(master: master, envelope: envelope, recoveryKey: encodeRecoveryKey(recovery))
    }

    /// Tries the current wrap, then the pending one left behind by an interrupted password change.
    static func unwrap(_ envelope: Envelope, password encKey: Data) throws -> Data {
        for wrapped in [envelope.pw, envelope.pw2].compactMap({ $0 }) {
            if let data = Data(base64Encoded: wrapped), let master = try? open(data, key: encKey, aad: aadPassword) {
                return master
            }
        }
        throw CryptoError.wrongPassword
    }

    static func unwrap(_ envelope: Envelope, recoveryKey text: String) throws -> Data {
        let recovery = try decodeRecoveryKey(text)
        guard let data = Data(base64Encoded: envelope.rec), let master = try? open(data, key: recovery, aad: aadRecovery) else {
            throw CryptoError.wrongRecoveryKey
        }
        return master
    }

    /// Step 1 of a password change: keep the old wrap and add one for the new password.
    static func addPending(_ envelope: Envelope, master: Data, newEncKey: Data) throws -> Envelope {
        var e = envelope
        e.pw2 = try seal(master, key: newEncKey, aad: aadPassword).base64EncodedString()
        return e
    }

    /// Makes `newEncKey` the only password wrap.
    static func rewrap(_ envelope: Envelope, master: Data, newEncKey: Data) throws -> Envelope {
        var e = envelope
        e.pw = try seal(master, key: newEncKey, aad: aadPassword).base64EncodedString()
        e.pw2 = nil
        return e
    }

    static func replaceRecovery(_ envelope: Envelope, master: Data) throws -> (Envelope, String) {
        let recovery = randomBytes(32)
        var e = envelope
        e.rec = try seal(master, key: recovery, aad: aadRecovery).base64EncodedString()
        return (e, encodeRecoveryKey(recovery))
    }
}
