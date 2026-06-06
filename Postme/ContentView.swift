import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PostmeStore()
    @State private var isCommandPalettePresented = false
    @State private var responseViewMode: ResponseViewMode = .pretty
    @State private var responseSearchText = ""

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let box = store.bindingForSelectedRequest() {
                    VStack(spacing: 0) {
                        RequestTabStrip(store: store)
                            .frame(height: PostmeLayout.requestTabStripHeight)

                        Divider()

                        RequestCommandBar(
                            request: Binding(get: box.get, set: box.set),
                            store: store,
                            responseViewMode: responseViewMode,
                            responseSearchText: $responseSearchText
                        )
                        .frame(height: PostmeLayout.requestToolbarHeight)

                        Divider()

                        HSplitView {
                            RequestEditorView(
                                request: Binding(get: box.get, set: box.set),
                                store: store
                            )
                            .frame(minWidth: 430, idealWidth: 560, maxHeight: .infinity)

                            ResponsePreviewView(
                                response: store.response,
                                errorMessage: store.errorMessage,
                                isSending: store.isSending,
                                viewMode: $responseViewMode,
                                searchText: $responseSearchText
                            )
                            .frame(minWidth: 420, idealWidth: 520, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 900, idealWidth: 1120, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No Request", systemImage: "tray")
                        .frame(minWidth: 900, idealWidth: 1120, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(PostmeBackdrop())
        .overlay {
            if isCommandPalettePresented {
                CommandPaletteView(store: store, isPresented: $isCommandPalettePresented)
            }
        }
        .frame(minWidth: 920, minHeight: 720)
        .background {
            Button {
                isCommandPalettePresented = true
            } label: {
                EmptyView()
            }
            .keyboardShortcut("k", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onExitCommand {
            isCommandPalettePresented = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushPersistence()
            }
        }
    }
}

private struct RequestTabStrip: View {
    @ObservedObject var store: PostmeStore

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(store.requests) { request in
                        RequestTab(
                            request: request,
                            isSelected: store.selectedRequestID == request.id,
                            canClose: store.requests.count > 1,
                            select: { store.selectRequest(request.id) },
                            close: { store.closeRequest(request.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 5)
            }

            Divider()
                .frame(height: 24)

            Button {
                store.addRequest()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New request tab")
            .accessibilityLabel("New request tab")
            .clickableHoverEffect()
            .padding(.horizontal, 6)
        }
        .background(PostmeTheme.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PostmeTheme.separator.opacity(0.45))
                .frame(height: 1)
        }
    }
}

private struct RequestTab: View {
    let request: APIRequest
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(request.method.rawValue)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(methodTint)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(tabTitle)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(tabSubtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(canClose ? (isSelected ? 1 : 0.62) : 0)
            .disabled(!canClose)
            .help("Close tab")
            .accessibilityLabel("Close tab")
        }
        .padding(.horizontal, 8)
        .frame(width: 196, height: 30)
        .contentShape(Rectangle())
        .background(tabBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isSelected ? PostmeTheme.accent : Color.clear)
                .frame(height: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(PostmeTheme.separator.opacity(isSelected ? 0.46 : 0.24))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: select)
        .accessibilityLabel("\(request.method.rawValue) \(tabTitle)")
    }

    private var tabTitle: String {
        let displayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayName.isEmpty ? "Untitled Request" : displayName
    }

    private var tabSubtitle: String {
        guard let url = URL(string: request.url) else { return "raw request" }
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.scheme ?? "raw"
    }

    private var tabBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(PostmeTheme.raised) : AnyShapeStyle(PostmeTheme.control.opacity(0.62))
    }

    private var methodTint: Color {
        switch request.method {
        case .get:
            return PostmeTheme.success
        case .post, .put, .patch:
            return PostmeTheme.accent
        case .delete:
            return PostmeTheme.danger
        case .head, .options:
            return PostmeTheme.warning
        }
    }
}

private struct EnvironmentEditorView: View {
    @ObservedObject var store: PostmeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Environment")
                        .font(.subheadline.weight(.semibold))
                    Text("Reusable values for raw requests")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.addVariable()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add variable")
                .accessibilityLabel("Add variable")
                .clickableHoverEffect()
            }
            .padding(.horizontal, 10)

            List {
                if store.variables.isEmpty {
                    SidebarEmptyState(
                        systemImage: "curlybraces.square",
                        title: "No variables",
                        subtitle: "Add values like baseUrl, token, or workspace ids."
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach($store.variables) { $variable in
                        EnvironmentVariableRow(variable: $variable) {
                            store.removeVariable(variable.id)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            HStack(spacing: 6) {
                Image(systemName: "text.badge.checkmark")
                    .foregroundStyle(PostmeTheme.accent)
                Text("Use variables as $baseUrl or {{baseUrl}} in raw requests.")
                    .lineLimit(2)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
        }
        .padding(.top, 2)
        .background(PostmeTheme.sidebar)
    }
}

private struct EnvironmentVariableRow: View {
    @Binding var variable: EnvironmentVariable
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Toggle("", isOn: $variable.isEnabled)
                    .labelsHidden()
                    .help(variable.isEnabled ? "Variable enabled" : "Variable disabled")

                TextField("key", text: $variable.key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .disabled(!variable.isEnabled)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove variable")
                .accessibilityLabel("Remove variable")
                .clickableHoverEffect()
            }

            TextField("value", text: $variable.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .disabled(!variable.isEnabled)
        }
        .padding(.vertical, 4)
        .opacity(variable.isEnabled ? 1 : 0.52)
    }
}

private struct RequestCommandBar: View {
    @Binding var request: APIRequest
    @ObservedObject var store: PostmeStore
    let responseViewMode: ResponseViewMode
    @Binding var responseSearchText: String
    @State private var isEnvironmentPresented = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                MethodBadge(method: request.method)
                SchemeBadge(scheme: requestScheme)
                RequestURLField(request: $request, store: store)

                Button {
                    Task { await store.sendSelectedRequest() }
                } label: {
                    Label(store.isSending ? "Sending" : "Send", systemImage: store.isSending ? "hourglass" : "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(PostmeSendButtonStyle())
                .accessibilityLabel(store.isSending ? "Sending" : "Send request")
                .disabled(!canSend)
                .clickableHoverEffect(isEnabled: canSend)
            }

            HStack(spacing: 6) {
                RequestNameField(name: $request.name)
                TargetPill(title: "Target", value: targetSummary)
                    .frame(maxWidth: 260, alignment: .leading)
                TargetPill(title: "Mode", value: "Raw HTTP")

                IconToolButton(systemName: "doc.on.doc", help: "Copy request") {
                    Clipboard.copy(rawBinding.wrappedValue)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                IconToolButton(systemName: "curlybraces", help: "Pretty print JSON body") {
                    store.prettyPrintSelectedJSONBody()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                IconToolButton(systemName: "wand.and.stars", help: "Normalize Host, path, Content-Length, and Connection") {
                    store.normalizeSelectedRawRequest()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                IconToolButton(systemName: "curlybraces.square", help: "Environment variables") {
                    isEnvironmentPresented.toggle()
                }
                .popover(isPresented: $isEnvironmentPresented, arrowEdge: .bottom) {
                    EnvironmentEditorView(store: store)
                        .frame(width: 360, height: 430)
                }

                Spacer(minLength: 12)

                RequestStatusCapsule(
                    isSending: store.isSending,
                    response: store.response,
                    errorMessage: store.errorMessage
                )

                if let response = store.response {
                    MetricPill(value: "\(Int(response.duration * 1000)) ms")
                    MetricPill(value: ByteCountFormatter.string(fromByteCount: Int64(response.size), countStyle: .file))
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search response", text: $responseSearchText)
                        .textFieldStyle(.plain)
                    if !responseSearchText.isEmpty {
                        Button {
                            responseSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .clickableHoverEffect()
                    }
                }
                .frame(width: 156)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(PostmeTheme.raised, in: RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius)
                        .stroke(PostmeTheme.separator.opacity(0.28))
                }

                IconToolButton(systemName: "doc.on.doc", help: "Copy response") {
                    if let response = store.response {
                        Clipboard.copy(ResponseDisplayFormatter.text(for: response, mode: responseViewMode, searchText: responseSearchText).text)
                    }
                }
                .disabled(store.response == nil)
                .opacity(store.response == nil ? 0.45 : 1)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PostmeTheme.toolbar)
    }

    private var rawBinding: Binding<String> {
        Binding(
            get: { request.rawRequest ?? store.ensureRawRequest(for: request) },
            set: { request.rawRequest = $0 }
        )
    }

    private var canSend: Bool {
        !store.isSending && !rawBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var requestScheme: String {
        URL(string: request.url)?.scheme?.uppercased() ?? "RAW"
    }

    private var targetSummary: String {
        guard let url = URL(string: request.url), let host = url.host else {
            return "Host header"
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }
}

private struct RequestURLField: View {
    @Binding var request: APIRequest
    @ObservedObject var store: PostmeStore
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            TextField("Paste URL or cURL", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .focused($isFocused)
                .onSubmit {
                    commitDraft()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PostmeTheme.raised, in: RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius)
                .stroke(PostmeTheme.separator.opacity(0.30))
        }
        .help("Paste a URL, or paste a browser Copy as cURL command to convert it into raw HTTP.")
        .onAppear {
            syncDraft(force: true)
        }
        .onChange(of: request.id) { _, _ in
            syncDraft(force: true)
        }
        .onChange(of: request.url) { _, _ in
            syncDraft(force: false)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                syncDraft(force: true)
            } else {
                commitDraft()
            }
        }
        .onChange(of: draft) { _, value in
            commitIfCompleteCurl(value)
        }
    }

    private var iconName: String {
        CurlCommandParser.looksLikeCurl(draft) ? "terminal" : "link"
    }

    private func syncDraft(force: Bool) {
        guard force || !isFocused else { return }
        draft = request.url
    }

    private func commitDraft(_ value: String? = nil) {
        let input = (value ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input != request.url else {
            syncDraft(force: true)
            return
        }

        store.applyTargetInput(input, to: request.id)
        draft = store.selectedRequest?.url ?? request.url
    }

    private func commitIfCompleteCurl(_ value: String) {
        guard isFocused, CurlCommandParser.looksLikeCurl(value) else { return }
        guard (try? CurlCommandParser().parse(value, fallback: request)) != nil else { return }
        commitDraft(value)
    }
}

private struct RequestNameField: View {
    @Binding var name: String

    var body: some View {
        HStack(spacing: 6) {
            Text("Name".uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)

            TextField("Request name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .frame(minWidth: 136, idealWidth: 174, maxWidth: 198)
        .background(PostmeTheme.raised.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(PostmeTheme.separator.opacity(0.24))
        }
    }
}

private struct RequestEditorView: View {
    @Binding var request: APIRequest
    @ObservedObject var store: PostmeStore

    var body: some View {
        VStack(spacing: 0) {
            RawPane(title: "Request", subtitle: "", systemImage: "doc.plaintext") {
                RawRequestEditor(
                    text: rawBinding,
                    repeatRequest: {
                        store.duplicateSelectedRequest()
                    },
                    copyAsCurl: {
                        copySelectedRequestAsCurl()
                    }
                )
            }
            .padding(PostmeLayout.panePadding)
        }
        .background(PostmeTheme.window)
    }

    private var rawBinding: Binding<String> {
        Binding(
            get: { request.rawRequest ?? store.ensureRawRequest(for: request) },
            set: { request.rawRequest = $0 }
        )
    }

    private func copySelectedRequestAsCurl() {
        do {
            let command = try CurlCommandFormatter().command(
                from: rawBinding.wrappedValue,
                fallback: request,
                variables: store.variables
            )
            Clipboard.copy(command)
            store.errorMessage = nil
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct ResponsePreviewView: View {
    var response: ResponseSnapshot?
    var errorMessage: String?
    var isSending: Bool
    @Binding var viewMode: ResponseViewMode
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                RawPane(title: "Response", subtitle: "", systemImage: "exclamationmark.triangle", accent: PostmeTheme.danger, accessory: {
                    responseModePicker
                }) {
                    ErrorResponseSurface(message: errorMessage)
                }
                .padding(PostmeLayout.panePadding)
            } else if let response {
                let rendered = ResponseDisplayFormatter.text(for: response, mode: viewMode, searchText: searchText)
                RawPane(title: "Response", subtitle: "", systemImage: "doc.plaintext", accent: HTTPStatusTone.color(for: response.statusCode), accessory: {
                    responseModePicker
                }) {
                    RawResponseSurface(text: rendered.text)
                }
                .padding(PostmeLayout.panePadding)
            } else {
                RawPane(title: "Response", subtitle: "", systemImage: "doc.plaintext", accent: .secondary, accessory: {
                    responseModePicker
                }) {
                    EmptyResponseSurface()
                }
                .padding(PostmeLayout.panePadding)
            }
        }
        .background(PostmeTheme.window)
    }

    private var responseModePicker: some View {
        ResponseModeSelector(selection: $viewMode)
    }

}

private enum ResponseViewMode: String, CaseIterable, Identifiable {
    case pretty = "Pretty"
    case raw = "Raw"
    case hex = "Hex"

    var id: String { rawValue }
}

private struct ResponseModeSelector: View {
    @Binding var selection: ResponseViewMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResponseViewMode.allCases) { mode in
                ResponseModeButton(mode: mode, isSelected: selection == mode) {
                    selection = mode
                }
            }
        }
        .padding(2)
        .frame(width: 166, height: 30)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(PostmeTheme.separator.opacity(0.35))
        }
    }
}

private struct ResponseModeButton: View {
    let mode: ResponseViewMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mode.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .foregroundStyle(foregroundStyle)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(mode.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "")
        .clickableHoverEffect()
    }

    private var foregroundStyle: Color {
        isSelected ? Color.white : Color.primary
    }

    private var backgroundStyle: Color {
        isSelected ? PostmeTheme.accent : Color.clear
    }
}

private enum ResponseDisplayFormatter {
    struct Result {
        let text: String
        let searchText: String
        let matchCount: Int?
    }

    static func text(for response: ResponseSnapshot, mode: ResponseViewMode, searchText: String) -> Result {
        let baseText = baseText(for: response, mode: mode)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            return Result(text: baseText, searchText: "", matchCount: nil)
        }

        let matches = baseText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(trimmedSearch) }

        return Result(
            text: matches.isEmpty ? "No response lines match \"\(trimmedSearch)\"." : matches.joined(separator: "\n"),
            searchText: trimmedSearch,
            matchCount: matches.count
        )
    }

    private static func baseText(for response: ResponseSnapshot, mode: ResponseViewMode) -> String {
        switch mode {
        case .raw:
            return response.rawHTTPText
        case .pretty:
            return prettyHTTPText(for: response)
        case .hex:
            return response.rawHTTPText.hexDump()
        }
    }

    private static func prettyHTTPText(for response: ResponseSnapshot) -> String {
        ([statusLine(for: response)] + headerLines(for: response) + ["", prettyBody(for: response)]).joined(separator: "\n")
    }

    private static func statusLine(for response: ResponseSnapshot) -> String {
        response.statusCode > 0 ? "HTTP/1.1 \(response.statusLine)" : "HTTP/1.1 0 Unknown"
    }

    private static func headerLines(for response: ResponseSnapshot) -> [String] {
        response.headers
            .keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { key -> String? in
                guard let value = response.headers[key] else { return nil }
                return "\(key): \(value)"
            }
    }

    private static func prettyBody(for response: ResponseSnapshot) -> String {
        response.prettyBody
    }
}

enum OrderedJSON {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

struct OrderedJSONParser {
    private let text: String
    private var index: String.Index

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func parse() -> OrderedJSON? {
        skipWhitespace()
        guard let value = parseValue() else { return nil }
        skipWhitespace()
        return index == text.endIndex ? value : nil
    }

    private mutating func parseValue() -> OrderedJSON? {
        skipWhitespace()
        guard index < text.endIndex else { return nil }

        switch text[index] {
        case "{":
            return parseObject()
        case "[":
            return parseArray()
        case "\"":
            return parseString().map(OrderedJSON.string)
        case "t":
            return consume("true") ? .bool(true) : nil
        case "f":
            return consume("false") ? .bool(false) : nil
        case "n":
            return consume("null") ? .null : nil
        default:
            return parseNumber().map(OrderedJSON.number)
        }
    }

    private mutating func parseObject() -> OrderedJSON? {
        guard consume("{") else { return nil }
        skipWhitespace()
        if consume("}") { return .object([]) }

        var pairs: [(key: String, value: OrderedJSON)] = []
        while true {
            skipWhitespace()
            guard let key = parseString() else { return nil }
            skipWhitespace()
            guard consume(":") else { return nil }
            guard let value = parseValue() else { return nil }
            pairs.append((key, value))
            skipWhitespace()
            if consume("}") { return .object(pairs) }
            guard consume(",") else { return nil }
        }
    }

    private mutating func parseArray() -> OrderedJSON? {
        guard consume("[") else { return nil }
        skipWhitespace()
        if consume("]") { return .array([]) }

        var values: [OrderedJSON] = []
        while true {
            guard let value = parseValue() else { return nil }
            values.append(value)
            skipWhitespace()
            if consume("]") { return .array(values) }
            guard consume(",") else { return nil }
        }
    }

    private mutating func parseString() -> String? {
        guard consume("\"") else { return nil }
        var output = ""

        while index < text.endIndex {
            let character = text[index]
            text.formIndex(after: &index)

            if character == "\"" {
                return output
            }

            guard character == "\\" else {
                output.append(character)
                continue
            }

            guard index < text.endIndex else { return nil }
            let escaped = text[index]
            text.formIndex(after: &index)
            switch escaped {
            case "\"", "\\", "/":
                output.append(escaped)
            case "b":
                output.append("\u{8}")
            case "f":
                output.append("\u{c}")
            case "n":
                output.append("\n")
            case "r":
                output.append("\r")
            case "t":
                output.append("\t")
            case "u":
                guard let scalar = parseUnicodeScalar() else { return nil }
                output.unicodeScalars.append(scalar)
            default:
                return nil
            }
        }

        return nil
    }

    private mutating func parseUnicodeScalar() -> UnicodeScalar? {
        var hex = ""
        for _ in 0..<4 {
            guard index < text.endIndex else { return nil }
            hex.append(text[index])
            text.formIndex(after: &index)
        }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return UnicodeScalar(value)
    }

    private mutating func parseNumber() -> String? {
        let start = index
        if current == "-" {
            text.formIndex(after: &index)
        }

        guard consumeDigits() else {
            index = start
            return nil
        }

        if current == "." {
            text.formIndex(after: &index)
            guard consumeDigits() else {
                index = start
                return nil
            }
        }

        if current == "e" || current == "E" {
            text.formIndex(after: &index)
            if current == "+" || current == "-" {
                text.formIndex(after: &index)
            }
            guard consumeDigits() else {
                index = start
                return nil
            }
        }

        return String(text[start..<index])
    }

    private mutating func consumeDigits() -> Bool {
        let start = index
        while let current, current.isNumber {
            text.formIndex(after: &index)
        }
        return index > start
    }

    private mutating func consume(_ token: String) -> Bool {
        guard index < text.endIndex, text[index...].hasPrefix(token) else { return false }
        index = text.index(index, offsetBy: token.count)
        return true
    }

    private mutating func skipWhitespace() {
        while let current, current.isWhitespace {
            text.formIndex(after: &index)
        }
    }

    private var current: Character? {
        index < text.endIndex ? text[index] : nil
    }
}

enum JSONDisplayRenderer {
    static func render(_ value: OrderedJSON) -> String {
        render(value, level: 0)
    }

    private static func render(_ value: OrderedJSON, level: Int) -> String {
        switch value {
        case .object(let pairs):
            return renderObject(pairs, level: level)
        case .array(let array):
            return renderArray(array, level: level)
        case .string(let string):
            return renderString(string, continuationIndent: indent(level + 1))
        case .number(let number):
            return number
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func renderObject(_ pairs: [(key: String, value: OrderedJSON)], level: Int) -> String {
        guard !pairs.isEmpty else { return "{}" }

        let keyIndent = indent(level + 1)
        let lines = pairs.map { key, value -> String in
            return "\(keyIndent)\"\(escape(key))\": \(render(value, level: level + 1))"
        }

        return "{\n\(lines.joined(separator: ",\n"))\n\(indent(level))}"
    }

    private static func renderArray(_ array: [OrderedJSON], level: Int) -> String {
        guard !array.isEmpty else { return "[]" }

        let itemIndent = indent(level + 1)
        let lines = array.map { "\(itemIndent)\(render($0, level: level + 1))" }
        return "[\n\(lines.joined(separator: ",\n"))\n\(indent(level))]"
    }

    private static func renderString(_ value: String, continuationIndent: String) -> String {
        let escaped = escape(value)
        guard escaped.contains("\n") else {
            return "\"\(escaped)\""
        }

        let lines = escaped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        return "\"" + lines.enumerated().map { index, line in
            index == 0 ? line : "\(continuationIndent)\(line)"
        }.joined(separator: "\n") + "\""
    }

    private static func escape(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private static func indent(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }
}

private struct CommandPaletteView: View {
    @ObservedObject var store: PostmeStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [CommandPaletteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = makeItems()
        guard !normalizedQuery.isEmpty else { return items }

        return items.filter { item in
            item.title.lowercased().contains(normalizedQuery) ||
            item.subtitle.lowercased().contains(normalizedQuery) ||
            item.keywords.contains { $0.lowercased().contains(normalizedQuery) }
        }
    }

    private var selectedItem: CommandPaletteItem? {
        guard filteredItems.indices.contains(selectedIndex) else { return filteredItems.first }
        return filteredItems[selectedIndex]
    }

    private var resultSummary: String {
        let count = filteredItems.count
        return count == 1 ? "1 result" : "\(count) results"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "command")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(PostmeTheme.accent)
                            .frame(width: 24, height: 24)
                            .background(PostmeTheme.accentSoft, in: RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Command palette")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Search requests, history, variables, and actions")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        CommandPaletteKeycap(text: "esc")
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PostmeTheme.accent)

                        TextField("Type a command or request", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .semibold))
                            .focused($isSearchFocused)
                            .onSubmit {
                                runSelectedItem()
                            }
                            .onExitCommand {
                                isPresented = false
                            }

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .clickableHoverEffect()
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(PostmeTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(PostmeTheme.accent.opacity(isSearchFocused ? 0.42 : 0.18), lineWidth: isSearchFocused ? 1.5 : 1)
                    }
                }
                .padding(14)

                Rectangle()
                    .fill(PostmeTheme.separator.opacity(0.42))
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            CommandPaletteRow(
                                item: item,
                                isSelected: index == selectedIndex,
                                select: { selectedIndex = index },
                                action: { run(item) }
                            )
                        }

                        if filteredItems.isEmpty {
                            CommandPaletteEmptyState(query: query)
                                .padding(.vertical, 38)
                        }
                    }
                    .padding(7)
                }
                .frame(height: 372)

                Rectangle()
                    .fill(PostmeTheme.separator.opacity(0.34))
                    .frame(height: 1)

                HStack(spacing: 8) {
                    Text(resultSummary)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 5) {
                        CommandPaletteKeycap(text: "↑↓")
                        Text("navigate")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        CommandPaletteKeycap(text: "return")
                        Text("run")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
            .frame(width: 650)
            .background(PostmeTheme.window, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PostmeTheme.separator.opacity(0.58))
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.55))
                    .blendMode(.screen)
            }
            .shadow(color: Color(red: 0.05, green: 0.10, blue: 0.18).opacity(0.22), radius: 34, x: 0, y: 18)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: filteredItems.count) { _, count in
            selectedIndex = min(selectedIndex, max(0, count - 1))
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
    }

    private func makeItems() -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = [
            CommandPaletteItem(
                title: "Send Request",
                subtitle: "Run the selected raw request",
                group: "Action",
                systemImage: "paperplane.fill",
                keywords: ["run", "repeat", "repeater"],
                run: { Task { await store.sendSelectedRequest() } }
            ),
            CommandPaletteItem(
                title: "New Request",
                subtitle: "Create a new raw HTTP request",
                group: "Action",
                systemImage: "plus",
                keywords: ["create", "collection"],
                run: { store.addRequest() }
            ),
            CommandPaletteItem(
                title: "Duplicate Request",
                subtitle: "Copy the selected request",
                group: "Action",
                systemImage: "plus.square.on.square",
                keywords: ["copy", "clone"],
                run: { store.duplicateSelectedRequest() }
            ),
            CommandPaletteItem(
                title: "Delete Request",
                subtitle: "Remove the selected request",
                group: "Action",
                systemImage: "trash",
                keywords: ["remove"],
                run: { store.deleteSelectedRequest() }
            ),
            CommandPaletteItem(
                title: "Pretty Print JSON Body",
                subtitle: "Format the raw request body as JSON",
                group: "Action",
                systemImage: "curlybraces",
                keywords: ["json", "format", "pretty"],
                run: { store.prettyPrintSelectedJSONBody() }
            ),
            CommandPaletteItem(
                title: "Normalize Request",
                subtitle: "Rewrite request line, Host, Content-Length, and Connection",
                group: "Action",
                systemImage: "wand.and.stars",
                keywords: ["content-length", "host", "connection", "fix"],
                run: { store.normalizeSelectedRawRequest() }
            )
        ]

        items += store.requests.map { request in
            CommandPaletteItem(
                title: request.name,
                subtitle: "\(request.method.rawValue) \(request.url)",
                group: "Request",
                systemImage: "doc.text",
                keywords: [request.method.rawValue, request.url],
                run: { store.selectRequest(request.id) }
            )
        }

        items += store.history.prefix(20).map { entry in
            let statusText: String
            if let errorMessage = entry.errorMessage {
                statusText = errorMessage
            } else if let statusCode = entry.statusCode, let reason = entry.reason {
                statusText = "\(statusCode) \(reason)"
            } else {
                statusText = "Failed"
            }
            
            return CommandPaletteItem(
                title: entry.request.url,
                subtitle: "\(entry.request.method.rawValue) \(statusText)",
                group: "History",
                systemImage: "clock",
                keywords: [entry.request.method.rawValue, entry.request.name],
                run: { store.loadHistory(entry) }
            )
        }

        items += store.variables.filter(\.isEnabled).map { variable in
            CommandPaletteItem(
                title: "Insert $\(variable.key)",
                subtitle: variable.value,
                group: "Variable",
                systemImage: "curlybraces",
                keywords: [variable.key, variable.value],
                run: { store.appendToSelectedRawRequest("$\(variable.key)") }
            )
        }

        return items
    }

    private func runSelectedItem() {
        guard let item = selectedItem else { return }
        run(item)
    }

    private func run(_ item: CommandPaletteItem) {
        item.run()
        isPresented = false
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !filteredItems.isEmpty else {
            selectedIndex = 0
            return
        }

        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(filteredItems.count - 1, selectedIndex + 1)
        default:
            break
        }
    }
}

private struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let group: String
    let systemImage: String
    let keywords: [String]
    let run: () -> Void

    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        group: String,
        systemImage: String,
        keywords: [String],
        run: @escaping () -> Void
    ) {
        self.id = id ?? "\(group)-\(title)-\(subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.systemImage = systemImage
        self.keywords = keywords
        self.run = run
    }
}

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    let select: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : PostmeTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.76) : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(item.group)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : PostmeTheme.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(groupBackground, in: RoundedRectangle(cornerRadius: 5))

                if isSelected {
                    CommandPaletteKeycap(text: "return", isSelected: true)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.20) : Color.clear)
        }
        .onHover { isHovering in
            if isHovering {
                select()
            }
        }
        .clickableHoverEffect()
    }

    private var rowBackground: Color {
        isSelected ? PostmeTheme.accent : Color.clear
    }

    private var iconBackground: Color {
        isSelected ? Color.white.opacity(0.16) : PostmeTheme.accentSoft
    }

    private var groupBackground: Color {
        isSelected ? Color.white.opacity(0.14) : PostmeTheme.accentSoft
    }
}

private struct CommandPaletteKeycap: View {
    let text: String
    var isSelected = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(isSelected ? Color.white.opacity(0.13) : PostmeTheme.control, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.white.opacity(0.18) : PostmeTheme.separator.opacity(0.34))
            }
    }
}

