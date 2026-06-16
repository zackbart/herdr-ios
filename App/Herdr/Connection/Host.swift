import Foundation

/// How we authenticate the SSH connection to a host.
enum AuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case privateKey
    case password

    var id: String { rawValue }
    var title: String {
        switch self {
        case .privateKey: return "Private key"
        case .password: return "Password"
        }
    }
}

/// A saved SSH connection to a machine running Herdr. Non-secret fields are
/// persisted in `UserDefaults`; the secret (key or password) lives in the
/// Keychain keyed by `id`.
struct Host: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var nickname: String = ""
    var hostname: String = ""
    var port: Int = 22
    var username: String = ""
    var authMethod: AuthMethod = .privateKey
    /// Path to the Herdr socket on the remote host. Default is the primary
    /// session; named sessions live under `~/.config/herdr/sessions/<n>/`.
    var socketPath: String = "~/.config/herdr/herdr.sock"

    var displayName: String {
        nickname.isEmpty ? "\(username)@\(hostname)" : nickname
    }

    var subtitle: String {
        "\(username)@\(hostname):\(port)"
    }
}

/// The secret material for a host, fetched from the Keychain at connect time.
struct Credential: Sendable {
    var password: String?
    var privateKey: String?
    var passphrase: String?
}
