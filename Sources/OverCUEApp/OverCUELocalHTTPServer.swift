import Foundation
import Network

struct OverCUELocalHTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct OverCUELocalHTTPResponse: Sendable {
    let statusCode: Int
    let reason: String
    let headers: [String: String]
    let body: Data

    static func json(statusCode: Int = 200, reason: String = "OK", body: Data) -> Self {
        Self(
            statusCode: statusCode,
            reason: reason,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
            ],
            body: body
        )
    }
}

enum OverCUELocalHTTPServerError: Error, LocalizedError {
    case invalidPort(UInt16)
    case malformedRequest
    case requestTooLarge

    var errorDescription: String? {
        switch self {
        case let .invalidPort(port):
            "Invalid local API port \(port)."
        case .malformedRequest:
            "Malformed local API request."
        case .requestTooLarge:
            "Local API request exceeded the size limit."
        }
    }
}

final class OverCUELocalHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (OverCUELocalHTTPRequest) async -> OverCUELocalHTTPResponse

    private static let maximumRequestSize = 128 * 1_024

    private let queue = DispatchQueue(label: "com.overcue.local-http")
    private let portNumber: UInt16
    private let handler: Handler
    private var listener: NWListener?

    init(port: UInt16 = 4_173, handler: @escaping Handler) {
        portNumber = port
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: portNumber) else {
            throw OverCUELocalHTTPServerError.invalidPort(portNumber)
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)

        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.listener = nil
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(on: connection, buffer: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1_024) {
            [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
            }

            guard nextBuffer.count <= Self.maximumRequestSize else {
                self.send(
                    .json(
                        statusCode: 413,
                        reason: "Payload Too Large",
                        body: Self.errorBody("Request is too large.")
                    ),
                    on: connection
                )
                return
            }

            do {
                if let request = try self.parseRequest(nextBuffer) {
                    Task { [handler] in
                        let response = await handler(request)
                        self.send(response, on: connection)
                    }
                    return
                }
            } catch {
                self.send(
                    .json(
                        statusCode: 400,
                        reason: "Bad Request",
                        body: Self.errorBody(error.localizedDescription)
                    ),
                    on: connection
                )
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func parseRequest(_ data: Data) throws -> OverCUELocalHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else { return nil }
        guard let headerText = String(
            data: data.subdata(in: data.startIndex..<headerRange.lowerBound),
            encoding: .utf8
        ) else {
            throw OverCUELocalHTTPServerError.malformedRequest
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw OverCUELocalHTTPServerError.malformedRequest
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3,
              requestParts[2].hasPrefix("HTTP/1.")
        else {
            throw OverCUELocalHTTPServerError.malformedRequest
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                throw OverCUELocalHTTPServerError.malformedRequest
            }
            let name = String(line[..<separatorIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw OverCUELocalHTTPServerError.malformedRequest
            }
            headers[name] = value
        }

        let contentLength: Int
        if let rawContentLength = headers["content-length"] {
            guard let parsed = Int(rawContentLength), parsed >= 0 else {
                throw OverCUELocalHTTPServerError.malformedRequest
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }

        let bodyStart = headerRange.upperBound
        let requiredLength = bodyStart + contentLength
        guard requiredLength <= Self.maximumRequestSize else {
            throw OverCUELocalHTTPServerError.requestTooLarge
        }
        guard data.count >= requiredLength else { return nil }

        let body = contentLength == 0
            ? Data()
            : data.subdata(in: bodyStart..<requiredLength)
        let rawTarget = requestParts[1]
        let path = rawTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawTarget

        return OverCUELocalHTTPRequest(
            method: requestParts[0].uppercased(),
            path: path,
            headers: headers,
            body: body
        )
    }

    private func send(_ response: OverCUELocalHTTPResponse, on connection: NWConnection) {
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"

        var head = "HTTP/1.1 \(response.statusCode) \(response.reason)\r\n"
        for key in headers.keys.sorted() {
            head += "\(key): \(headers[key]!)\r\n"
        }
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func errorBody(_ message: String) -> Data {
        (try? JSONEncoder().encode(["error": message])) ?? Data("{\"error\":\"Request failed.\"}".utf8)
    }
}
