import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PostmeStore()
    @State private var isCommandPalettePresented = false
    @State private var responseViewMode: ResponseViewMode = .raw
    @State private var responseSearchText = ""

    var body: some View {
        GeometryReader { proxy in
            HSplitView {
                SidebarView(store: store)
                    .frame(minWidth: 220, idealWidth: 236, maxWidth: 264, maxHeight: .infinity)

                if let box = store.bindingForSelectedRequest() {
                    VStack(spacing: 0) {
                        RequestCommandBar(
                            request: Binding(get: box.get, set: box.set),
                            store: store,
                            response: store.response,
                            errorMessage: store.errorMessage,
                            isSending: store.isSending,
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
                    .frame(minWidth: 920, idealWidth: 1140, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No Request", systemImage: "tray")
                        .frame(minWidth: 920, idealWidth: 1140, maxHeight: .infinity)
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
        .frame(minWidth: 1120, minHeight: 720)
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
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                store.flushPersistence()
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var store: PostmeStore

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PostmeTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Postme")
                            .font(.footnote.weight(.semibold))
                        Text("Repeater Workspace")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    store.addRequest()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New request")
                .accessibilityLabel("New request")
                .contentShape(Rectangle())
                .keyboardShortcut("n", modifiers: .command)
                .pointingHandCursor()
            }
            .padding(.horizontal, 10)
            .padding(.top, 5)

            SidebarModeRail(selection: $store.sidebarMode)
                .padding(.horizontal, 10)

            switch store.sidebarMode {
            case .collection:
                CollectionListView(store: store)
            case .history:
                HistoryListView(store: store)
            case .environment:
                EnvironmentEditorView(store: store)
            }
        }
        .background(PostmeTheme.sidebar)
    }
}

private struct CollectionListView: View {
    @ObservedObject var store: PostmeStore

    var body: some View {
        List(selection: $store.selectedRequestID) {
            Section {
                ForEach(store.requests) { request in
                    SidebarRequestRow(request: request, isSelected: store.selectedRequestID == request.id)
                    .tag(request.id)
                    .onTapGesture(count: 2) {
                        store.selectRequest(request.id)
                        Task { await store.sendSelectedRequest() }
                    }
                }
            } header: {
                Text("Requests")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PostmeTheme.sidebar)
        .contextMenu {
            Button("Duplicate") { store.duplicateSelectedRequest() }
            Button("Delete", role: .destructive) { store.deleteSelectedRequest() }
        }
    }
}

private struct HistoryListView: View {
    @ObservedObject var store: PostmeStore

    var body: some View {
        List {
            if store.history.isEmpty {
                SidebarEmptyState(
                    systemImage: "clock.badge.questionmark",
                    title: "No history yet",
                    subtitle: "Sent requests will appear here with status, timing, and errors."
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.history) { entry in
                    Button {
                        store.loadHistory(entry)
                    } label: {
                        HistoryEntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 1)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PostmeTheme.sidebar)
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                MethodBadge(method: entry.request.method)
                Text(entry.request.url)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                StatusDot(color: statusColor)
                Text(statusText)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Text(entry.sentAt, style: .relative)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusText: String {
        if let response = entry.response {
            return response.statusLine
        }
        return entry.errorMessage ?? "Failed"
    }

    private var statusColor: Color {
        if let response = entry.response {
            return HTTPStatusTone.color(for: response.statusCode)
        }
        return PostmeTheme.danger
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
                .pointingHandCursor()
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
    var response: ResponseSnapshot?
    var errorMessage: String?
    var isSending: Bool
    let responseViewMode: ResponseViewMode
    @Binding var responseSearchText: String

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                MethodBadge(method: request.method)
                SchemeBadge(scheme: requestScheme)
                RequestURLField(url: request.url)

                Button {
                    Task { await store.sendSelectedRequest() }
                } label: {
                    Label(store.isSending ? "Sending" : "Send", systemImage: store.isSending ? "hourglass" : "paperplane.fill")
                        .frame(width: 84)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(PostmeTheme.accent)
                .accessibilityLabel(store.isSending ? "Sending" : "Send request")
                .disabled(store.isSending || rawBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pointingHandCursor(isEnabled: !store.isSending && !rawBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

                Spacer(minLength: 12)

                if let response {
                    ResponseStatusPill(response: response)
                    MetricPill(value: "\(Int(response.duration * 1000)) ms")
                    MetricPill(value: ByteCountFormatter.string(fromByteCount: Int64(response.size), countStyle: .file))
                } else if isSending {
                    MetricPill(value: "Sending")
                } else if errorMessage != nil {
                    MetricPill(value: "Error")
                } else {
                    MetricPill(value: "No response")
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
                    if let response {
                        Clipboard.copy(displayText(for: response))
                    }
                }
                .disabled(response == nil)
                .opacity(response == nil ? 0.45 : 1)
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

    private func displayText(for response: ResponseSnapshot) -> String {
        let value: String
        switch responseViewMode {
        case .raw:
            value = response.rawHTTPText
        case .pretty:
            value = response.prettyBody
        case .hex:
            value = response.rawHTTPText.hexDump()
        }

        let trimmedSearch = responseSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return value }

        return value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(trimmedSearch) }
            .joined(separator: "\n")
    }
}

private struct RequestURLField: View {
    let url: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(url)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
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
            RawPane(title: "Request", subtitle: "Edit request line, headers, blank line, and body directly", systemImage: "doc.plaintext") {
                RawRequestEditor(text: rawBinding)
                    .onAppear {
                        if request.rawRequest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                            request.rawRequest = store.ensureRawRequest(for: request)
                        }
                    }
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
                RawPane(title: "Request Failed", subtitle: "Transport or protocol error", systemImage: "exclamationmark.triangle", accent: PostmeTheme.danger, accessory: {
                    responseModePicker
                }) {
                    ErrorResponseSurface(message: errorMessage)
                }
                .padding(PostmeLayout.panePadding)
            } else if let response {
                RawPane(title: responsePaneTitle, subtitle: responsePaneSubtitle(for: response), systemImage: "doc.plaintext", accent: HTTPStatusTone.color(for: response.statusCode), accessory: {
                    responseModePicker
                }) {
                    RawResponseSurface(text: displayText(for: response))
                }
                .padding(PostmeLayout.panePadding)
            } else {
                RawPane(title: "Response", subtitle: emptyResponseSubtitle, systemImage: "doc.plaintext", accent: .secondary, accessory: {
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
        Picker("", selection: $viewMode) {
            ForEach(ResponseViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 166)
    }

    private var emptyResponseSubtitle: String {
        isSending
            ? "Waiting for raw HTTP response"
            : "Raw HTTP response, headers, timing, and size will appear here"
    }

    private func displayText(for response: ResponseSnapshot) -> String {
        let value = baseDisplayText(for: response)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return value }

        let matches = matchingLines(in: value, query: trimmedSearch)
        return matches.isEmpty ? "No response lines match \"\(trimmedSearch)\"." : matches.joined(separator: "\n")
    }

    private func baseDisplayText(for response: ResponseSnapshot) -> String {
        switch viewMode {
        case .raw:
            return response.rawHTTPText
        case .pretty:
            return response.prettyBody
        case .hex:
            return response.rawHTTPText.hexDump()
        }
    }

    private func matchingLines(in value: String, query: String) -> [String.SubSequence] {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var responsePaneTitle: String {
        switch viewMode {
        case .raw:
            return "Raw response"
        case .pretty:
            return "Pretty body"
        case .hex:
            return "Hex dump"
        }
    }

    private func responsePaneSubtitle(for response: ResponseSnapshot) -> String {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let count = matchingLines(in: baseDisplayText(for: response), query: trimmedSearch).count
            return count == 1
                ? "1 matching line for \"\(trimmedSearch)\""
                : "\(count) matching lines for \"\(trimmedSearch)\""
        }

        switch viewMode {
        case .raw:
            return "Socket bytes rendered as HTTP"
        case .pretty:
            return "Formatted response body"
        case .hex:
            return "Raw response bytes as hexadecimal"
        }
    }
}

private enum ResponseViewMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case pretty = "Pretty"
    case hex = "Hex"

    var id: String { rawValue }
}

private struct CommandPaletteView: View {
    @ObservedObject var store: PostmeStore
    @Binding var isPresented: Bool
    @State private var query = ""
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search commands, requests, history, variables", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isSearchFocused)
                        .onSubmit {
                            runFirstItem()
                        }
                        .onExitCommand {
                            isPresented = false
                        }
                    Text("esc")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .separatorColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(16)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredItems) { item in
                            Button {
                                run(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.systemImage)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(item.group)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .animation(.easeInOut(duration: 0.18), value: filteredItems.first?.id)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.return, modifiers: [])
                            .background(item.id == filteredItems.first?.id ? PostmeTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        }

                        if filteredItems.isEmpty {
                            ContentUnavailableView("No Commands", systemImage: "command", description: Text("Try another search."))
                                .padding(.vertical, 34)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 430)
            }
            .frame(minWidth: 620, idealWidth: 680, maxWidth: 760)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor))
            }
            .shadow(color: .black.opacity(0.24), radius: 30, y: 18)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            isSearchFocused = true
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
            ),
            CommandPaletteItem(
                title: "Show Collection",
                subtitle: "Switch sidebar to saved requests",
                group: "View",
                systemImage: "folder",
                keywords: ["requests"],
                run: { store.sidebarMode = .collection }
            ),
            CommandPaletteItem(
                title: "Show History",
                subtitle: "Switch sidebar to sent requests",
                group: "View",
                systemImage: "clock.arrow.circlepath",
                keywords: ["recent"],
                run: { store.sidebarMode = .history }
            ),
            CommandPaletteItem(
                title: "Show Environment",
                subtitle: "Switch sidebar to variables",
                group: "View",
                systemImage: "curlybraces",
                keywords: ["variables", "env"],
                run: { store.sidebarMode = .environment }
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
            CommandPaletteItem(
                title: entry.request.url,
                subtitle: "\(entry.request.method.rawValue) \(entry.response?.statusLine ?? entry.errorMessage ?? "Failed")",
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

    private func runFirstItem() {
        guard let item = filteredItems.first else { return }
        run(item)
    }

    private func run(_ item: CommandPaletteItem) {
        item.run()
        isPresented = false
    }
}

private struct CommandPaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let group: String
    let systemImage: String
    let keywords: [String]
    let run: () -> Void
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
    static let window = Color(red: 0.936, green: 0.942, blue: 0.948)
    static let sidebar = Color(red: 0.906, green: 0.915, blue: 0.924)
    static let toolbar = Color(red: 0.928, green: 0.936, blue: 0.944).opacity(0.98)
    static let control = Color(red: 0.976, green: 0.979, blue: 0.982)
    static let raised = Color(red: 0.996, green: 0.997, blue: 0.998)
    static let editor = Color(red: 0.989, green: 0.991, blue: 0.994)
    static let gutter = Color(red: 0.936, green: 0.942, blue: 0.948)
    static let separator = Color(red: 0.742, green: 0.766, blue: 0.790)
    static let accent = Color(red: 0.145, green: 0.365, blue: 0.690)
    static let accentSoft = Color(red: 0.145, green: 0.365, blue: 0.690).opacity(0.11)
    static let success = Color(red: 0.130, green: 0.520, blue: 0.280)
    static let danger = Color(red: 0.700, green: 0.165, blue: 0.165)
    static let warning = Color(red: 0.760, green: 0.425, blue: 0.090)
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
    static let requestToolbarHeight: CGFloat = 68
    static let panePadding: CGFloat = 12
    static let cornerRadius: CGFloat = 7
}

private struct PostmeBackdrop: View {
    var body: some View {
        ZStack {
            PostmeTheme.window
            LinearGradient(
                colors: [
                    Color.white.opacity(0.34),
                    Color(red: 0.88, green: 0.895, blue: 0.910).opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct SidebarModeRail: View {
    @Binding var selection: SidebarMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SidebarMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.rawValue, systemImage: icon(for: mode))
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundStyle(selection == mode ? PostmeTheme.accent : .secondary)
                        .background(selection == mode ? PostmeTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(mode.rawValue)
                .pointingHandCursor()
            }
        }
        .padding(1.5)
        .background(PostmeTheme.window.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(PostmeTheme.separator.opacity(0.45))
        }
    }

    private func icon(for mode: SidebarMode) -> String {
        switch mode {
        case .collection:
            return "folder"
        case .history:
            return "clock.arrow.circlepath"
        case .environment:
            return "curlybraces"
        }
    }
}

private struct SidebarRequestRow: View {
    let request: APIRequest
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? PostmeTheme.accent : Color.clear)
                .frame(width: 2, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    MethodBadge(method: request.method)
                    Text(request.displayName)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                }
                HStack(spacing: 4) {
                    Text(hostText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(pathText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 3)
            .padding(.trailing, 6)
        }
        .padding(.leading, 5)
        .background(isSelected ? PostmeTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: PostmeLayout.cornerRadius)
                    .stroke(PostmeTheme.accent.opacity(0.22))
            }
        }
        .contentShape(Rectangle())
    }

    private var hostText: String {
        if let url = URL(string: request.url), let host = url.host {
            return host
        }
        return request.url.replacingOccurrences(of: "{{baseUrl}}", with: "$baseUrl")
    }

    private var pathText: String {
        guard let url = URL(string: request.url) else { return "" }
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path += "?\(query)"
        }
        return path
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
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .pointingHandCursor()
    }
}

private struct RawRequestEditor: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 0) {
            EditorGutter(lineCount: lineCount)
            HighlightedHTTPTextView(text: $text, isEditable: true, wrapsLines: false)
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
        HighlightedHTTPTextView(text: .constant(text), isEditable: false, wrapsLines: true)
            .contextMenu {
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rawSurfaceStyle()
    }
}

private struct HighlightedHTTPTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let wrapsLines: Bool
    private var layout: HighlightedTextLayout {
        wrapsLines ? .wrapped : .raw
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
        textView.isEditable = isEditable
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
        applyLayout(to: textView, in: scrollView)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.apply(text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable
        applyLayout(to: textView, in: scrollView)

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
            guard !isApplying, let textView else { return }
            parent.text = textView.string
            scheduleRehighlight()
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
    }
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

        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = String(text[lineRange])
            let nsRange = NSRange(lineRange, in: text)
            highlightLine(line, range: nsRange, in: attributed)
        }

        return attributed
    }

    private static func highlightLine(_ line: String, range: NSRange, in attributed: NSMutableAttributedString) {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        if line.hasPrefix("HTTP/") {
            highlightStatusLine(line, range: range, in: attributed)
            return
        }

        if let methodRange = requestMethodRange(in: line) {
            let nsMethodRange = NSRange(methodRange, in: line)
            attributed.addAttributes(
                [.foregroundColor: successColor, .font: boldFont],
                range: NSRange(location: range.location + nsMethodRange.location, length: nsMethodRange.length)
            )
            highlightRequestLineParts(line, baseRange: range, methodRange: methodRange, in: attributed)
            return
        }

        if let colonIndex = line.firstIndex(of: ":") {
            let keyLength = line.distance(from: line.startIndex, to: colonIndex)
            let valueStart = line.index(after: colonIndex)
            let valueOffset = valueStart.utf16Offset(in: line)
            attributed.addAttributes([.foregroundColor: accentColor, .font: boldFont], range: NSRange(location: range.location, length: keyLength))
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: range.location + valueOffset, length: max(0, range.length - valueOffset)))
            return
        }

        highlightJSONFragments(line, baseRange: range, in: attributed)
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

        guard parts.count > 1, let versionRange = line.range(of: String(parts[1]), range: pathRange.upperBound..<line.endIndex) else { return }
        let nsVersionRange = NSRange(versionRange, in: line)
        attributed.addAttribute(.foregroundColor, value: protocolColor, range: NSRange(location: baseRange.location + nsVersionRange.location, length: nsVersionRange.length))
    }

    private static func highlightJSONFragments(_ line: String, baseRange: NSRange, in attributed: NSMutableAttributedString) {
        var index = line.startIndex
        while index < line.endIndex, let quoteStart = line[index...].firstIndex(of: "\"") {
            var scanIndex = line.index(after: quoteStart)
            var quoteEnd: String.Index?
            var isEscaped = false

            while scanIndex < line.endIndex {
                let character = line[scanIndex]
                if character == "\\" {
                    isEscaped.toggle()
                } else {
                    if character == "\"", !isEscaped {
                        quoteEnd = scanIndex
                        break
                    }
                    isEscaped = false
                }
                scanIndex = line.index(after: scanIndex)
            }

            guard let quoteEnd else { break }
            let nsRange = NSRange(quoteStart...quoteEnd, in: line)
            attributed.addAttribute(.foregroundColor, value: stringColor, range: NSRange(location: baseRange.location + nsRange.location, length: nsRange.length))
            index = line.index(after: quoteEnd)
        }
    }

    private static func requestMethodRange(in line: String) -> Range<String.Index>? {
        let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
        return methods.compactMap { method in
            line.hasPrefix("\(method) ") ? line.startIndex..<line.index(line.startIndex, offsetBy: method.count) : nil
        }.first
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

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 17
        style.maximumLineHeight = 17
        return style
    }
}

private struct EmptyResponseSurface: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Send a request")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Press Command-Return to run the selected raw request.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rawSurfaceStyle()
    }
}

private struct ErrorResponseSurface: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
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

private struct PointingHandCursorModifier: ViewModifier {
    var isEnabled = true

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            guard isEnabled else { return }
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
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
