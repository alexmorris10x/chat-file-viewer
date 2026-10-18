import QuickLook
import SwiftUI

/// Browse Google Drive from a home folder (My Drive unless one is pinned).
struct DriveBrowserView: View {
    @ObservedObject var account: GoogleAccount
    @StateObject private var store: DriveStore
    @State private var path: [DriveRoute] = []
    @AppStorage("drive.homeTrail") private var homeTrailData = Data()
    let openLocalFile: () -> Void

    init(account: GoogleAccount, openLocalFile: @escaping () -> Void) {
        self.account = account
        self.openLocalFile = openLocalFile
        _store = StateObject(wrappedValue: DriveStore(account: account))
    }

    private var homeTrail: [FolderRef] {
        let trail = (try? JSONDecoder().decode([FolderRef].self, from: homeTrailData)) ?? []
        return trail.isEmpty ? [.myDrive] : trail
    }

    var body: some View {
        NavigationStack(path: $path) {
            FolderView(
                folder: homeTrail.last ?? .myDrive,
                trail: homeTrail,
                isHome: true,
                actions: actions
            )
            .navigationDestination(for: DriveRoute.self) { route in
                switch route {
                case let .folder(folder, trail):
                    FolderView(folder: folder, trail: trail, isHome: false, actions: actions)
                case let .file(item, trail):
                    DriveFileView(item: item, trail: trail, open: { path.append($0) })
                }
            }
        }
        .environmentObject(store)
    }

    private var actions: FolderView.Actions {
        FolderView.Actions(
            email: account.email ?? "",
            homeName: homeTrail.last?.name ?? FolderRef.myDrive.name,
            setHome: { trail in
                homeTrailData = (try? JSONEncoder().encode(trail)) ?? Data()
                path = []
            },
            resetHome: {
                homeTrailData = Data()
                path = []
            },
            openLocalFile: openLocalFile,
            signOut: { account.signOut() }
        )
    }
}

struct FolderView: View {
    struct Actions {
        let email: String
        let homeName: String
        let setHome: ([FolderRef]) -> Void
        let resetHome: () -> Void
        let openLocalFile: () -> Void
        let signOut: () -> Void
    }

    let folder: FolderRef
    let trail: [FolderRef]
    let isHome: Bool
    let actions: Actions

    @EnvironmentObject private var store: DriveStore
    @State private var items: [DriveItem]?
    @State private var sharedDrives: [FolderRef] = []
    @State private var errorMessage: String?
    @State private var isOffline = false
    @State private var query = ""
    @State private var results: [DriveItem]?
    @State private var isSearching = false

