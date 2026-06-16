import XCTest
@testable import HerdrKit

final class ClientTests: XCTestCase {
    /// Exercises the full request → transport → response → continuation path.
    func testListWorkspacesRoundTrip() async throws {
        let client = HerdrClient(transport: MockTransport(tickInterval: .seconds(3600)))
        try await client.connect()

        let workspaces = try await client.listWorkspaces()
        XCTAssertEqual(workspaces.map(\.label), ["herdr-ios", "api-server", "infra"])
        XCTAssertEqual(workspaces[0].aggregateStatus, .blocked, "blocked agent should win the badge")
    }

    func testReadPaneReturnsLines() async throws {
        let client = HerdrClient(transport: MockTransport(tickInterval: .seconds(3600)))
        try await client.connect()

        let lines = try await client.readPane("1-2")
        XCTAssertTrue(lines.contains { $0.contains("Waiting for your confirmation") })
    }

    /// A server-pushed event must surface on the client's event stream as a
    /// typed `HerdrEvent`.
    func testEventStreamDeliversStatusChange() async throws {
        let transport = MockTransport(tickInterval: .seconds(3600))
        let client = HerdrClient(transport: transport)
        try await client.connect()

        let received = Task { () -> HerdrEvent? in
            for await event in await client.eventStream {
                if case .agentStatus(let pane, _) = event, pane == "1-1" { return event }
            }
            return nil
        }

        await transport.emit(RPCEvent(method: EventMethod.agentStatus, params: .object([
            "pane": .string("1-1"), "status": .string("done"),
        ])))

        let event = await received.value
        guard case .agentStatus(let pane, let status)? = event else {
            return XCTFail("expected an agentStatus event")
        }
        XCTAssertEqual(pane, "1-1")
        XCTAssertEqual(status, .done)
    }
}
