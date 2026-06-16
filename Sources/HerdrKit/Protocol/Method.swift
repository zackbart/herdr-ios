import Foundation

/// Socket RPC method names, centralized so they map cleanly to Herdr's CLI verbs
/// and can be corrected in one place.
///
/// These are derived from the documented CLI (`workspace list`, `pane read`,
/// `pane send-text`, …). The exact wire `method` strings — and the
/// subscribe/event method names — must be confirmed against
/// https://herdr.dev/docs/socket-api/ when wiring the real SSH transport. They
/// are isolated here precisely so that confirmation is a one-file change.
public enum Method {
    public static let ping = "ping"

    public static let workspaceList = "workspace.list"
    public static let tabList = "tab.list"
    public static let paneList = "pane.list"

    public static let paneRead = "pane.read"
    public static let paneSendText = "pane.send-text"
    public static let paneSendKeys = "pane.send-keys"
    public static let paneSplit = "pane.split"

    /// Open a live subscription; the server then streams events on the socket.
    public static let subscribe = "subscribe"
}

/// Event method names pushed by the server over a subscription.
public enum EventMethod {
    /// An agent's status changed: `{"pane": "1-1", "status": "working"}`.
    public static let agentStatus = "agent-status"
    /// New pane output: `{"pane": "1-1", "chunk": "…"}`.
    public static let output = "output"
    /// Workspace/tab/pane topology changed; clients should re-list.
    public static let topologyChanged = "topology-changed"
}
