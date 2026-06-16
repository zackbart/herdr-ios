import Foundation

/// High-level, typed API over a `HerdrTransport`.
///
/// Responsibilities:
///  - generate request ids and correlate replies to the awaiting caller,
///  - demultiplex server-pushed events into a single `events` stream the UI
///    can observe for live status/output updates,
///  - expose ergonomic async methods (`listWorkspaces`, `readPane`, …).
///
/// It is an `actor`, so all id/continuation bookkeeping is serialized without
/// locks.
public actor HerdrClient {
    private let transport: HerdrTransport

    private var pending: [String: CheckedContinuation<RPCResponse, Error>] = [:]
    private var nextID = 0
    private var consumeTask: Task<Void, Never>?

    private let events: AsyncStream<HerdrEvent>
    private let eventsContinuation: AsyncStream<HerdrEvent>.Continuation

    public init(transport: HerdrTransport) {
        self.transport = transport
        var continuation: AsyncStream<HerdrEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.eventsContinuation = continuation
    }

    /// Live stream of domain events. Observe this to react to status/output
    /// changes. Multiple awaits share one underlying stream.
    public var eventStream: AsyncStream<HerdrEvent> { events }

    // MARK: Lifecycle

    public func connect() async throws {
        try await transport.connect()
        let incoming = transport.messages()
        consumeTask = Task { [weak self] in
            for await message in incoming {
                await self?.handle(message)
            }
            await self?.failAllPending(HerdrError.transportClosed)
        }
        // Ask the server to start streaming events. Tolerate servers that don't
        // implement an explicit subscribe.
        _ = try? await call(Method.subscribe)
    }

    public func disconnect() async {
        consumeTask?.cancel()
        await transport.disconnect()
        failAllPending(HerdrError.transportClosed)
        eventsContinuation.finish()
    }

    // MARK: Typed API

    public func ping() async throws {
        _ = try await call(Method.ping)
    }

    public func listWorkspaces() async throws -> [Workspace] {
        let result = try await call(Method.workspaceList)
        if let ws = result["workspaces"] { return try ws.decoded([Workspace].self) }
        return try result.decoded([Workspace].self)
    }

    /// Read recent scrollback for a pane, returned as lines.
    public func readPane(_ pane: PaneID, lines: Int = 200) async throws -> [String] {
        let result = try await call(Method.paneRead, .object([
            "pane": .string(pane.rawValue),
            "source": .string("recent"),
            "lines": .int(lines),
        ]))
        if let arr = result["lines"]?.arrayValue { return arr.compactMap(\.stringValue) }
        if let text = result["text"]?.stringValue {
            return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        return []
    }

    /// Send literal text to a pane without a trailing newline.
    public func sendText(_ text: String, to pane: PaneID) async throws {
        _ = try await call(Method.paneSendText, .object([
            "pane": .string(pane.rawValue),
            "text": .string(text),
        ]))
    }

    /// Send a key press (e.g. `"Enter"`) to a pane.
    public func sendKeys(_ keys: String, to pane: PaneID) async throws {
        _ = try await call(Method.paneSendKeys, .object([
            "pane": .string(pane.rawValue),
            "keys": .string(keys),
        ]))
    }

    /// Convenience: submit a line of input (text + Enter), as the pane view does.
    public func submitLine(_ text: String, to pane: PaneID) async throws {
        try await sendText(text, to: pane)
        try await sendKeys("Enter", to: pane)
    }

    // MARK: Request plumbing

    private func call(_ method: String, _ params: JSONValue = .object([:])) async throws -> JSONValue {
        nextID += 1
        let id = "req_\(nextID)"
        let request = RPCRequest(id: id, method: method, params: params)

        let response: RPCResponse = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await transport.send(request)
                } catch {
                    // Send failed before any reply could arrive.
                    if let waiting = pending.removeValue(forKey: id) {
                        waiting.resume(throwing: error)
                    }
                }
            }
        }

        if let error = response.error { throw HerdrError.rpc(error) }
        return response.result ?? .null
    }

    private func handle(_ message: IncomingMessage) {
        switch message {
        case .response(let response):
            guard let id = response.id, let continuation = pending.removeValue(forKey: id) else { return }
            continuation.resume(returning: response)
        case .event(let event):
            if let domain = HerdrEvent(event) { eventsContinuation.yield(domain) }
        }
    }

    private func failAllPending(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }
}