    var body: some View {
        List {
            if let results {
                searchSection(results)
            } else {
                if isOffline {
                    Label("Offline — showing the last saved list.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let items {
                    if items.isEmpty {
                        Text("This folder is empty.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        NavigationLink(value: route(for: item, in: trail)) {
                            DriveItemRow(item: item)
                        }
                    }
                }
                if folder == .myDrive && !sharedDrives.isEmpty {
                    Section("Shared drives") {
                        ForEach(sharedDrives, id: \.self) { drive in
                            NavigationLink(value: DriveRoute.folder(drive, trail: [drive])) {
                                Label(drive.name, systemImage: "externaldrive.fill.badge.person.crop")
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if items == nil && results == nil {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load this folder", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    ProgressView()
                }
            } else if isSearching {
                ProgressView()
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(isHome ? .large : .inline)
        .searchable(text: $query, prompt: "Search all of Drive")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty { results = nil }
        }
        .refreshable { await load() }
        .task { await loadIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
    }

    private var menu: some View {
        Menu {
            if !isHome || folder != .myDrive {
                Button {
                    actions.setHome(trail)
                } label: {
                    Label("Make “\(folder.name)” Home", systemImage: "house")
                }
            }
            if actions.homeName != FolderRef.myDrive.name {
                Button {
                    actions.resetHome()
                } label: {
                    Label("Reset Home to My Drive", systemImage: "arrow.uturn.backward")
                }
            }
            Button {
                actions.openLocalFile()
            } label: {
                Label("Open a File on This Device", systemImage: "folder")
            }
            Section(actions.email) {
                Button(role: .destructive) {
                    actions.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private func searchSection(_ results: [DriveItem]) -> some View {
        if results.isEmpty && !isSearching {
            Text("No files named like “\(query)”.")
                .foregroundStyle(.secondary)
        }
        ForEach(results) { item in
            // Search results don't know their folder path, so their relative links
            // resolve from Drive's top level.
            NavigationLink(value: route(for: item, in: [.myDrive])) {
                DriveItemRow(item: item)
            }
        }
    }

    private func route(for item: DriveItem, in trail: [FolderRef]) -> DriveRoute {
        if item.isFolder {
            let ref = FolderRef(id: item.resolved.id, name: item.name)
            return .folder(ref, trail: trail + [ref])
        }
        return .file(item, trail: trail)
    }

    private func loadIfNeeded() async {
        guard items == nil else { return }
        items = store.cachedChildren(of: folder.id)
        await load()
    }

    private func load() async {
        do {
            items = try await store.children(of: folder.id)
            isOffline = false
            errorMessage = nil
            if folder == .myDrive {
                sharedDrives = (try? await store.client.sharedDrives()) ?? []
            }
        } catch is CancellationError {
        } catch {
            if items == nil {
                errorMessage = error.localizedDescription
            } else {
                isOffline = true
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        results = (try? await store.client.search(text)) ?? []
    }
}

struct DriveItemRow: View {
    let item: DriveItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.title3)
                .foregroundStyle(item.isFolder ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if let modified = item.modifiedTime {
            parts.append(modified.formatted(.relative(presentation: .named)))
        }
        if let size = item.size, !item.isFolder {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One Drive file: rendered when it's text (Markdown, HTML, code, CSV, Mermaid),
/// otherwise shown with Quick Look (images, PDFs, Office files, audio, video).
struct DriveFileView: View {
    enum Phase {
        case loading
        case rendered(MarkupDocument, URL)
        case quickLook(URL)
        case failed(String)
    }

    let item: DriveItem
    let trail: [FolderRef]
    let open: (DriveRoute) -> Void

    @EnvironmentObject private var store: DriveStore
    @Environment(\.openURL) private var openURL
    @State private var phase = Phase.loading
    @State private var linkError: String?

    var body: some View {
        content
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let fileURL {
                        ShareLink(item: fileURL)
                    }
                    Menu {
                        Button {
                            Task { await load(reload: true) }
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        if let link = item.webViewLink, let url = URL(string: link) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open in Google Drive", systemImage: "arrow.up.forward.app")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .task { await load(reload: false) }
            .alert("Couldn't open that link", isPresented: Binding(
                get: { linkError != nil },
                set: { if !$0 { linkError = nil } }
            )) {
                Button("OK", role: .cancel) { linkError = nil }
            } message: {
                Text(linkError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .rendered(document, _):
            MarkupRenderView(
                document: document,
                renderContext: MarkupRenderContext(
                    baseURL: store.baseURL(for: trail),
                    schemeHandler: store.schemeHandler,
                    onOpenLink: handleLink
                )
            )
            .ignoresSafeArea(edges: .bottom)
        case let .quickLook(url):
            QuickLookView(url: url)
                .ignoresSafeArea(edges: .bottom)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't open “\(item.name)”", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(reload: true) } }
            }
        }
    }

    private var fileURL: URL? {
        switch phase {
        case let .rendered(_, url), let .quickLook(url):
            return url
        default:
            return nil
        }
    }

    private func load(reload: Bool) async {
        if reload || fileURL == nil {
            phase = .loading
        }
        do {
            let url = try await store.localFile(for: item, reload: reload)
            let tooBigToRender = (item.size ?? 0) > 8_000_000
            if item.opensAsText && !tooBigToRender {
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                phase = .rendered(MarkupDocument.forFile(named: item.localFileName, text: text), url)
            } else {
                phase = .quickLook(url)
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func handleLink(_ url: URL) {
        guard url.scheme == DriveLink.scheme else {
            openURL(url)
            return
        }
        Task {
            do {
                open(try await store.route(for: url, from: trail))
            } catch {
                linkError = error.localizedDescription
            }
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
