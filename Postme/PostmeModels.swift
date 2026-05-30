import Foundation

enum HTTPMethod: String, Codable, CaseIterable, Identifiable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    var id: String { rawValue }

    var sendsBody: Bool {
        switch self {
        case .post, .put, .patch, .delete:
            return true
        case .get, .head, .options:
            return false
        }
    }
}

struct HeaderField: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true
}

struct EnvironmentVariable: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true
}

struct APIRequest: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var method: HTTPMethod
    var url: String
    var headers: [HeaderField]
    var body: String
    var rawRequest: String?
    var updatedAt: Date

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty || trimmedName == "Untitled Request" else {
            return trimmedName
        }

        if let url = URL(string: url) {
            let path = url.path.isEmpty ? "/" : url.path
            return "\(method.rawValue) \(path)"
        }

        if let rawRequest {
            let firstLine = rawRequest
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", maxSplits: 1)
                .first
                .map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0]) \(parts[1])"
            }
        }

        return "Untitled Request"
    }

    static let sample = APIRequest(
        name: "JSON Placeholder",
        method: .get,
        url: "https://jsonplaceholder.typicode.com/posts/1",
        headers: [
            HeaderField(key: "Host", value: "jsonplaceholder.typicode.com"),
            HeaderField(key: "Accept", value: "application/json")
        ],
        body: "",
        rawRequest: """
        GET /posts/1 HTTP/1.1
        Host: jsonplaceholder.typicode.com
        Accept: application/json

        """,
        updatedAt: .now
    )
}

struct ResponseSnapshot: Codable, Equatable {
    var statusCode: Int
    var reason: String
    var duration: TimeInterval
    var size: Int
    var headers: [String: String]
    var body: String
    var rawResponseText: String?
    var receivedAt: Date

    var statusLine: String {
        "\(statusCode) \(reason)"
    }

    var rawHTTPText: String {
        if let rawResponseText, !rawResponseText.isEmpty {
            return rawResponseText
        }

        let statusText = statusCode > 0 ? "HTTP/1.1 \(statusLine)" : "HTTP/1.1 0 Unknown"
        let headerLines = headers
            .keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { key -> String? in
                guard let value = headers[key] else { return nil }
                return "\(key): \(value)"
            }

        return ([statusText] + headerLines + ["", prettyBody]).joined(separator: "\n")
    }

    var prettyBody: String {
        guard
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(object),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return body
        }

        return pretty
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var request: APIRequest
    var response: ResponseSnapshot?
    var errorMessage: String?
    var sentAt: Date
}

enum SidebarMode: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case history = "History"
    case environment = "Environment"

    var id: String { rawValue }
}

enum RequestBuildError: LocalizedError, Equatable {
    case invalidURL(String)
    case invalidHeader(String)
    case invalidRawRequest(String)
    case missingHost
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .invalidHeader(let key):
            return "Invalid header: \(key)"
        case .invalidRawRequest(let reason):
            return "Invalid raw request: \(reason)"
        case .missingHost:
            return "Raw request needs an absolute URL or a Host header."
        case .transport(let reason):
            return "Transport error: \(reason)"
        }
    }
}

struct EnvironmentResolver {
    let variables: [EnvironmentVariable]

    func resolve(_ value: String) -> String {
        variables
            .filter(\.isEnabled)
            .reduce(value) { resolved, variable in
                guard !variable.key.isEmpty else { return resolved }
                return resolved
                    .replacingOccurrences(of: "$\(variable.key)", with: variable.value)
                    .replacingOccurrences(of: "{{\(variable.key)}}", with: variable.value)
            }
    }
}

struct RawHTTPRequestCodec {
    func rawText(from request: APIRequest) -> String {
        if let rawRequest = request.rawRequest, !rawRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawRequest
        }

