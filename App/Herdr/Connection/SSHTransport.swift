import Foundation
import HerdrKit

/// SSH-bridged transport to a remote Herdr Unix socket — **scaffold**.
///
/// Herdr exposes no network port: its socket API is a local Unix domain socket
/// (`~/.config/herdr/herdr.sock`). The intended design for reaching it from iOS:
///
///  1. Open an SSH connection to `host` (Citadel / SwiftNIO SSH) using
///     `credential` (private key or password).
///  2. Start an exec channel that bridges stdio to the socket, e.g.
///     `socat - UNIX-CONNECT:<socketPath>` (fallback `nc -U <socketPath>`).
///  3. Write request frames to the channel's stdin via `NDJSON.frame`, and feed
///     the channel's stdout through `LineBuffer` → `IncomingMessage.decode` →
///     `continuation.yield(_:)`. The persistent duplex channel makes live event
///     subscriptions work, exactly like a direct socket connection.
///
/// The connection/auth surface and the `HerdrTransport` plumbing are in place;
/// the Citadel channel bridge (step 2/3) is the agreed follow-up and currently
/// surfaces a friendly `HerdrError.sshNotWired`. See README "SSH transport".
public actor SSHTransport: HerdrTransport {
    private let host: Host
    private let credential: Credential

    private let stream: AsyncStream<IncomingMessage>
    private let continuation: AsyncStream<IncomingMessage>.Continuation
    private var lineBuffer = LineBuffer()

    public init(host: Host, credential: Credential) {
        self.host = host
        self.credential = credential
        var continuation: AsyncStream<IncomingMessage>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
    }

    public nonisolated func messages() -> AsyncStream<IncomingMessage> { stream }

    public func connect() async throws {
        // TODO(ssh): replace this stub with the Citadel-based bridge described
        // above. Validation that the config is at least usable:
        guard !host.hostname.isEmpty, !host.username.isEmpty else {
            throw HerdrError.sshNotWired("This host is missing a hostname or username.")
        }
        throw HerdrError.sshNotWired(
            "SSH isn't wired up yet — connecting to \(host.displayName) lands with the "
            + "Citadel socket bridge. Tap “Open demo workspace” to explore the app now."
        )
    }

    public func send(_ request: RPCRequest) async throws {
        // TODO(ssh): write `try NDJSON.frame(request)` to the exec channel stdin.
        _ = try NDJSON.frame(request)
        throw HerdrError.notConnected
    }

    /// Feed raw channel bytes here once the SSH read loop exists.
    private func ingest(_ bytes: Data) {
        for line in lineBuffer.append(bytes) {
            if let message = try? IncomingMessage.decode(line: line) {
                continuation.yield(message)
            }
        }
    }

    public func disconnect() async {
        continuation.finish()
    }
}
