import Foundation

// Herdr speaks newline-delimited JSON-RPC over its Unix socket. A request is one
// JSON object per line:
//     {"id":"req_1","method":"ping","params":{}}
// and a successful response echoes the id:
//     {"id":"req_1","result":{"type":"pong"}}
// Subscriptions keep the connection open and push further messages (events).

/// A client → server request.
public struct RPCRequest: Codable, Sendable {
    public let id: String
    public let method: String
    public let params: JSONValue

    public init(id: String, method: String, params: JSONValue = .object([:])) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// An error object returned in place of a result.
public struct RPCError: Codable, Hashable, Sendable, Error {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// A server → client reply correlated to a request by `id`.
public struct RPCResponse: Sendable {
    public let id: String?
    public let result: JSONValue?
    public let error: RPCError?

    public init(id: String?, result: JSONValue?, error: RPCError?) {
        self.id = id
        self.result = result
        self.error = error
    }
}

/// A server-pushed event (from a subscription) that carries no request id.
public struct RPCEvent: Sendable {
    public let method: String
    public let params: JSONValue

    public init(method: String, params: JSONValue) {
        self.method = method
        self.params = params
    }
}

/// One decoded line from the socket: either a reply or an event.
public enum IncomingMessage: Sendable {
    case response(RPCResponse)
    case event(RPCEvent)

    /// Decode a single NDJSON line. A message with `result`/`error` (or only an
    /// echoed `id`) is a response; one with a `method` is an event.
    public static func decode(line: Data) throws -> IncomingMessage {
        let raw = try JSONDecoder().decode(RawMessage.self, from: line)
        if raw.result != nil || raw.error != nil {
            return .response(RPCResponse(id: raw.id, result: raw.result, error: raw.error))
        }
        if let method = raw.method, raw.id == nil {
            return .event(RPCEvent(method: method, params: raw.params ?? .object([:])))
        }
        // Bare ack: an id with no result body.
        return .response(RPCResponse(id: raw.id, result: raw.params, error: nil))
    }

    private struct RawMessage: Decodable {
        let id: String?
        let method: String?
        let params: JSONValue?
        let result: JSONValue?
        let error: RPCError?
    }
}
