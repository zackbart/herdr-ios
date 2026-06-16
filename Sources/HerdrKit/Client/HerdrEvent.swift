import Foundation

/// A decoded, domain-level event surfaced by `HerdrClient` to the UI. Raw
/// `RPCEvent`s from the socket are translated into these so views never touch
/// JSON.
public enum HerdrEvent: Sendable {
    /// An agent in a pane changed status.
    case agentStatus(pane: PaneID, status: AgentStatus)
    /// A pane produced new output to append to its scrollback.
    case output(pane: PaneID, chunk: String)
    /// Topology changed; the client should re-list workspaces.
    case topologyChanged

    /// Translate a raw socket event, or `nil` if it isn't one we model.
    init?(_ event: RPCEvent) {
        switch event.method {
        case EventMethod.agentStatus:
            guard
                let pane = event.params["pane"]?.stringValue,
                let raw = event.params["status"]?.stringValue,
                let status = AgentStatus(rawValue: raw)
            else { return nil }
            self = .agentStatus(pane: PaneID(pane), status: status)

        case EventMethod.output:
            guard let pane = event.params["pane"]?.stringValue else { return nil }
            let chunk = event.params["chunk"]?.stringValue ?? event.params["text"]?.stringValue ?? ""
            self = .output(pane: PaneID(pane), chunk: chunk)

        case EventMethod.topologyChanged:
            self = .topologyChanged

        default:
            return nil
        }
    }
}
