import Foundation
import UniformTypeIdentifiers
import WebKit

/// Drive access for the views: folder listings and file copies cached on the device
/// (so anything opened once also opens offline), and resolution of the relative
/// links and images inside rendered pages.
@MainActor
final class DriveStore: ObservableObject {
    enum StoreError: LocalizedError {
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case let .notFound(path):
                return "Couldn't find “\(path)” in Google Drive."
            }
        }
    }

    let client: DriveClient
    private(set) lazy var schemeHandler = DriveSchemeHandler(store: self)
    private var childCache: [String: DriveItem] = [:]
    private let cacheRoot: URL

    init(account: GoogleAccount, cacheRoot: URL? = nil) {
        client = DriveClient { [weak account] forceRefresh in
            guard let account else { throw GoogleAccount.AccountError.notSignedIn }
            return try await account.validAccessToken(forceRefresh: forceRefresh)
        }
        self.cacheRoot = cacheRoot ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drive", isDirectory: true)
    }

    // MARK: Listings

    func cachedChildren(of folderID: String) -> [DriveItem]? {
        guard let data = try? Data(contentsOf: listingURL(folderID)) else { return nil }
        return try? JSONDecoder.drive.decode([DriveItem].self, from: data)
    }

    func children(of folderID: String) async throws -> [DriveItem] {
        let items = try await client.children(of: folderID)
        remember(items, in: folderID)
        let url = listingURL(folderID)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
        return items
    }

    // MARK: Files

    /// The local copy of a file, downloading it if this version isn't cached yet.
    func localFile(for item: DriveItem, reload: Bool = false) async throws -> URL {
        let folder = cacheRoot
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(Self.safeName(item.resolved.id), isDirectory: true)
        let url = folder
            .appendingPathComponent(Self.safeName(item.contentVersion), isDirectory: true)
            .appendingPathComponent(Self.safeName(item.localFileName))
        if !reload, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let data = try await client.content(of: item)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Links inside pages

    func baseURL(for trail: [FolderRef]) -> URL {
        DriveLink.baseURL(rootID: trail.first?.id ?? FolderRef.myDrive.id, folderNames: trail.dropFirst().map(\.name))
    }

    /// Where a tapped `cfv-drive:` link leads, with the trail for its own links.
    func route(for url: URL, from trail: [FolderRef]) async throws -> DriveRoute {
        guard let link = DriveLink(url: url) else {
            throw StoreError.notFound(url.absoluteString)
        }
        let root = trail.first?.id == link.rootID
            ? trail[0]
            : FolderRef(id: link.rootID, name: "Folder")
        var folders = [root]
        var parent = root.id
        for (index, name) in link.names.enumerated() {
            let item = try await child(named: name, in: parent, path: link.names.prefix(index + 1).joined(separator: "/"))
            let isLast = index == link.names.count - 1
            if item.isFolder {
                let ref = FolderRef(id: item.resolved.id, name: item.name)
                folders.append(ref)
                parent = ref.id
                if isLast { return .folder(ref, trail: folders) }
            } else if isLast {
                return .file(item, trail: folders)
            } else {
                throw StoreError.notFound(link.names.joined(separator: "/"))
            }
        }
        return .folder(root, trail: [root])
    }

    /// The file a page's relative image, stylesheet or script points to.
    func file(at url: URL) async throws -> DriveItem {
        guard let link = DriveLink(url: url), !link.names.isEmpty else {
            throw StoreError.notFound(url.absoluteString)
        }
        var parent = link.rootID
        for (index, name) in link.names.enumerated() {
            let item = try await child(named: name, in: parent, path: link.names.prefix(index + 1).joined(separator: "/"))
            if index == link.names.count - 1 {
                guard !item.isFolder else { throw StoreError.notFound(link.names.joined(separator: "/")) }
                return item
            }
            guard item.isFolder else { throw StoreError.notFound(link.names.joined(separator: "/")) }
            parent = item.resolved.id
        }
        throw StoreError.notFound(link.names.joined(separator: "/"))
    }

    private func child(named name: String, in folderID: String, path: String) async throws -> DriveItem {
        let key = folderID + "/" + name
        if let item = childCache[key] { return item }
        if let item = cachedChildren(of: folderID)?.first(where: { $0.name == name }) {
            childCache[key] = item
            return item
        }
        guard let item = try await client.child(named: name, in: folderID) else {
            throw StoreError.notFound(path)
        }
        childCache[key] = item
        return item
    }

    private func remember(_ items: [DriveItem], in folderID: String) {
        for item in items {
            childCache[folderID + "/" + item.name] = item
        }
    }

    private func listingURL(_ folderID: String) -> URL {
        cacheRoot
            .appendingPathComponent("listings", isDirectory: true)
            .appendingPathComponent(Self.safeName(folderID) + ".json")
    }

    nonisolated static func safeName(_ value: String) -> String {
        let cleaned = value.map { character -> Character in
            character == "/" || character == ":" ? "_" : character
        }
        let name = String(cleaned)
        return name.isEmpty || name == "." || name == ".." ? "_" : name
    }
}

/// `cfv-drive://drive/<root folder id>/<folder>/<folder>/<file>` — a page's base URL
/// and the links resolved against it. Folder and file names are percent-encoded.
struct DriveLink: Equatable {
    static let scheme = "cfv-drive"

    let rootID: String
    let names: [String]

    static func baseURL(rootID: String, folderNames: [String]) -> URL {
        let segments = [rootID] + folderNames
        var components = URLComponents()
        components.scheme = scheme
        components.host = "drive"
        components.percentEncodedPath = "/" + segments.map(encode).joined(separator: "/") + "/"
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        else {
            return nil
        }
        let segments = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.removingPercentEncoding ?? String($0) }
        guard let rootID = segments.first else { return nil }
        self.rootID = rootID
        self.names = Array(segments.dropFirst())
    }

    private static func encode(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;?#%")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}

/// Serves a rendered page's relative files (images, stylesheets, scripts) from Drive.
@MainActor
final class DriveSchemeHandler: NSObject, WKURLSchemeHandler {
    private weak var store: DriveStore?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(store: DriveStore) {
        self.store = store
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        tasks[id] = Task { [weak self] in
            do {
                guard let store = self?.store else { throw URLError(.cancelled) }
                let item = try await store.file(at: url)
                let fileURL = try await store.localFile(for: item)
                let data = try Data(contentsOf: fileURL)
                guard let self, self.tasks[id] != nil else { return }
                let fileExtension = (item.localFileName as NSString).pathExtension
                let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? item.resolved.mimeType
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": mimeType,
                        "Content-Length": String(data.count),
                        "Access-Control-Allow-Origin": "*"
                    ]
                )!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
                self.tasks[id] = nil
            } catch {
                guard let self, self.tasks[id] != nil else { return }
                urlSchemeTask.didFailWithError(error)
                self.tasks[id] = nil
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
    }
}
