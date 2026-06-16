import Foundation

/// In-memory `HerdrTransport` that answers requests from sample data and emits a
/// trickle of live status/output events, so the app behaves like it's connected
/// to a busy Herdr server. This drives all UI development and is the default
/// transport the app boots on.
public actor MockTransport: HerdrTransport {
    private let stream: AsyncStream<IncomingMessage>
    private let continuation: AsyncStream<IncomingMessage>.Continuation

    private let workspaces: [Workspace]
    private let output: [PaneID: [String]]
    private let agentPaneIDs: [PaneID]
    private let tickInterval: Duration

    private var tickTask: Task<Void, Never>?

    public init(
        workspaces: [Workspace] = MockData.workspaces,
        output: [PaneID: [String]] = MockData.output,
        tickInterval: Duration = .seconds(3)
    ) {
        var continuation: AsyncStream<IncomingMessage>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
        self.workspaces = workspaces
        self.output = output
        self.agentPaneIDs = workspaces.flatMap(\.agentPanes).map(\.id)
        self.tickInterval = tickInterval
    }

    public nonisolated func messages() -> AsyncStream<IncomingMessage> { stream }

    public func connect() async throws {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            guard let interval = await self?.tickInterval else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.tick()
            }
        }
    }

    public func disconnect() async {
        tickTask?.cancel()
        tickTask = nil
        continuation.finish()
    }

    public func send(_ request: RPCRequest) async throws {
        continuation.yield(.response(makeResponse(for: request)))
    }

    /// Inject an arbitrary event (used by tests to drive the client deterministically).
    public func emit(_ event: RPCEvent) {
        continuation.yield(.event(event))
    }

    // MARK: Simulation

    private func tick() {
        guard let pane = agentPaneIDs.randomElement() else { return }
        let status = AgentStatus.allCases.filter { $0 != .unknown }.randomElement() ?? .working
        emit(RPCEvent(method: EventMethod.agentStatus, params: .object([
            "pane": .string(pane.rawValue),
            "status": .string(status.rawValue),
        ])))
        if status == .working {
            emit(RPCEvent(method: EventMethod.output, params: .object([
                "pane": .string(pane.rawValue),
                "chunk": .string("● still working… \(Self.timestamp())"),
            ])))
        }
    }

    private func makeResponse(for request: RPCRequest) -> RPCResponse {
        do {
            switch request.method {
            case Method.workspaceList:
                let payload = try JSONValue.object(["workspaces": JSONValue(encoding: workspaces)])
                return RPCResponse(id: request.id, result: payload, error: nil)

            case Method.paneRead:
                let pane = request.params["pane"]?.stringValue.map { PaneID($0) }
                let lines = pane.flatMap { output[$0] } ?? []
                return RPCResponse(
                    id: request.id,
                    result: .object(["lines": .array(lines.map(JSONValue.string))]),
                    error: nil
                )

            default:
                // send-text / send-keys / subscribe / ping and anything else: ack.
                return RPCResponse(id: request.id, result: .object(["ok": .bool(true)]), error: nil)
            }
        } catch {
            return RPCResponse(id: request.id, result: nil, error: RPCError(code: -1, message: "\(error)"))
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
