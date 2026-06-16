import Foundation
import HerdrKit

/// The single source of truth for a connected Herdr session. Holds the live
/// workspace tree and per-pane scrollback, applies server-pushed events, and
/// exposes the actions the screens need. Injected into the view hierarchy via
/// SwiftUI's environment.
@MainActor
@Observable
final class SessionModel {
    let client: HerdrClient
    let label: String

    var workspaces: [Workspace] = []
    /// Scrollback lines per pane, populated by `loadOutput` and grown by events.
    var outputs: [PaneID: [String]] = [:]
    var loadError: String?

    private var eventTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subscribedTopology = false
    private var subscribedPanes: Set<PaneID> = []

    init(client: HerdrClient, label: String) {
        self.client = client
        self.label = label
    }

    /// Load the initial workspace list, begin observing live events, and
    /// subscribe to topology + per-agent-pane status changes.
    func start() async {
        await refresh()
        observeEvents()
        await syncSubscriptions()
    }

    /// Subscribe to topology once, plus agent-status for any agent panes we
    /// haven't subscribed to yet. Safe to call after each refresh.
    private func syncSubscriptions() async {
        var subscriptions: [EventSubscription] = []
        if !subscribedTopology {
            subscriptions.append(.topology)
            subscribedTopology = true
        }
        let agentPanes = Set(workspaces.flatMap(\.panes).filter(\.isAgent).map(\.id))
        let fresh = agentPanes.subtracting(subscribedPanes)
        subscriptions += fresh.map { .paneAgentStatus($0) }
        subscribedPanes.formUnion(fresh)
        guard !subscriptions.isEmpty else { return }
        try? await client.subscribe(subscriptions)
    }

    func refresh() async {
        do {
            workspaces = try await client.listWorkspaces()
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    func loadOutput(for pane: PaneID) async {
        do {
            outputs[pane] = try await client.readPane(pane)
        } catch {
            outputs[pane] = ["[error reading pane: \(error)]"]
        }
    }

    /// Submit a line of input (text + Enter), echoing it optimistically.
    func submit(_ text: String, to pane: PaneID) async {
        guard !text.isEmpty else { return }
        appendOutput("❯ \(text)", to: pane)
        try? await client.submitLine(text, to: pane)
    }

    func sendKeys(_ keys: String, to pane: PaneID) async {
        try? await client.sendKeys(keys, to: pane)
    }

    // MARK: Lookups

    func workspace(_ id: WorkspaceID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    func pane(_ id: PaneID) -> Pane? {
        workspaces.flatMap(\.panes).first { $0.id == id }
    }

    // MARK: Event handling

    private func observeEvents() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let stream = await self?.client.eventStream else { return }
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    private func apply(_ event: HerdrEvent) {
        switch event {
        case .agentStatus(let pane, let status):
            updateStatus(status, for: pane)
        case .output(let pane, let chunk):
            appendOutput(chunk, to: pane)
        case .topologyChanged:
            scheduleRefresh()
        }
    }

    /// Coalesce bursty topology events (a workspace close emits tab + pane
    /// closes too) into a single debounced re-list + re-subscribe.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
            await self?.syncSubscriptions()
        }
    }

    private func updateStatus(_ status: AgentStatus, for paneID: PaneID) {
        for w in workspaces.indices {
            for t in workspaces[w].tabs.indices {
                for p in workspaces[w].tabs[t].panes.indices
                where workspaces[w].tabs[t].panes[p].id == paneID {
                    workspaces[w].tabs[t].panes[p].status = status
                }
            }
        }
    }

    private func appendOutput(_ chunk: String, to pane: PaneID) {
        outputs[pane, default: []].append(chunk)
    }
}