private struct CommandPaletteEmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "command.square")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PostmeTheme.accent)
                .frame(width: 48, height: 48)
                .background(PostmeTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 3) {
                Text("No matching command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(query.isEmpty ? "Start typing to search the workspace." : "Try a request path, method, variable, or action name.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private enum Clipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private extension String {
    func hexDump(bytesPerRow: Int = 16) -> String {
        let bytes = Array(utf8)
        guard !bytes.isEmpty else { return "" }

        return stride(from: 0, to: bytes.count, by: bytesPerRow).map { offset in
            let chunk = bytes[offset..<min(offset + bytesPerRow, bytes.count)]
            let hex = chunk
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
                .padding(toLength: bytesPerRow * 3 - 1, withPad: " ", startingAt: 0)
            let ascii = chunk.map { byte -> String in
                (32...126).contains(byte) ? String(UnicodeScalar(byte)) : "."
            }.joined()
            return String(format: "%08x  %@  %@", offset, hex, ascii)
        }
        .joined(separator: "\n")
    }
}

private enum PostmeTheme {
    static let window = Color(red: 0.955, green: 0.949, blue: 0.940)
    static let sidebar = Color(red: 0.925, green: 0.918, blue: 0.906)
    static let toolbar = Color(red: 0.946, green: 0.940, blue: 0.930).opacity(0.98)
    static let control = Color(red: 0.982, green: 0.978, blue: 0.970)
    static let raised = Color(red: 1.000, green: 0.998, blue: 0.994)
    static let editor = Color(red: 0.990, green: 0.987, blue: 0.980)
    static let gutter = Color(red: 0.930, green: 0.923, blue: 0.912)
    static let separator = Color(red: 0.675, green: 0.650, blue: 0.615)
    static let accent = Color(red: 0.000, green: 0.459, blue: 0.871)
    static let accentSoft = Color(red: 0.000, green: 0.459, blue: 0.871).opacity(0.10)
    static let success = Color(red: 0.145, green: 0.560, blue: 0.310)
    static let danger = Color(red: 0.700, green: 0.165, blue: 0.165)
    static let warning = Color(red: 0.760, green: 0.445, blue: 0.120)
}


private enum HTTPStatusTone {
    static func color(for statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300:
            return PostmeTheme.success
        case 300..<400:
            return PostmeTheme.warning
        case 400...:
            return PostmeTheme.danger
        default:
            return .secondary
        }
    }
}

private enum PostmeLayout {
    static let requestTabStripHeight: CGFloat = 36
    static let requestToolbarHeight: CGFloat = 68
    static let panePadding: CGFloat = 12
    static let paneHeaderHeight: CGFloat = 30
    static let cornerRadius: CGFloat = 7
}

private struct PostmeBackdrop: View {
    var body: some View {
        ZStack {
            PostmeTheme.window
            LinearGradient(
                colors: [
                    Color.white.opacity(0.42),
                    Color(red: 0.900, green: 0.890, blue: 0.875).opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct SidebarEmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PostmeTheme.accent)
                .frame(width: 32, height: 32)
                .background(PostmeTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.caption.weight(.semibold))

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PostmeTheme.window.opacity(0.54), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(PostmeTheme.separator.opacity(0.28))
        }
    }
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
            }
    }
}


