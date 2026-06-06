import Foundation
import Combine

@MainActor
final class PostmeStore: ObservableObject {
    @Published var requests: [APIRequest] {
        didSet { scheduleSave() }
    }
    @Published var history: [HistoryEntry] {
        didSet { scheduleSave() }
    }
    @Published var variables: [EnvironmentVariable] {
        didSet { scheduleSave() }
    }
    @Published var selectedRequestID: APIRequest.ID?
    @Published var sidebarMode: SidebarMode = .collection
    @Published var response: ResponseSnapshot?
    @Published var errorMessage: String?
    @Published var isSending = false

    private let runner = RequestRunner()
    private let rawCodec = RawHTTPRequestCodec()
    private let persistenceKey = "postme.workspace.v1"
    private let historyLimit = 100
    private var saveTask: Task<Void, Never>?

    init() {
        if let workspace = Self.loadWorkspace(key: persistenceKey) {
            let migrated = Self.migratedWorkspace(workspace)
            requests = migrated.requests
            history = migrated.history
            variables = migrated.variables
            selectedRequestID = migrated.requests.first?.id
            saveImmediately()
        } else {
            requests = [.sample]
            history = []
            variables = [
                EnvironmentVariable(key: "baseUrl", value: "https://jsonplaceholder.typicode.com")
            ]
            selectedRequestID = APIRequest.sample.id
        }
    }

    deinit {
        saveTask?.cancel()
    }

    var selectedRequest: APIRequest? {
        guard let selectedRequestID else { return nil }
        return request(matching: selectedRequestID)
    }

    func bindingForSelectedRequest() -> BindingBox<APIRequest>? {
        guard let selectedRequestID, let selectedRequest = request(matching: selectedRequestID) else {
            return nil
        }

        return BindingBox(
            get: { self.request(matching: selectedRequestID) ?? selectedRequest },
            set: { request in
                guard let index = self.indexOfRequest(matching: selectedRequestID) else { return }
                self.requests[index] = request
                self.requests[index].updatedAt = .now
            }
        )
    }

    func addRequest() {
        let request = APIRequest(
            name: "GET /posts/1",
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
        requests.insert(request, at: 0)
        selectedRequestID = request.id
        sidebarMode = .collection
        response = nil
        errorMessage = nil
    }

    func duplicateSelectedRequest() {
        guard var request = selectedRequest else { return }
        request.id = UUID()
        request.name += " Copy"
        request.updatedAt = .now
        requests.insert(request, at: 0)
        selectedRequestID = request.id
    }

    func selectRequest(_ requestID: APIRequest.ID) {
        selectedRequestID = requestID
        sidebarMode = .collection
        response = nil
        errorMessage = nil
    }

    func deleteSelectedRequest() {
        guard let selectedRequestID, requests.count > 1 else { return }
        requests.removeAll { $0.id == selectedRequestID }
        self.selectedRequestID = requests.first?.id
        response = nil
        errorMessage = nil
    }

    func addHeader(to requestID: APIRequest.ID) {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }
        requests[index].headers.append(HeaderField(key: "", value: ""))
        requests[index].updatedAt = .now
    }

