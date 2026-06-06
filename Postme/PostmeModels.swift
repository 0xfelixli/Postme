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

        return ([statusText] + headerLines + ["", prettyBody]).joined(separator: "\n")
    }

    private var statusText: String {
        statusCode > 0 ? "HTTP/1.1 \(statusLine)" : "HTTP/1.1 0 Unknown"
    }

    private var headerLines: [String] {
        headers
            .keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { key -> String? in
                guard let value = headers[key] else { return nil }
                return "\(key): \(value)"
            }
    }

    var prettyBody: String {
        var parser = OrderedJSONParser(body)
        guard let value = parser.parse() else {
            return body
        }

        return JSONDisplayRenderer.render(value)
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var request: APIRequest
    var statusCode: Int?
    var reason: String?
    var duration: TimeInterval?
    var size: Int?
    var errorMessage: String?
    var sentAt: Date
    
    init(id: UUID = UUID(), request: APIRequest, response: ResponseSnapshot?, errorMessage: String?, sentAt: Date) {
        self.id = id
        self.request = request
        self.statusCode = response?.statusCode
        self.reason = response?.reason
        self.duration = response?.duration
        self.size = response?.size
        self.errorMessage = errorMessage
        self.sentAt = sentAt
    }
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
    private let replacements: [(dollar: String, mustache: String, value: String)]

    init(variables: [EnvironmentVariable]) {
        replacements = variables.compactMap { variable in
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard variable.isEnabled, !key.isEmpty else { return nil }
            return (dollar: "$\(key)", mustache: "{{\(key)}}", value: variable.value)
        }
    }

    func resolve(_ value: String) -> String {
        replacements.reduce(value) { resolved, replacement in
            resolved
                .replacingOccurrences(of: replacement.dollar, with: replacement.value)
                .replacingOccurrences(of: replacement.mustache, with: replacement.value)
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

struct CurlCommandParser {
    static func looksLikeCurl(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "curl"
            || trimmed.hasPrefix("curl ")
            || trimmed.hasPrefix("curl\t")
            || trimmed == "curl.exe"
            || trimmed.hasPrefix("curl.exe ")
            || trimmed.hasPrefix("curl.exe\t")
    }

    func parse(_ command: String, fallback: APIRequest) throws -> APIRequest {
        let tokens = try Self.shellTokens(from: command)
        guard let commandName = tokens.first?.lowercased(),
              commandName == "curl" || commandName == "curl.exe" else {
            throw RequestBuildError.invalidRawRequest("expected a curl command")
        }

        var urlText: String?
        var explicitMethod: HTTPMethod?
        var headers: [HeaderField] = []
        var bodyParts: [String] = []
        var usesHead = false
        var index = 1

        while index < tokens.count {
            let token = tokens[index]

            if let value = optionValue(token, short: "-X", long: "--request", tokens: tokens, index: &index) {
                guard let method = HTTPMethod(rawValue: value.uppercased()) else {
                    throw RequestBuildError.invalidRawRequest("unsupported curl method \(value)")
                }
                explicitMethod = method
            } else if let value = optionValue(token, short: "-H", long: "--header", tokens: tokens, index: &index) {
                if let header = Self.header(from: value) {
                    upsert(header, in: &headers)
                }
            } else if let value = optionValue(token, short: nil, long: "--url", tokens: tokens, index: &index) {
                urlText = value
            } else if let value = dataOptionValue(token, tokens: tokens, index: &index) {
                bodyParts.append(value)
            } else if let value = optionValue(token, short: "-b", long: "--cookie", tokens: tokens, index: &index) {
                appendCookie(value, to: &headers)
            } else if let value = optionValue(token, short: "-A", long: "--user-agent", tokens: tokens, index: &index) {
                upsert(HeaderField(key: "User-Agent", value: value), in: &headers)
            } else if let value = optionValue(token, short: "-e", long: "--referer", tokens: tokens, index: &index) {
                upsert(HeaderField(key: "Referer", value: value), in: &headers)
            } else if let value = optionValue(token, short: "-u", long: "--user", tokens: tokens, index: &index) {
                let encoded = Data(value.utf8).base64EncodedString()
                upsert(HeaderField(key: "Authorization", value: "Basic \(encoded)"), in: &headers)
            } else if token == "-I" || token == "--head" {
                usesHead = true
            } else if Self.noValueOptions.contains(token) {
                // Runtime-only curl behavior that has no direct raw HTTP representation here.
            } else if Self.valueOptions.contains(token) {
                index += 1
            } else if token.hasPrefix("--") {
                // Ignore unsupported long options without treating them as the request URL.
            } else if token.hasPrefix("-") {
                // Ignore unsupported short options without treating them as the request URL.
            } else if urlText == nil {
                urlText = token
            }

            index += 1
        }

        guard let rawURL = urlText?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            throw RequestBuildError.invalidRawRequest("curl command is missing a URL")
        }
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            throw RequestBuildError.invalidURL(rawURL)
        }

        let body = bodyParts.joined(separator: "&")
        let method = explicitMethod ?? (usesHead ? .head : (body.isEmpty ? .get : .post))
        let normalizedHeaders = normalizedHeaders(headers, url: url, bodyLength: Data(body.utf8).count)
        let rawRequest = rawHTTPText(method: method, url: url, headers: normalizedHeaders, body: body)

        return APIRequest(
            id: fallback.id,
            name: displayName(method: method, url: url, fallback: fallback.name),
            method: method,
            url: url.absoluteString,
            headers: normalizedHeaders,
            body: body,
            rawRequest: rawRequest,
            updatedAt: .now
        )
    }

    private static let dataOptions: Set<String> = [
        "-d", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode"
    ]

    private static let noValueOptions: Set<String> = [
        "-L", "--location", "-k", "--insecure", "-i", "--include", "-s", "--silent",
        "-S", "--show-error", "-v", "--verbose", "--compressed", "--globoff",
        "--http1.0", "--http1.1", "--http2", "--http2-prior-knowledge", "--ipv4", "--ipv6",
        "-G", "--get"
    ]

    private static let valueOptions: Set<String> = [
        "-m", "--max-time", "--connect-timeout", "--retry", "--retry-delay", "--proxy",
        "--proxy-user", "--cacert", "--cert", "--key", "--resolve", "--interface",
        "-o", "--output", "--request-target", "--form", "-F", "--form-string"
    ]

    private static func shellTokens(from command: String) throws -> [String] {
        let normalized = command
            .replacingOccurrences(of: "\\\r\n", with: " ")
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\\r", with: " ")
        let characters = Array(normalized)
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var index = 0

        func flushToken() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        while index < characters.count {
            let character = characters[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if activeQuote == "\"", character == "\\", index + 1 < characters.count {
                    index += 1
                    current.append(characters[index])
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "\\", index + 1 < characters.count {
                index += 1
                current.append(characters[index])
            } else if character.isWhitespace {
                flushToken()
            } else {
                current.append(character)
            }

            index += 1
        }

        guard quote == nil else {
            throw RequestBuildError.invalidRawRequest("unterminated quote in curl command")
        }

        flushToken()
        return tokens
    }

    private func optionValue(_ token: String, short: String?, long: String, tokens: [String], index: inout Int) -> String? {
        if token == long {
            guard index + 1 < tokens.count else { return "" }
            index += 1
            return tokens[index]
        }

        let longPrefix = long + "="
        if token.hasPrefix(longPrefix) {
            return String(token.dropFirst(longPrefix.count))
        }

        guard let short else { return nil }
        if token == short {
            guard index + 1 < tokens.count else { return "" }
            index += 1
            return tokens[index]
        }

        if token.hasPrefix(short), token.count > short.count {
            return String(token.dropFirst(short.count))
        }

        return nil
    }

    private func dataOptionValue(_ token: String, tokens: [String], index: inout Int) -> String? {
        for option in Self.dataOptions {
            if token == option {
                guard index + 1 < tokens.count else { return "" }
                index += 1
                return tokens[index]
            }

            let longPrefix = option + "="
            if option.hasPrefix("--"), token.hasPrefix(longPrefix) {
                return String(token.dropFirst(longPrefix.count))
            }
        }

        if token.hasPrefix("-d"), token.count > 2 {
            return String(token.dropFirst(2))
        }

        return nil
    }

    private static func header(from value: String) -> HeaderField? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        var key = String(value[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let headerValue = String(value[value.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix(":") else { return nil }
        if key.caseInsensitiveCompare("authority") == .orderedSame {
            key = "Host"
        }
        return HeaderField(key: key, value: headerValue)
    }

    private func appendCookie(_ value: String, to headers: inout [HeaderField]) {
        guard let index = headers.firstIndex(where: { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }) else {
            headers.append(HeaderField(key: "Cookie", value: value))
            return
        }

        if headers[index].value.isEmpty {
            headers[index].value = value
        } else {
            headers[index].value += "; \(value)"
        }
    }

    private func upsert(_ header: HeaderField, in headers: inout [HeaderField]) {
        guard !header.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard header.key.caseInsensitiveCompare("Content-Length") != .orderedSame else { return }

        if let index = headers.firstIndex(where: { $0.key.caseInsensitiveCompare(header.key) == .orderedSame }) {
            headers[index].value = header.value
        } else {
            headers.append(header)
        }
    }

    private func normalizedHeaders(_ headers: [HeaderField], url: URL, bodyLength: Int) -> [HeaderField] {
        var output = headers.filter { $0.key.caseInsensitiveCompare("Content-Length") != .orderedSame }

        if !output.contains(where: { $0.key.caseInsensitiveCompare("Host") == .orderedSame }),
           let host = hostValue(for: url) {
            output.insert(HeaderField(key: "Host", value: host), at: 0)
        }

        if bodyLength > 0 {
            output.append(HeaderField(key: "Content-Length", value: "\(bodyLength)"))
        }

        return output
    }

    private func rawHTTPText(method: HTTPMethod, url: URL, headers: [HeaderField], body: String) -> String {
        var lines = ["\(method.rawValue) \(targetText(for: url)) HTTP/1.1"]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        return (lines + ["", body]).joined(separator: "\n")
    }

    private func targetText(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path.isEmpty ? "/" : url.path
        }

        var target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            target += "?\(query)"
        }
        return target
    }

    private func hostValue(for url: URL) -> String? {
        guard let host = url.host, !host.isEmpty else { return nil }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private func displayName(method: HTTPMethod, url: URL, fallback: String) -> String {
        let fallbackName = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackName.isEmpty, fallbackName != "Untitled Request" {
            return fallback
        }

        let path = targetText(for: url)
        return "\(method.rawValue) \(path)"
    }
}

struct CurlCommandFormatter {
    func command(from rawText: String, fallback: APIRequest, variables: [EnvironmentVariable]) throws -> String {
        let resolver = EnvironmentResolver(variables: variables)
        let request = try RawHTTPRequestCodec().parse(rawText, fallback: fallback, resolver: resolver)
        guard let url = URL(string: request.url) else {
            throw RequestBuildError.invalidURL(request.url)
        }

        var parts = ["curl \(Self.shellQuoted(url.absoluteString))"]
        if request.method != .get || !request.body.isEmpty {
            parts.append("-X \(request.method.rawValue)")
        }

        for header in headersForCurl(request.headers, url: url) {
            parts.append("-H \(Self.shellQuoted("\(header.key): \(header.value)"))")
        }

        if !request.body.isEmpty {
            parts.append("--data-raw \(Self.shellQuoted(request.body))")
        }

        return parts.joined(separator: " \\\n  ")
    }

    private func headersForCurl(_ headers: [HeaderField], url: URL) -> [HeaderField] {
        headers.filter { header in
            guard header.isEnabled else { return false }
            let key = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            guard key.caseInsensitiveCompare("Content-Length") != .orderedSame else { return false }
            guard key.caseInsensitiveCompare("Connection") != .orderedSame else { return false }

            if key.caseInsensitiveCompare("Host") == .orderedSame,
               header.value.caseInsensitiveCompare(hostValue(for: url) ?? "") == .orderedSame {
                return false
            }

            return true
        }
    }

    private func hostValue(for url: URL) -> String? {
        guard let host = url.host, !host.isEmpty else { return nil }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