private struct RawPane<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accent: Color = PostmeTheme.accent
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color = PostmeTheme.accent,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: title, subtitle: subtitle, systemImage: systemImage, accent: accent) {
                accessory
            }
            .frame(height: PostmeLayout.paneHeaderHeight, alignment: .center)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 1)
    }
}

private extension RawPane where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color = PostmeTheme.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accent: accent,
            accessory: { EmptyView() },
            content: content
        )
    }
}

private struct PaneHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 21, height: 21)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            accessory
        }
    }
}

private struct EmptyPane: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct TargetPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(PostmeTheme.raised.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(PostmeTheme.separator.opacity(0.26))
        }
    }
}

private struct ResponseStatusPill: View {
    let response: ResponseSnapshot

    var body: some View {
        Text(response.statusLine)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.18))
            }
    }

    private var color: Color {
        HTTPStatusTone.color(for: response.statusCode)
    }
}

private struct RequestStatusCapsule: View {
    let isSending: Bool
    let response: ResponseSnapshot?
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: isSending)

            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)

            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .frame(maxWidth: 210, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.17))
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var systemImage: String {
        if isSending { return "paperplane.fill" }
        if response != nil { return "checkmark.circle.fill" }
        if errorMessage != nil { return "exclamationmark.triangle.fill" }
        return "circle.dashed"
    }

    private var title: String {
        if isSending { return "Sending" }
        if let response { return response.statusLine }
        if errorMessage != nil { return "Error" }
        return "No response"
    }

    private var detail: String? {
        if isSending { return "Raw HTTP" }
        if response != nil { return nil }
        return errorMessage
    }

    private var tint: Color {
        if isSending { return PostmeTheme.accent }
        if let response { return HTTPStatusTone.color(for: response.statusCode) }
        if errorMessage != nil { return PostmeTheme.danger }
        return .secondary
    }

    private var accessibilityLabel: String {
        if let detail {
            return "\(title), \(detail)"
        }
        return title
    }
}

