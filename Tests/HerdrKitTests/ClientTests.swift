import XCTest
@testable import HerdrKit

final class ClientTests: XCTestCase {
    /// Exercises assembly: workspace.list + pane.list + tab.list + agent.list →
    /// nested tree.
    func testListWorkspacesAssemblesTree() async throws {
        let client = HerdrClient(transport: MockTransport(tickInterval: .seconds(3600)))
        try await client.connect()

        let workspaces = try await client.listWorkspaces()
        XCTAssertEqual(workspaces.map(\.label), ["herdr-ios", "api-server", "infra"])
        XCTAssertEqual(workspaces[0].aggregateStatus, .blocked, "blocked agent should win the badge")

        // Panes are grouped under the right tabs from the global pane.list.
        XCTAssertEqual(workspaces[0].tabs.map(\.label), ["agents", "shell"])
        XCTAssertEqual(workspaces[0].tabs[0].panes.count, 2)
        let claude = workspaces[0].tabs[0].panes.first { $0.id == "1-1" }
        XCTAssertEqual(claude?.agent, "claude")
        XCTAssertTrue(claude?.isAgent == true)
    }

    func testReadPaneReturnsLines() async throws {
        let client = HerdrClient(transport: MockTransport(tickInterval: .seconds(3600)))
        try await client.connect()

        let lines = try await client.readPane("1-2")
        XCTAssertTrue(lines.contains { $0.contains("Waiting for your confirmation") })
    }

    /// Subscribing to a pane's status opens the persistent event channel and
    /// delivers that pane's status changes as typed `HerdrEvent`s.
    func testSubscribeDeliversStatusChangesForSubscribedPane() async throws {
        let client = HerdrClient(transport: MockTransport(tickInterval: .milliseconds(20)))
        try await client.connect()
        try await client.subscribe([.paneAgentStatus("1-1")])

        let received = Task { () -> HerdrEvent? in
            for await event in await client.eventStream {
                if case .agentStatus(let pane, _) = event, pane == "1-1" { return event }
            }
            return nil
        }
        let event = await received.value
        guard case .agentStatus(let pane, _)? = event else {
            return XCTFail("expected an agentStatus event for the subscribed pane")
        }
        XCTAssertEqual(pane, "1-1")
    }

    /// A topology-only subscription gets the ack but no status events (the mock
    /// mirrors the server), so `subscribe` still returns without hanging.
    func testTopologyOnlySubscriptionSucceeds() async throws {
        let client = HerdrClient(transport: MockTransport(tickInterval: .milliseconds(20)))
        try await client.connect()
        try await client.subscribe([.topology]) // must not throw or hang
    }
}
