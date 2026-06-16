import SwiftUI
import HerdrKit

/// A small colored dot for a single agent status, optionally labeled.
struct StatusDot: View {
    let status: AgentStatus
    var pulses: Bool = false
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 10, height: 10)
            .opacity(pulses && status == .working ? (animate ? 0.4 : 1) : 1)
            .animation(
                pulses && status == .working
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: animate
            )
            .onAppear { animate = true }
            .accessibilityLabel(status.label)
    }
}

/// A pill summarizing how many agents sit in each status within a workspace.
struct StatusSummary: View {
    let counts: [AgentStatus: Int]

    private var ordered: [(AgentStatus, Int)] {
        AgentStatus.allCases
            .compactMap { status in counts[status].map { (status, $0) } }
            .filter { $0.1 > 0 }
            .sorted { $0.0.priority > $1.0.priority }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ordered, id: \.0) { status, count in
                HStack(spacing: 4) {
                    StatusDot(status: status)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Inline status label used in pane rows.
struct StatusTag: View {
    let status: AgentStatus
    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: status, pulses: true)
            Text(status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)
        }
    }
}
