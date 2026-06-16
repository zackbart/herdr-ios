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

    init(client: HerdrClient, label: String) {
        self.client = client
        self.label = label
    }

    /// Load the initial workspace list and begin observing live events.
    func start() async {
        await refresh()
        observeEvents()
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
            Task { await refresh() }
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