    func removeHeader(_ headerID: HeaderField.ID, from requestID: APIRequest.ID) {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }
        requests[index].headers.removeAll { $0.id == headerID }
        requests[index].updatedAt = .now
    }

    func addVariable() {
        variables.append(EnvironmentVariable(key: "", value: ""))
    }

    func removeVariable(_ variableID: EnvironmentVariable.ID) {
        variables.removeAll { $0.id == variableID }
    }

    func loadHistory(_ entry: HistoryEntry) {
        var request = entry.request
        request.id = UUID()
        request.name = "\(request.method.rawValue) \(URL(string: request.url)?.host ?? request.name)"
        request.updatedAt = .now
        requests.insert(request, at: 0)
        selectedRequestID = request.id
        sidebarMode = .collection
        response = nil
        errorMessage = entry.errorMessage
    }

    func sendSelectedRequest() async {
        guard !isSending, let request = selectedRequest else { return }
        let requestID = request.id
        isSending = true
        errorMessage = nil
        response = nil
        defer { isSending = false }

        do {
            let resolver = EnvironmentResolver(variables: variables)
            let normalizedRequest = try runner.normalizedRequest(from: request, resolver: resolver)
            updateRequest(with: normalizedRequest, matching: requestID)

            let snapshot = try await runner.send(normalizedRequest, variables: variables)
            response = snapshot
            prependHistory(HistoryEntry(request: normalizedRequest, response: snapshot, errorMessage: nil, sentAt: .now))
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            prependHistory(HistoryEntry(request: request, response: nil, errorMessage: message, sentAt: .now))
        }
    }

    func ensureRawRequest(for request: APIRequest) -> String {
        rawCodec.rawText(from: request)
    }

    func appendToSelectedRawRequest(_ value: String) {
        guard let selectedRequestID, let index = requests.firstIndex(where: { $0.id == selectedRequestID }) else { return }
        var rawRequest = rawCodec.rawText(from: requests[index])
        if !rawRequest.hasSuffix("\n") {
            rawRequest += "\n"
        }
        rawRequest += value
        requests[index].rawRequest = rawRequest
        requests[index].updatedAt = .now
    }

    func normalizeSelectedRawRequest() {
        guard let selectedRequestID, let index = requests.firstIndex(where: { $0.id == selectedRequestID }) else { return }
        do {
            let normalized = try rawCodec.normalizedRawText(from: requests[index], variables: variables)
            requests[index].rawRequest = normalized
            requests[index].updatedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func flushPersistence() {
        saveImmediately()
    }

    func prettyPrintSelectedJSONBody() {
        guard let selectedRequestID, let index = requests.firstIndex(where: { $0.id == selectedRequestID }) else { return }
        let rawRequest = rawCodec.rawText(from: requests[index]).replacingOccurrences(of: "\r\n", with: "\n")
        let parts = rawRequest.components(separatedBy: "\n\n")
        guard parts.count > 1 else {
            errorMessage = "Request body is empty."
            return
        }

        let head = parts[0]
        let body = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let data = body.data(using: .utf8) else {
            errorMessage = "Request body is empty."
            return
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard JSONSerialization.isValidJSONObject(object) else {
                errorMessage = "Request body is not a JSON object or array."
                return
            }

            let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            guard let pretty = String(data: prettyData, encoding: .utf8) else {
                errorMessage = "Unable to encode pretty JSON."
                return
            }

            requests[index].rawRequest = head + "\n\n" + pretty
            requests[index].updatedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = "Request body is not valid JSON."
        }
    }

    private func request(matching requestID: APIRequest.ID) -> APIRequest? {
        guard let index = indexOfRequest(matching: requestID) else { return nil }
        return requests[index]
    }

    private func indexOfRequest(matching requestID: APIRequest.ID) -> Array<APIRequest>.Index? {
        requests.firstIndex { $0.id == requestID }
    }

    private func updateRequest(with normalizedRequest: APIRequest, matching requestID: APIRequest.ID) {
        guard let index = indexOfRequest(matching: requestID) else { return }
        requests[index].method = normalizedRequest.method
        requests[index].url = normalizedRequest.url
        requests[index].headers = normalizedRequest.headers
        requests[index].body = normalizedRequest.body
        requests[index].updatedAt = .now
    }

    private func prependHistory(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > historyLimit {
            history.removeSubrange(historyLimit..<history.count)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil
        let workspace = Workspace(requests: requests, history: history, variables: variables)
        guard let data = try? JSONEncoder.postme.encode(workspace) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private static func loadWorkspace(key: String) -> Workspace? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder.postme.decode(Workspace.self, from: data)
    }

    private static func migratedWorkspace(_ workspace: Workspace) -> Workspace {
        Workspace(
            requests: workspace.requests.map(migratedRequest),
            history: workspace.history,
            variables: workspace.variables
        )
    }

    private static func migratedRequest(_ request: APIRequest) -> APIRequest {
        var output = request
        output.url = migrateVariableSyntax(output.url)
        output.body = migrateVariableSyntax(output.body)
        output.rawRequest = output.rawRequest.map(migrateVariableSyntax)
        output.headers = output.headers.map { header in
            HeaderField(
                id: header.id,
                key: header.key,
                value: migrateVariableSyntax(header.value),
                isEnabled: header.isEnabled
            )
        }
        return output
    }

    private static func migrateVariableSyntax(_ value: String) -> String {
        value.replacingOccurrences(of: "{{baseUrl}}", with: "$baseUrl")
    }
}

struct BindingBox<Value> {
    let get: () -> Value
    let set: (Value) -> Void
}

private struct Workspace: Codable {
    var requests: [APIRequest]
    var history: [HistoryEntry]
    var variables: [EnvironmentVariable]
}

extension JSONEncoder {
    static var postme: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var postme: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
