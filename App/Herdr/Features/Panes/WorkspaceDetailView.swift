import SwiftUI
import HerdrKit

/// Screen 2: the tabs and panes/agents inside a single workspace, each with its
/// live status. Reads from the shared `SessionModel`, so status updates animate
/// in place.
struct WorkspaceDetailView: View {
    @Environment(SessionModel.self) private var session
    let workspaceID: WorkspaceID

    private var workspace: Workspace? { session.workspace(workspaceID) }

    var body: some View {
        Group {
            if let workspace {
                List {
                    ForEach(workspace.tabs) { tab in
                        Section(tab.label) {
                            ForEach(tab.panes) { pane in
                                NavigationLink(value: pane.id) {
                                    PaneRow(pane: pane)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(workspace.label)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Workspace closed", systemImage: "xmark.rectangle",
                                       description: Text("This workspace is no longer available."))
            }
        }
    }
}

private struct PaneRow: View {
    let pane: Pane

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.isAgent ? "cpu" : "terminal")
                .foregroundStyle(pane.isAgent ? Color.accentColor : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(pane.id.rawValue).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    if let agent = pane.agent {
                        Text(agent).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if pane.isAgent {
                StatusTag(status: pane.status)
            }
        }
        .padding(.vertical, 3)
    }
}
