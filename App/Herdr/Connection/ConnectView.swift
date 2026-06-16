import SwiftUI
import HerdrKit

/// Entry screen: pick a saved host to connect over SSH, add a new one, or open
/// the in-memory demo.
struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @State private var editingHost: Host?
    @State private var showingNewHost = false

    private var store: ConnectionStore { app.connections }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await app.connectDemo() }
                    } label: {
                        Label("Open demo workspace", systemImage: "play.circle.fill")
                    }
                    .disabled(app.isConnecting)
                } header: {
                    Text("Quick start")
                } footer: {
                    Text("Explore the app with realistic sample data and live status updates — no server required.")
                }

                Section("Hosts") {
                    if store.hosts.isEmpty {
                        Text("No hosts yet. Add the machine where Herdr runs.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.hosts) { host in
                        Button {
                            Task { await app.connect(to: host) }
                        } label: {
                            HostRow(host: host)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { store.remove(host) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editingHost = host } label: {
                                Label("Edit", systemImage: "pencil")
                            }.tint(.blue)
                        }
                    }
                }

                if case .failed(let message) = app.phase {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Herdr")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewHost = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if case .connecting(let label) = app.phase {
                    ConnectingOverlay(label: label)
                }
            }
            .sheet(isPresented: $showingNewHost) {
                HostEditor(host: Host()) { host, secret in
                    store.upsert(host, secret: secret)
                }
            }
            .sheet(item: $editingHost) { host in
                HostEditor(host: host) { updated, secret in
                    store.upsert(updated, secret: secret)
                }
            }
        }
    }
}

private struct HostRow: View {
    let host: Host
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.displayName).font(.body.weight(.medium))
            Text(host.subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ConnectingOverlay: View {
    let label: String
    var body: some View {
        ZStack {
            Color(.systemBackground).opacity(0.7).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(label)…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Add/edit a host. The secret field stores the private key or password in the
/// Keychain on save.
private struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var host: Host
    @State private var secret: String = ""
    let onSave: (Host, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Nickname (optional)", text: $host.nickname)
                    TextField("Hostname", text: $host.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $host.port, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("Authentication") {
                    Picker("Method", selection: $host.authMethod) {
                        ForEach(AuthMethod.allCases) { Text($0.title).tag($0) }
                    }
                    switch host.authMethod {
                    case .privateKey:
                        TextField("Paste private key (PEM)", text: $secret, axis: .vertical)
                            .font(.caption.monospaced())
                            .lineLimit(3...8)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .password:
                        SecureField("Password", text: $secret)
                    }
                }

                Section("Herdr socket") {
                    TextField("Socket path", text: $host.socketPath)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(host.hostname.isEmpty ? "New host" : host.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(host, secret.isEmpty ? nil : secret)
                        dismiss()
                    }
                    .disabled(host.hostname.isEmpty || host.username.isEmpty)
                }
            }
        }
    }
}
