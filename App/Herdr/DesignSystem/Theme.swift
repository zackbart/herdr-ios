import SwiftUI
import HerdrKit

// Status presentation, matching Herdr's sidebar legend:
// 🔴 blocked · 🟡 working · 🔵 done · 🟢 idle · ⚪️ unknown.
extension AgentStatus {
    var color: Color {
        switch self {
        case .blocked: return .red
        case .working: return .yellow
        case .done: return .blue
        case .idle: return .green
        case .unknown: return .gray
        }
    }

    /// Short human label for badges and accessibility.
    var label: String {
        switch self {
        case .blocked: return "Blocked"
        case .working: return "Working"
        case .done: return "Done"
        case .idle: return "Idle"
        case .unknown: return "—"
        }
    }

    /// SF Symbol used alongside the status dot.
    var symbol: String {
        switch self {
        case .blocked: return "exclamationmark.circle.fill"
        case .working: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .idle: return "moon.zzz.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum Theme {
    static let monospaced = Font.system(.callout, design: .monospaced)
}
