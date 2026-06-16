import SwiftUI
import HerdrKit

/// Screen 1: the list of workspaces with live aggregate agent status. Hosts the
/// `NavigationStack` and registers destinations for the drill-down screens.
struct WorkspaceListView: View {
    @Environment(SessionModel.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                if let error = session.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(session.workspaces) { workspace in
                    NavigationLink(value: workspace.id) {
                        WorkspaceRow(workspace: workspace)
                    }
                }
            }
            .navigationTitle("Workspaces")
            .navigationDestination(for: WorkspaceID.self) { id in
                WorkspaceDetailView(workspaceID: id)
            }
            .navigationDestination(for: PaneID.self) { id in
                PaneView(paneID: id)
            }
            .refreshable { await session.refresh() }
            .overlay {
                if session.workspaces.isEmpty && session.loadError == nil {
                    ContentUnavailableView("No workspaces", systemImage: "rectangle.3.group",
                                           description: Text("Create one with `herdr workspace create`."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Disconnect") { Task { await app.disconnect() } }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Workspaces").font(.headline)
                        Text(session.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: workspace.aggregateStatus, pulses: true)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.label).font(.body.weight(.semibold))
                if let cwd = workspace.cwd {
                    Text(cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                StatusSummary(counts: workspace.agentCounts())
            }
            Spacer()
            Text("\(workspace.agentPanes.count) agent\(workspace.agentPanes.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
