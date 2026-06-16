import Foundation

/// In-memory `HerdrTransport` that answers requests from sample data and streams
/// a trickle of live status events, so the app behaves like it's connected to a
/// busy Herdr server. Mirrors the real wire shapes (type-tagged responses,
/// `{"event":…}` envelopes) and the real one-request-per-connection model. This
/// is the default transport the app boots on.
public actor MockTransport: HerdrTransport {
    private let workspaces: [Workspace]
    private let output: [PaneID: [String]]
    private let agentPaneIDs: [PaneID]
    private let tickInterval: Duration

    public init(
        workspaces: [Workspace] = MockData.workspaces,
        output: [PaneID: [String]] = MockData.output,
        tickInterval: Duration = .seconds(3)
    ) {
        self.workspaces = workspaces
        self.output = output
        self.agentPaneIDs = workspaces.flatMap(\.agentPanes).map(\.id)
        self.tickInterval = tickInterval
    }

    public func connect() async throws {}
    public func disconnect() async {}

    public func request(_ request: RPCRequest) async throws -> RPCResponse {
        makeResponse(for: request)
    }

    /// Persistent subscription: acks with `subscription_started`, then emits a
    /// random agent-status change every `tickInterval` (the real event shape).
    public nonisolated func events(_ subscribeRequest: RPCRequest) -> AsyncStream<IncomingMessage> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                continuation.yield(.response(RPCResponse(
                    id: subscribeRequest.id,
                    result: .object(["type": .string("subscription_started")]),
                    error: nil
                )))
                let interval = await self.tickInterval
                let panes = await self.agentPaneIDs
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    if Task.isCancelled { break }
                    guard let pane = panes.randomElement() else { continue }
                    let status = AgentStatus.allCases.filter { $0 != .unknown }.randomElement() ?? .working
                    continuation.yield(.event(RPCEvent(
                        method: EventName.paneAgentStatusChanged,
                        params: .object([
                            "pane_id": .string(pane.rawValue),
                            "agent_status": .string(status.rawValue),
                        ])
                    )))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// All panes flattened, paired with their workspace/tab ids.
    private func flatPanes() -> [(workspace: Workspace, tab: Tab, pane: Pane)] {
        workspaces.flatMap { ws in ws.tabs.flatMap { tab in tab.panes.map { (ws, tab, $0) } } }
    }

    private func makeResponse(for request: RPCRequest) -> RPCResponse {
        let result: JSONValue
        switch request.method {
        case Method.workspaceList:
            result = .object(["type": .string("workspace_list"), "workspaces": .array(
                workspaces.map { ws in .object([
                    "workspace_id": .string(ws.id.rawValue),
                    "label": .string(ws.label),
                    "active_tab_id": ws.tabs.first.map { .string($0.id.rawValue) } ?? .null,
                    "agent_status": .string(ws.aggregateStatus.rawValue),
                ]) }
            )])

        case Method.tabList:
            let wsID = request.params["workspace_id"]?.stringValue
            let tabs = workspaces.first { $0.id.rawValue == wsID }?.tabs ?? []
            result = .object(["type": .string("tab_list"), "tabs": .array(
                tabs.map { tab in .object([
                    "tab_id": .string(tab.id.rawValue),
                    "workspace_id": .string(wsID ?? ""),
                    "label": .string(tab.label),
                    "agent_status": .string(AgentStatus.mostUrgent(tab.panes.map(\.status)).rawValue),
                ]) }
            )])

        case Method.paneList:
            result = .object(["type": .string("pane_list"), "panes": .array(
                flatPanes().map { entry in .object([
                    "pane_id": .string(entry.pane.id.rawValue),
                    "workspace_id": .string(entry.workspace.id.rawValue),
                    "tab_id": .string(entry.tab.id.rawValue),
                    "cwd": entry.pane.cwd.map { .string($0) } ?? .null,
                    "agent_status": .string(entry.pane.status.rawValue),
                    "focused": .bool(entry.pane.isFocused),
                ]) }
            )])

        case Method.agentList:
            // Surface agent names so the demo shows them (the real server's
            // shape is unconfirmed; the client parses this defensively).
            result = .object(["type": .string("agent_list"), "agents": .array(
                flatPanes().filter { $0.pane.isAgent }.compactMap { entry in
                    entry.pane.agent.map { name in .object([
                        "pane_id": .string(entry.pane.id.rawValue),
                        "name": .string(name),
                        "status": .string(entry.pane.status.rawValue),
                    ]) }
                }
            )])

        case Method.paneRead:
            let pane = request.params["pane_id"]?.stringValue.map { PaneID($0) }
            let text = (pane.flatMap { output[$0] } ?? []).joined(separator: "\n")
            result = .object(["type": .string("pane_read"), "read": .object([
                "text": .string(text),
                "format": .string("text"),
            ])])

        default:
            // send_text / send_keys / ping and anything else: ack.
            result = .object(["type": .string("ok")])
        }
        return RPCResponse(id: request.id, result: result, error: nil)
    }
}