        let target = targetText(for: URL(string: request.url)) ?? request.url
        var lines = ["\(request.method.rawValue) \(target) HTTP/1.1"]
        let enabledHeaders = headersWithHost(for: request)
        lines.append(contentsOf: enabledHeaders.map { "\($0.key): \($0.value)" })
        return (lines + ["", request.body]).joined(separator: "\n")
    }

    func normalizedRawText(from request: APIRequest, variables: [EnvironmentVariable]) throws -> String {
        let resolver = EnvironmentResolver(variables: variables)
        let parsed = try parse(rawText(from: request), fallback: request, resolver: resolver)
        guard let url = URL(string: parsed.url) else {
            throw RequestBuildError.invalidURL(parsed.url)
        }

        let bodyLength = Data(parsed.body.utf8).count
        let headers = normalizedHeaders(parsed.headers, url: url, bodyLength: bodyLength)
        let target = targetText(for: url) ?? parsed.url
        var lines = ["\(parsed.method.rawValue) \(target) HTTP/1.1"]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        return (lines + ["", parsed.body]).joined(separator: "\n")
    }

    func parse(_ rawText: String, fallback: APIRequest, resolver: EnvironmentResolver) throws -> APIRequest {
        let resolvedRaw = resolver.resolve(rawText).replacingOccurrences(of: "\r\n", with: "\n")
        let parts = resolvedRaw.components(separatedBy: "\n\n")
        let head = parts.first ?? ""
        let body = parts.dropFirst().joined(separator: "\n\n")
        let lines = head.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !requestLine.isEmpty else {
            throw RequestBuildError.invalidRawRequest("missing request line")
        }

        let requestLineParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestLineParts.count >= 2 else {
            throw RequestBuildError.invalidRawRequest("expected METHOD target HTTP/version")
        }
        guard let method = HTTPMethod(rawValue: requestLineParts[0].uppercased()) else {
            throw RequestBuildError.invalidRawRequest("unsupported method \(requestLineParts[0])")
        }

        let headers = try lines.dropFirst().compactMap { line -> HeaderField? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let colon = trimmed.firstIndex(of: ":") else {
                throw RequestBuildError.invalidHeader(trimmed)
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return HeaderField(key: key, value: value)
        }

        let url = try resolvedURL(target: requestLineParts[1], headers: headers, fallback: fallback.url)
        let normalizedHeaders = headersWithHost(headers, url: url)
        return APIRequest(
            id: fallback.id,
            name: fallback.name,
            method: method,
            url: url.absoluteString,
            headers: normalizedHeaders,
            body: body,
            rawRequest: rawText,
            updatedAt: .now
        )
    }

    private func headersWithHost(for request: APIRequest) -> [HeaderField] {
        let enabledHeaders = request.headers.filter(\.isEnabled)
        guard let url = URL(string: request.url) else { return enabledHeaders }
        return headersWithHost(enabledHeaders, url: url)
    }

    private func headersWithHost(_ headers: [HeaderField], url: URL) -> [HeaderField] {
        guard !headers.contains(where: { $0.key.caseInsensitiveCompare("Host") == .orderedSame }) else {
            return headers
        }
        guard let host = url.host, !host.isEmpty else {
            return headers
        }

        var value = host
        if let port = url.port {
            value += ":\(port)"
        }

        return [HeaderField(key: "Host", value: value)] + headers
    }

    private func normalizedHeaders(_ headers: [HeaderField], url: URL, bodyLength: Int) -> [HeaderField] {
        var output = headersWithHost(headers, url: url)
        if bodyLength > 0 {
            if let index = output.firstIndex(where: { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }) {
                output[index].value = "\(bodyLength)"
            } else {
                output.append(HeaderField(key: "Content-Length", value: "\(bodyLength)"))
            }
        } else {
            output.removeAll { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }
        }

        if !output.contains(where: { $0.key.caseInsensitiveCompare("Connection") == .orderedSame }) {
            output.append(HeaderField(key: "Connection", value: "close"))
        }
        return output
    }

    private func targetText(for url: URL?) -> String? {
        guard let url else { return nil }
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            target += "?\(query)"
        }
        return target
    }

    private func resolvedURL(target: String, headers: [HeaderField], fallback: String) throws -> URL {
        if let url = URL(string: target), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }

        let host = headers.first { $0.key.caseInsensitiveCompare("Host") == .orderedSame }?.value
        let fallbackScheme = URL(string: fallback)?.scheme ?? "https"
        guard let host, !host.isEmpty else {
            throw RequestBuildError.missingHost
        }

        var path = target
        if !path.hasPrefix("/") {
            path = "/" + path
        }

        let scheme = inferredScheme(host: host, fallbackScheme: fallbackScheme)
        guard let url = URL(string: "\(scheme)://\(host)\(path)") else {
            throw RequestBuildError.invalidURL("\(scheme)://\(host)\(path)")
        }
        return url
    }

    private func inferredScheme(host: String, fallbackScheme: String) -> String {
        let lowercasedHost = host.lowercased()
        if lowercasedHost == "localhost" || lowercasedHost == "127.0.0.1" || lowercasedHost.hasPrefix("localhost:") || lowercasedHost.hasPrefix("127.0.0.1:") {
            return "http"
        }

        if let colonIndex = host.lastIndex(of: ":"),
           let port = Int(host[host.index(after: colonIndex)...]) {
            return port == 443 ? "https" : "http"
        }
        return fallbackScheme
    }
}
