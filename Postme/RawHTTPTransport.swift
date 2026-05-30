import Foundation
import Network

struct RawHTTPTransport {
    private let codec = RawHTTPRequestCodec()

    func send(_ request: APIRequest, variables: [EnvironmentVariable]) async throws -> ResponseSnapshot {
        let resolver = EnvironmentResolver(variables: variables)
        let rawText = resolver.resolve(codec.rawText(from: request))
        let parsedRequest = try codec.parse(rawText, fallback: request, resolver: EnvironmentResolver(variables: []))
        guard let url = URL(string: parsedRequest.url), let host = url.host else {
            throw RequestBuildError.invalidURL(parsedRequest.url)
        }

        let startedAt = Date()
        let scheme = url.scheme?.lowercased()
        let port = url.port ?? (scheme == "http" ? 80 : 443)
        let useTLS = scheme == "https"
        let outboundData = try buildOutboundData(from: parsedRequest, url: url)
        let responseData = try await send(outboundData, host: host, port: port, useTLS: useTLS)
        let duration = Date().timeIntervalSince(startedAt)

        return snapshot(from: responseData, duration: duration)
    }

    private func buildOutboundData(from request: APIRequest, url: URL) throws -> Data {
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            target += "?\(query)"
        }

        var headers = request.headers
        let bodyData = Data(request.body.utf8)
        headers = normalizeHeaders(headers, url: url, bodyLength: bodyData.count)

        var headLines = ["\(request.method.rawValue) \(target) HTTP/1.1"]
        headLines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })

        var data = Data(headLines.joined(separator: "\r\n").utf8)
        data.append(Data("\r\n\r\n".utf8))
        data.append(bodyData)
        return data
    }

    private func normalizeHeaders(_ headers: [HeaderField], url: URL, bodyLength: Int) -> [HeaderField] {
        var output = headers.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !output.contains(where: { $0.key.caseInsensitiveCompare("Host") == .orderedSame }), let host = url.host {
            var value = host
            if let port = url.port {
                value += ":\(port)"
            }
            output.insert(HeaderField(key: "Host", value: value), at: 0)
        }

        if bodyLength > 0 {
            if let index = output.firstIndex(where: { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }) {
                output[index].value = "\(bodyLength)"
            } else {
                output.append(HeaderField(key: "Content-Length", value: "\(bodyLength)"))
            }
        }

        if !output.contains(where: { $0.key.caseInsensitiveCompare("Connection") == .orderedSame }) {
            output.append(HeaderField(key: "Connection", value: "close"))
        }

        return output
    }

    private func send(_ data: Data, host: String, port: Int, useTLS: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(throwing: RequestBuildError.transport("invalid port \(port)"))
                return
            }

            let parameters: NWParameters = useTLS ? .tls : .tcp
            let connection = NWConnection(host: nwHost, port: nwPort, using: parameters)
            let receiver = RawHTTPReceiver(connection: connection, continuation: continuation)
            receiver.startAndSend(data)
        }
    }

    private func snapshot(from data: Data, duration: TimeInterval) -> ResponseSnapshot {
        let rawText = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        let headerDelimiter = Data("\r\n\r\n".utf8)
        let headerRange = data.range(of: headerDelimiter)
        let headData = headerRange.map { data[..<$0.lowerBound] } ?? data[...]
        let bodyData = headerRange.map { data[$0.upperBound...] } ?? Data.SubSequence()
        let head = String(data: Data(headData), encoding: .utf8)?.replacingOccurrences(of: "\r\n", with: "\n") ?? ""
        let lines = head.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let statusLine = lines.first ?? ""
        let statusParts = statusLine.split(separator: " ", maxSplits: 2).map(String.init)
        let statusCode = statusParts.count > 1 ? Int(statusParts[1]) ?? 0 : 0
        let reason = statusParts.count > 2 ? statusParts[2] : HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized

        let headers = lines.dropFirst().reduce(into: [String: String]()) { output, line in
            guard let colon = line.firstIndex(of: ":") else { return }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            output[key] = value
        }
        let decodedBodyData = shouldDecodeChunked(headers: headers) ? decodeChunked(Data(bodyData)) : Data(bodyData)
        let body = String(data: decodedBodyData, encoding: .utf8) ?? decodedBodyData.base64EncodedString()

        return ResponseSnapshot(
            statusCode: statusCode,
            reason: reason,
            duration: duration,
            size: data.count,
            headers: headers,
            body: body,
            rawResponseText: rawText,
            receivedAt: .now
        )
    }

    private func shouldDecodeChunked(headers: [String: String]) -> Bool {
        headers.contains { key, value in
            key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame &&
            value.localizedCaseInsensitiveContains("chunked")
        }
    }

    private func decodeChunked(_ data: Data) -> Data {
        var cursor = data.startIndex
        var output = Data()

        while cursor < data.endIndex {
            guard let lineRange = data.range(of: Data("\r\n".utf8), in: cursor..<data.endIndex) else {
                return data
            }

            let sizeLineData = data[cursor..<lineRange.lowerBound]
            guard let sizeLine = String(data: sizeLineData, encoding: .utf8) else {
                return data
            }
            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? sizeLine
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
                return data
            }

            cursor = lineRange.upperBound
            if size == 0 {
                return output
            }

            guard cursor + size <= data.endIndex else {
                return data
            }
            output.append(data[cursor..<(cursor + size)])
            cursor += size

            if data[cursor..<min(cursor + 2, data.endIndex)] == Data("\r\n".utf8) {
                cursor += 2
            }
        }

        return output
    }
}

private final class RawHTTPReceiver: @unchecked Sendable {
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Data, Error>?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "postme.raw-http")
    private var didResume = false
    private let timeout: TimeInterval = 60
    private var timeoutWorkItem: DispatchWorkItem?

    init(connection: NWConnection, continuation: CheckedContinuation<Data, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func startAndSend(_ data: Data) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        self.finish(.failure(error))
                    } else {
                        self.receive()
                    }
                })
            case .failed(let error):
                self.finish(.failure(error))
            case .cancelled:
                self.finish(.success(self.buffer))
            default:
                break
            }
        }
        connection.start(queue: queue)
        let timeoutWorkItem = DispatchWorkItem {
            self.finish(.failure(RequestBuildError.transport("request timed out after \(Int(self.timeout)) seconds")))
        }
        self.timeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
            }
            if let error {
                self.finish(.failure(error))
                return
            }
            if isComplete || self.hasCompleteResponse {
                self.finish(.success(self.buffer))
                return
            }
            self.receive()
        }
    }

    private var hasCompleteResponse: Bool {
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return false }
        let lowerHeaders = headerText.lowercased()

        if lowerHeaders.contains("transfer-encoding: chunked") {
            return buffer.range(of: Data("\r\n0\r\n\r\n".utf8), in: headerRange.upperBound..<buffer.endIndex) != nil
        }

        guard let contentLength = contentLength(from: headerText) else { return false }
        let bodyStart = headerRange.upperBound
        return buffer.count - bodyStart >= contentLength
    }

    private func contentLength(from headerText: String) -> Int? {
        for line in headerText.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame else {
                continue
            }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func finish(_ result: Result<Data, Error>) {
        queue.async {
            guard !self.didResume else { return }
            self.didResume = true
            self.timeoutWorkItem?.cancel()
            self.timeoutWorkItem = nil
            self.connection.stateUpdateHandler = nil
            self.connection.cancel()
            switch result {
            case .success(let data):
                self.continuation?.resume(returning: data)
            case .failure(let error):
                self.continuation?.resume(throwing: error)
            }
            self.continuation = nil
        }
    }
}