private struct MetricPill: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(PostmeTheme.raised.opacity(0.80), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(PostmeTheme.separator.opacity(0.20))
            }
    }
}

private struct IconToolButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .help(help)
        .buttonStyle(PostmeIconButtonStyle())
        .clickableHoverEffect()
    }
}

private struct PostmeSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.white)
            .frame(width: 84, height: 22)
            .background(
                PostmeTheme.accent.opacity(configuration.isPressed ? 0.84 : 1),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.18))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct RawRequestEditor: View {
    @Binding var text: String
    let repeatRequest: () -> Void
    let copyAsCurl: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            EditorGutter(lineCount: lineCount)
            HighlightedHTTPTextView(
                text: $text,
                isEditable: true,
                allowsInsertionCursor: true,
                wrapsLines: true,
                contextMenuStyle: .editable,
                repeatRequest: repeatRequest,
                copyAsCurl: copyAsCurl
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rawSurfaceStyle()
    }

    private var lineCount: Int {
        max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }
}

private struct RawResponseSurface: View {
    let text: String

    var body: some View {
        HighlightedHTTPTextView(
            text: .constant(text),
            isEditable: false,
            allowsInsertionCursor: true,
            wrapsLines: true,
            contextMenuStyle: .readOnly
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rawSurfaceStyle()
    }
}

private struct HighlightedHTTPTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let allowsInsertionCursor: Bool
    let wrapsLines: Bool
    var contextMenuStyle: HighlightedTextContextMenuStyle = .none
    var repeatRequest: (() -> Void)?
    var copyAsCurl: (() -> Void)?
    private var layout: HighlightedTextLayout {
        wrapsLines ? .wrapped : .raw
    }
    private var textViewAllowsEditing: Bool {
        isEditable || allowsInsertionCursor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = layout.hasHorizontalScroller
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = textViewAllowsEditing
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = isEditable
        textView.usesFindPanel = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = layout.textContainerInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.font = HTTPHighlighter.font
        textView.typingAttributes = HTTPHighlighter.typingAttributes
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.enabledTextCheckingTypes = 0
        applyLayout(to: textView, in: scrollView)
        context.coordinator.applyContextMenu(to: textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.apply(text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        textView.isEditable = textViewAllowsEditing
        applyLayout(to: textView, in: scrollView)
        context.coordinator.applyContextMenu(to: textView)

        if textView.string != text {
            context.coordinator.apply(text)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func applyLayout(to textView: NSTextView, in scrollView: NSScrollView) {
        scrollView.hasHorizontalScroller = layout.hasHorizontalScroller
        textView.textContainerInset = layout.textContainerInset
        textView.textContainer?.widthTracksTextView = layout.widthTracksTextView
        textView.isHorizontallyResizable = layout.isHorizontallyResizable
        textView.autoresizingMask = layout.autoresizingMask
        textView.maxSize = layout.maxSize
        textView.textContainer?.containerSize = layout.containerSize(for: scrollView.contentSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedHTTPTextView
        weak var textView: NSTextView?
        private var isApplying = false
        private var highlightTask: Task<Void, Never>?

        init(_ parent: HighlightedHTTPTextView) {
            self.parent = parent
        }

        deinit {
            highlightTask?.cancel()
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, parent.isEditable, let textView else { return }
            parent.text = textView.string
            scheduleRehighlight()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            parent.isEditable
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            switch parent.contextMenuStyle {
            case .none:
                return nil
            case .editable:
                return editableMenu()
            case .readOnly:
                return readOnlyMenu()
            }
        }

        func applyContextMenu(to textView: NSTextView) {
            switch parent.contextMenuStyle {
            case .none:
                textView.menu = nil
            case .editable:
                textView.menu = editableMenu()
            case .readOnly:
                textView.menu = readOnlyMenu()
            }
        }

        @objc private func copyAll(_ sender: Any?) {
            guard let textView else { return }
            Clipboard.copy(textView.string)
        }

        @objc private func cutSelection(_ sender: Any?) {
            textView?.cut(sender)
        }

        @objc private func copySelection(_ sender: Any?) {
            textView?.copy(sender)
        }

        @objc private func pasteClipboard(_ sender: Any?) {
            guard parent.isEditable else { return }
            textView?.paste(sender)
        }

        @objc private func deleteSelection(_ sender: Any?) {
            guard parent.isEditable else { return }
            textView?.delete(sender)
        }

        @objc private func selectAllText(_ sender: Any?) {
            textView?.selectAll(sender)
        }

        @objc private func repeatRequest(_ sender: Any?) {
            parent.repeatRequest?()
        }

        @objc private func copyAsCurl(_ sender: Any?) {
            parent.copyAsCurl?()
        }

        func apply(_ value: String) {
            guard let textView else { return }
            highlightTask?.cancel()
            let selectedRanges = textView.selectedRanges
            isApplying = true
            textView.textStorage?.setAttributedString(HTTPHighlighter.highlight(value))
            textView.typingAttributes = HTTPHighlighter.typingAttributes
            textView.selectedRanges = selectedRanges
            isApplying = false
        }

        private func scheduleRehighlight() {
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                self?.rehighlight()
            }
        }

        func rehighlight() {
            guard let textView else { return }
            let selectedRanges = textView.selectedRanges
            let visibleOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            isApplying = true
            textView.textStorage?.setAttributedString(HTTPHighlighter.highlight(textView.string))
            textView.typingAttributes = HTTPHighlighter.typingAttributes
            textView.selectedRanges = selectedRanges
            if let visibleOrigin, let scrollView = textView.enclosingScrollView {
                scrollView.contentView.scroll(to: visibleOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            isApplying = false
            highlightTask = nil
        }

        private func editableMenu() -> NSMenu {
            let menu = NSMenu()
            menu.allowsContextMenuPlugIns = false

            menu.addItem(menuItem(title: "Repeat", action: #selector(repeatRequest(_:)), target: self))
            menu.addItem(menuItem(title: "Copy as cURL", action: #selector(copyAsCurl(_:)), target: self))

            menu.addItem(.separator())
            menu.addItem(menuItem(title: "Cut", action: #selector(cutSelection(_:)), target: self))
            menu.addItem(menuItem(title: "Copy", action: #selector(copySelection(_:)), target: self))
            menu.addItem(menuItem(title: "Paste", action: #selector(pasteClipboard(_:)), target: self))
            menu.addItem(menuItem(title: "Delete", action: #selector(deleteSelection(_:)), target: self))
            menu.addItem(.separator())
            menu.addItem(menuItem(title: "Select All", action: #selector(selectAllText(_:)), target: self))
            menu.addItem(.separator())
            menu.addItem(menuItem(title: "Copy All", action: #selector(copyAll(_:)), target: self))
            return menu
        }

        private func readOnlyMenu() -> NSMenu {
            let menu = NSMenu()
            menu.allowsContextMenuPlugIns = false
            menu.addItem(menuItem(title: "Copy", action: #selector(copySelection(_:)), target: self))
            menu.addItem(menuItem(title: "Select All", action: #selector(selectAllText(_:)), target: self))
            menu.addItem(.separator())
            menu.addItem(menuItem(title: "Copy All", action: #selector(copyAll(_:)), target: self))
            return menu
        }

        private func menuItem(title: String, action: Selector, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.image = nil
            return item
        }
    }
}

private enum HighlightedTextContextMenuStyle {
    case none
    case editable
    case readOnly
}

private struct HighlightedTextLayout {
    let hasHorizontalScroller: Bool
    let widthTracksTextView: Bool
    let isHorizontallyResizable: Bool
    let autoresizingMask: NSView.AutoresizingMask
    let textContainerInset: NSSize
    let maxSize: NSSize

    static let raw = HighlightedTextLayout(
        hasHorizontalScroller: true,
        widthTracksTextView: false,
        isHorizontallyResizable: true,
        autoresizingMask: [],
        textContainerInset: NSSize(width: 12, height: 0),
        maxSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    )

    static let wrapped = HighlightedTextLayout(
        hasHorizontalScroller: false,
        widthTracksTextView: true,
        isHorizontallyResizable: false,
        autoresizingMask: [.width],
        textContainerInset: NSSize(width: 14, height: 0),
        maxSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )

    func containerSize(for contentSize: NSSize) -> NSSize {
        NSSize(
            width: widthTracksTextView ? max(0, contentSize.width - textContainerInset.width * 2) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}

private enum HTTPHighlighter {
    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static let typingAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.labelColor
    ]

    static func highlight(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.clear,
                .paragraphStyle: paragraphStyle
            ]
        )

        var documentState = DocumentState.detectingStartLine
        var bodyStartLocation: Int?

        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            let line = String(text[lineRange])
            let nsRange = NSRange(lineRange, in: text)
            let nsEnclosingRange = NSRange(enclosingRange, in: text)
            highlightLine(line, range: nsRange, enclosingRange: nsEnclosingRange, state: &documentState, bodyStartLocation: &bodyStartLocation, in: attributed)
        }

        if text.isEmpty {
            return attributed
        }

        if documentState == .body {
            let startLocation = bodyStartLocation ?? 0
            let bodyRange = NSRange(location: startLocation, length: max(0, (text as NSString).length - startLocation))
            highlightBody(in: text, range: bodyRange, attributed: attributed)
        }

        return attributed
    }

    private static func highlightLine(
        _ line: String,
        range: NSRange,
        enclosingRange: NSRange,
        state: inout DocumentState,
        bodyStartLocation: inout Int?,
        in attributed: NSMutableAttributedString
    ) {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if state == .headers {
                state = .body
                bodyStartLocation = enclosingRange.location + enclosingRange.length
            }
            return
        }

        switch state {
        case .detectingStartLine:
            if line.hasPrefix("HTTP/") {
                highlightStatusLine(line, range: range, in: attributed)
                state = .headers
                return
            }

            if let methodRange = requestMethodRange(in: line) {
                let nsMethodRange = NSRange(methodRange, in: line)
                attributed.addAttributes(
                    [.foregroundColor: successColor, .font: boldFont],
                    range: NSRange(location: range.location + nsMethodRange.location, length: nsMethodRange.length)
                )
                highlightRequestLineParts(line, baseRange: range, methodRange: methodRange, in: attributed)
                state = .headers
                return
            }

            state = .body
            bodyStartLocation = range.location
            return

        case .headers:
            highlightHeaderLine(line, range: range, in: attributed)

        case .body:
            if bodyStartLocation == nil {
                bodyStartLocation = range.location
            }
        }
    }

    private static func highlightHeaderLine(_ line: String, range: NSRange, in attributed: NSMutableAttributedString) {
        if line.first?.isWhitespace == true {
            attributed.addAttribute(.foregroundColor, value: headerValueColor, range: range)
            return
        }

        guard let colonIndex = line.firstIndex(of: ":") else { return }

        let keyLength = line.distance(from: line.startIndex, to: colonIndex)
        let valueStart = line.index(after: colonIndex)
        let valueOffset = valueStart.utf16Offset(in: line)
        attributed.addAttributes([.foregroundColor: headerNameColor, .font: boldFont], range: NSRange(location: range.location, length: keyLength))
        attributed.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(location: range.location + keyLength, length: 1))
        attributed.addAttribute(.foregroundColor, value: headerValueColor, range: NSRange(location: range.location + valueOffset, length: max(0, range.length - valueOffset)))
    }

    private static func highlightStatusLine(_ line: String, range: NSRange, in attributed: NSMutableAttributedString) {
        attributed.addAttributes([.foregroundColor: protocolColor, .font: boldFont], range: range)
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count > 1, let codeRange = line.range(of: String(parts[1])) else { return }
        let code = Int(parts[1]) ?? 0
        let color: NSColor = code < 300 ? successColor : code < 400 ? accentColor : code < 500 ? warningColor : dangerColor
        let nsCodeRange = NSRange(codeRange, in: line)
        attributed.addAttributes([.foregroundColor: color, .font: boldFont], range: NSRange(location: range.location + nsCodeRange.location, length: nsCodeRange.length))
    }

    private static func highlightRequestLineParts(_ line: String, baseRange: NSRange, methodRange: Range<String.Index>, in attributed: NSMutableAttributedString) {
        let remainder = line[methodRange.upperBound...].trimmingCharacters(in: .whitespaces)
        let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let path = parts.first, let pathRange = line.range(of: String(path), range: methodRange.upperBound..<line.endIndex) else { return }
        let nsPathRange = NSRange(pathRange, in: line)
        attributed.addAttribute(.foregroundColor, value: accentColor, range: NSRange(location: baseRange.location + nsPathRange.location, length: nsPathRange.length))
        highlightQueryParameters(in: line, targetRange: pathRange, baseRange: baseRange, attributed: attributed)

        guard parts.count > 1, let versionRange = line.range(of: String(parts[1]), range: pathRange.upperBound..<line.endIndex) else { return }
        let nsVersionRange = NSRange(versionRange, in: line)
        attributed.addAttribute(.foregroundColor, value: protocolColor, range: NSRange(location: baseRange.location + nsVersionRange.location, length: nsVersionRange.length))
    }

    private static func highlightQueryParameters(in line: String, targetRange: Range<String.Index>, baseRange: NSRange, attributed: NSMutableAttributedString) {
        guard let queryStart = line[targetRange].firstIndex(of: "?") else { return }
        var cursor = line.index(after: queryStart)

        while cursor < targetRange.upperBound {
            let nameStart = cursor
            while cursor < targetRange.upperBound, line[cursor] != "=", line[cursor] != "&" {
                cursor = line.index(after: cursor)
            }

            if cursor > nameStart {
                let nameRange = NSRange(nameStart..<cursor, in: line)
                attributed.addAttributes([.foregroundColor: parameterNameColor, .font: boldFont], range: NSRange(location: baseRange.location + nameRange.location, length: nameRange.length))
            }

            if cursor < targetRange.upperBound, line[cursor] == "=" {
                let equalsRange = NSRange(cursor..<line.index(after: cursor), in: line)
                attributed.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(location: baseRange.location + equalsRange.location, length: equalsRange.length))
                cursor = line.index(after: cursor)
            }

            let valueStart = cursor
            while cursor < targetRange.upperBound, line[cursor] != "&" {
                cursor = line.index(after: cursor)
            }

            if cursor > valueStart {
                let valueRange = NSRange(valueStart..<cursor, in: line)
                attributed.addAttribute(.foregroundColor, value: stringColor, range: NSRange(location: baseRange.location + valueRange.location, length: valueRange.length))
            }

            if cursor < targetRange.upperBound, line[cursor] == "&" {
                let ampersandRange = NSRange(cursor..<line.index(after: cursor), in: line)
                attributed.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(location: baseRange.location + ampersandRange.location, length: ampersandRange.length))
                cursor = line.index(after: cursor)
            }
        }
    }

    private static func highlightBody(in text: String, range: NSRange, attributed: NSMutableAttributedString) {
        guard range.length > 0, let swiftRange = Range(range, in: text) else { return }
        let body = text[swiftRange]
        let firstToken = body.first { !$0.isWhitespace }
        if firstToken == "{" || firstToken == "[" {
            highlightJSON(in: text, range: range, attributed: attributed)
            return
        }

        if body.contains("="), body.contains("&") {
            highlightFormBody(in: text, range: range, attributed: attributed)
            return
        }

        if firstToken == "<" {
            highlightXMLBody(in: text, range: range, attributed: attributed)
        }
    }

    private static func highlightJSON(in text: String, range: NSRange, attributed: NSMutableAttributedString) {
        guard let swiftRange = Range(range, in: text) else { return }
        var index = swiftRange.lowerBound

        while index < swiftRange.upperBound {
            let character = text[index]

            if character == "\"" {
                let stringStart = index
                index = text.index(after: index)
                var isEscaped = false

                while index < swiftRange.upperBound {
                    let character = text[index]
                    let next = text.index(after: index)
                    if character == "\\", !isEscaped {
                        isEscaped = true
                        index = next
                        continue
                    }
                    if character == "\"", !isEscaped {
                        index = next
                        break
                    }
                    isEscaped = false
                    index = next
                }

                let stringRange = NSRange(stringStart..<index, in: text)
                let color = isJSONStringKey(after: index, upperBound: swiftRange.upperBound, in: text) ? parameterNameColor : stringColor
                attributed.addAttribute(.foregroundColor, value: color, range: stringRange)
                if color == parameterNameColor {
                    attributed.addAttribute(.font, value: boldFont, range: stringRange)
                }
                continue
            }

            if character.isNumber || character == "-" {
                let start = index
                index = text.index(after: index)
                while index < swiftRange.upperBound, isJSONNumberCharacter(text[index]) {
                    index = text.index(after: index)
                }
                attributed.addAttribute(.foregroundColor, value: numberColor, range: NSRange(start..<index, in: text))
                continue
            }

            if let tokenRange = jsonLiteralRange(at: index, upperBound: swiftRange.upperBound, in: text) {
                attributed.addAttributes([.foregroundColor: keywordColor, .font: boldFont], range: NSRange(tokenRange, in: text))
                index = tokenRange.upperBound
                continue
            }

            if "{}[],:".contains(character) {
                attributed.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(index..<text.index(after: index), in: text))
            }

            index = text.index(after: index)
        }
    }

    private static func highlightFormBody(in text: String, range: NSRange, attributed: NSMutableAttributedString) {
        guard let swiftRange = Range(range, in: text) else { return }
        var cursor = swiftRange.lowerBound

        while cursor < swiftRange.upperBound {
            let nameStart = cursor
            while cursor < swiftRange.upperBound, text[cursor] != "=", text[cursor] != "&", text[cursor] != "\n" {
                cursor = text.index(after: cursor)
            }

            if cursor > nameStart {
                attributed.addAttributes([.foregroundColor: parameterNameColor, .font: boldFont], range: NSRange(nameStart..<cursor, in: text))
            }

            if cursor < swiftRange.upperBound, text[cursor] == "=" {
                attributed.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(cursor..<text.index(after: cursor), in: text))
                cursor = text.index(after: cursor)
            }

            let valueStart = cursor
            while cursor < swiftRange.upperBound, text[cursor] != "&", text[cursor] != "\n" {
                cursor = text.index(after: cursor)
            }

            if cursor > valueStart {
                attributed.addAttribute(.foregroundColor, value: stringColor, range: NSRange(valueStart..<cursor, in: text))
            }

            if cursor < swiftRange.upperBound {
                attributed.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(cursor..<text.index(after: cursor), in: text))
                cursor = text.index(after: cursor)
            }
        }
    }

    private static func highlightXMLBody(in text: String, range: NSRange, attributed: NSMutableAttributedString) {
        guard let swiftRange = Range(range, in: text) else { return }
        var cursor = swiftRange.lowerBound

        while cursor < swiftRange.upperBound, let tagStart = text[cursor..<swiftRange.upperBound].firstIndex(of: "<") {
            guard let tagEnd = text[tagStart..<swiftRange.upperBound].firstIndex(of: ">") else { break }
            attributed.addAttributes([.foregroundColor: accentColor, .font: boldFont], range: NSRange(tagStart...tagEnd, in: text))
            cursor = text.index(after: tagEnd)
        }
    }

    private static func isJSONStringKey(after index: String.Index, upperBound: String.Index, in text: String) -> Bool {
        var cursor = index
        while cursor < upperBound, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        return cursor < upperBound && text[cursor] == ":"
    }

    private static func isJSONNumberCharacter(_ character: Character) -> Bool {
        character.isNumber || character == "." || character == "e" || character == "E" || character == "+" || character == "-"
    }

    private static func jsonLiteralRange(at index: String.Index, upperBound: String.Index, in text: String) -> Range<String.Index>? {
        for literal in ["true", "false", "null"] {
            guard text[index..<upperBound].hasPrefix(literal) else { continue }
            let end = text.index(index, offsetBy: literal.count)
            if end == upperBound || !isIdentifierCharacter(text[end]) {
                return index..<end
            }
        }

        return nil
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func requestMethodRange(in line: String) -> Range<String.Index>? {
        HTTPMethod.allCases.compactMap { method in
            let method = method.rawValue
            return line.hasPrefix("\(method) ") ? line.startIndex..<line.index(line.startIndex, offsetBy: method.count) : nil
        }.first
    }

    private enum DocumentState {
        case detectingStartLine
        case headers
        case body
    }

    private static var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
    }

    private static let accentColor = NSColor(calibratedRed: 0.145, green: 0.365, blue: 0.690, alpha: 1)
    private static let successColor = NSColor(calibratedRed: 0.130, green: 0.520, blue: 0.280, alpha: 1)
    private static let warningColor = NSColor(calibratedRed: 0.760, green: 0.425, blue: 0.090, alpha: 1)
    private static let dangerColor = NSColor(calibratedRed: 0.700, green: 0.165, blue: 0.165, alpha: 1)
    private static let protocolColor = NSColor(calibratedRed: 0.285, green: 0.340, blue: 0.520, alpha: 1)
    private static let stringColor = NSColor(calibratedRed: 0.215, green: 0.445, blue: 0.690, alpha: 1)
    private static let headerNameColor = NSColor(calibratedRed: 0.145, green: 0.365, blue: 0.690, alpha: 1)
    private static let headerValueColor = NSColor.secondaryLabelColor
    private static let parameterNameColor = NSColor(calibratedRed: 0.450, green: 0.235, blue: 0.670, alpha: 1)
    private static let keywordColor = NSColor(calibratedRed: 0.365, green: 0.255, blue: 0.690, alpha: 1)
    private static let numberColor = NSColor(calibratedRed: 0.085, green: 0.455, blue: 0.405, alpha: 1)
    private static let punctuationColor = NSColor.tertiaryLabelColor

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 17
        style.maximumLineHeight = 17
        return style
    }
}

private struct EmptyResponseSurface: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "paperplane")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PostmeTheme.accent)
                .frame(width: 36, height: 36)
                .background(PostmeTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to send")
                    .font(.system(size: 14, weight: .semibold))
                Text("Press Command-Return to run the selected raw request. The response will appear here with status, headers, body, timing, and size.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rawSurfaceStyle()
    }
}

private struct ErrorResponseSurface: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PostmeTheme.danger)
                Text("Request failed")
                    .font(.system(size: 13.5, weight: .semibold))
            }

            Text(message)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .rawSurfaceStyle()
    }
}

private struct EditorGutter: View {
    let lineCount: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...min(lineCount, 999), id: \.self) { line in
                Text("\(line)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, height: 17, alignment: .trailing)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .padding(.trailing, 8)
        .frame(width: 48, alignment: .topTrailing)
        .frame(maxHeight: .infinity, alignment: .topTrailing)
        .background(PostmeTheme.gutter)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(PostmeTheme.separator.opacity(0.46))
                .frame(width: 1)
        }
    }
}

private struct MethodBadge: View {
    let method: HTTPMethod

    var body: some View {
        Text(method.rawValue)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 48, height: 20)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.16))
            }
    }

    private var color: Color {
        switch method {
        case .get:
            return PostmeTheme.success
        case .post:
            return PostmeTheme.accent
        case .put, .patch:
            return PostmeTheme.warning
        case .delete:
            return PostmeTheme.danger
        case .head, .options:
            return Color(red: 0.285, green: 0.340, blue: 0.520)
        }
    }
}

private struct SchemeBadge: View {
    let scheme: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scheme.lowercased() == "https" ? "lock" : "network")
                .font(.system(size: 9, weight: .bold))
            Text(scheme)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .frame(width: 58, height: 20)
        .background(PostmeTheme.control, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(PostmeTheme.separator.opacity(0.36))
        }
    }
}

private struct PostmeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 22)
            .background(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(configuration.isPressed ? 1 : 0.75),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(configuration.isPressed ? 0.9 : 0.45))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct RawEditorStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13.5, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(PostmeTheme.editor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PostmeTheme.separator.opacity(0.72))
            }
    }
}

private struct RawSurfaceStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [PostmeTheme.raised, PostmeTheme.editor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius)
                    .stroke(PostmeTheme.separator.opacity(0.62))
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(height: 1)
            }
    }
}

private struct ClickableHoverStyleModifier: ViewModifier {
    @Environment(\.isEnabled) private var environmentEnabled
    @State private var isHovering = false
    var isEnabled = true

    private var isActive: Bool {
        isHovering && isEnabled && environmentEnabled
    }

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? Color.black.opacity(0.08) : .clear, radius: isActive ? 4 : 0, x: 0, y: isActive ? 1 : 0)
            .scaleEffect(isActive ? 1.008 : 1)
            .animation(.easeOut(duration: 0.14), value: isActive)
            .onHover { isHovering in
                self.isHovering = isHovering
            }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled {
                    CursorRectView(cursor: .pointingHand)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectNSView {
        let view = CursorRectNSView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorRectNSView: NSView {
    var cursor: NSCursor = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }
}

private extension View {
    func clickableHoverEffect(isEnabled: Bool = true) -> some View {
        modifier(ClickableHoverStyleModifier(isEnabled: isEnabled))
            .modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }

    func rawEditorStyle() -> some View {
        modifier(RawEditorStyleModifier())
    }

    func rawSurfaceStyle() -> some View {
        modifier(RawSurfaceStyleModifier())
    }
}

#Preview {
    ContentView()
}
