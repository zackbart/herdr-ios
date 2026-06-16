import Foundation

/// A bidirectional channel to a Herdr socket. Implementations are intentionally
/// dumb: they move framed messages in and out. Request/response correlation and
/// event routing live in `HerdrClient`, so the UI is identical whether the
/// underlying transport is a Mock (in-memory) or a real SSH-bridged socket.
public protocol HerdrTransport: Sendable {
    /// Open the connection (and, for stream transports, start reading).
    func connect() async throws

    /// Write a single request frame to the socket.
    func send(_ request: RPCRequest) async throws

    /// Stream of incoming server messages (responses and events), already
    /// line-split and decoded. Consume this exactly once.
    func messages() -> AsyncStream<IncomingMessage>

    /// Close the connection and finish the `messages()` stream.
    func disconnect() async
}

public enum HerdrError: Error, Sendable {
    case notConnected
    case transportClosed
    case rpc(RPCError)
    /// A human-readable SSH connection problem — bad credentials, unreachable
    /// host, or a socket bridge that couldn't start. Carries a message safe to
    /// show the user.
    case connectionFailed(String)
    /// Legacy friendly-message case retained for transports that are still
    /// stubbed out; prefer `connectionFailed` for real failures.
    case sshNotWired(String)
}
