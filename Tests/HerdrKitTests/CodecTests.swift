import XCTest
@testable import HerdrKit

final class CodecTests: XCTestCase {
    func testRequestFramingMatchesDocumentedShape() throws {
        let request = RPCRequest(id: "req_1", method: "ping", params: .object([:]))
        let line = try NDJSON.frame(request)

        XCTAssertEqual(line.last, NDJSON.newline, "frames must be newline-terminated")

        let object = try JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any]
        XCTAssertEqual(object?["id"] as? String, "req_1")
        XCTAssertEqual(object?["method"] as? String, "ping")
    }

    func testDecodeResponseMessage() throws {
        let line = Data(#"{"id":"req_1","result":{"type":"pong"}}"#.utf8)
        guard case .response(let response) = try IncomingMessage.decode(line: line) else {
            return XCTFail("expected a response")
        }
        XCTAssertEqual(response.id, "req_1")
        XCTAssertEqual(response.result?["type"]?.stringValue, "pong")
        XCTAssertNil(response.error)
    }

    func testDecodeEventMessage() throws {
        let line = Data(#"{"method":"agent-status","params":{"pane":"1-1","status":"blocked"}}"#.utf8)
        guard case .event(let event) = try IncomingMessage.decode(line: line) else {
            return XCTFail("expected an event")
        }
        XCTAssertEqual(event.method, "agent-status")
        XCTAssertEqual(HerdrEvent(event).map(String.init(describing:)),
                       String(describing: HerdrEvent.agentStatus(pane: "1-1", status: .blocked)))
    }

    func testDecodeErrorResponse() throws {
        let line = Data(#"{"id":"req_2","error":{"code":-32601,"message":"method not found"}}"#.utf8)
        guard case .response(let response) = try IncomingMessage.decode(line: line) else {
            return XCTFail("expected a response")
        }
        XCTAssertEqual(response.error?.code, -32601)
    }

    func testLineBufferSplitsAndRetainsPartials() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data(#"{"a":1}"#.utf8)).count, 0, "no newline yet → no lines")
        let lines = buffer.append(Data("\n{\"b\":2}\n{\"c\"".utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), #"{"a":1}"#)
        XCTAssertEqual(String(data: lines[1], encoding: .utf8), #"{"b":2}"#)
        // The trailing partial is retained until its newline arrives.
        let rest = buffer.append(Data(":3}\n".utf8))
        XCTAssertEqual(String(data: rest[0], encoding: .utf8), #"{"c":3}"#)
    }

    func testJSONValueRoundTrip() throws {
        let value = JSONValue.object([
            "s": .string("x"), "i": .int(7), "b": .bool(true),
            "a": .array([.int(1), .null]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}
