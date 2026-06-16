import Foundation
import SwiftUI
import HerdrKit

/// Screen 3: read a pane's output and send input. Scrollback comes from
/// `pane read` plus live `output` events; the input bar sends text + Enter (or
/// individual keys).
struct PaneView: View {
    @Environment(SessionModel.self) private var session
    let paneID: PaneID

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    private var pane: Pane? { session.pane(paneID) }
    private var lines: [String] { session.outputs[paneID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            scrollback
            Divider()
            inputBar
        }
        .navigationTitle(pane?.title ?? paneID.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let pane, pane.isAgent {
                    StatusTag(status: pane.status)
                }
            }
        }
        .task(id: paneID) { await session.loadOutput(for: paneID) }
    }

    private var scrollback: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.strippingANSI())
                            .font(Theme.monospaced)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(12)
            }
            .background(Color(.systemBackground))
            .onChange(of: lines.count) {
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            // Quick keys for common control sequences.
            HStack(spacing: 8) {
                ForEach(["Enter", "Esc", "Ctrl-C", "Up", "Down"], id: \.self) { key in
                    Button(key) { Task { await session.sendKeys(key, to: paneID) } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.caption.monospaced())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                TextField("Send input…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.monospaced)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private let bottomAnchor = "herdr.pane.bottom"

    private func send() {
        let text = input
        input = ""
        Task { await session.submit(text, to: paneID) }
    }
}

extension String {
    /// Remove ANSI/VT escape sequences so terminal output renders as plain text.
    func strippingANSI() -> String {
        guard contains("\u{1B}") else { return self }
        let pattern = "\u{1B}\\[[0-9;?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }
}
