import Foundation

struct RequestRunner {
    private let rawTransport = RawHTTPTransport()

    func send(_ apiRequest: APIRequest, variables: [EnvironmentVariable]) async throws -> ResponseSnapshot {
        try await rawTransport.send(apiRequest, variables: variables)
    }

    func normalizedRequest(from apiRequest: APIRequest, resolver: EnvironmentResolver) throws -> APIRequest {
        guard let rawRequest = apiRequest.rawRequest, !rawRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return apiRequest
        }

        return try RawHTTPRequestCodec().parse(rawRequest, fallback: apiRequest, resolver: resolver)
    }

    func buildURLRequest(from apiRequest: APIRequest, resolver: EnvironmentResolver) throws -> URLRequest {
        let resolvedURL = resolver.resolve(apiRequest.url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: resolvedURL), let scheme = url.scheme, !scheme.isEmpty else {
            throw RequestBuildError.invalidURL(resolvedURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = apiRequest.method.rawValue
        request.timeoutInterval = 60

        for header in apiRequest.headers where header.isEnabled {
            let key = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            guard !key.contains("\n"), !key.contains(":") else {
                throw RequestBuildError.invalidHeader(key)
            }
            request.setValue(resolver.resolve(header.value), forHTTPHeaderField: key)
        }

        let resolvedBody = resolver.resolve(apiRequest.body)
        if apiRequest.method.sendsBody, !resolvedBody.isEmpty {
            request.httpBody = Data(resolvedBody.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }
}
