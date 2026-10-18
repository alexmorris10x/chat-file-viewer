import Foundation

/// Read-only Google Drive v3 calls. Every request carries a fresh access token and
/// retries once with a refreshed token if Drive answers 401.
struct DriveClient {
    enum DriveError: LocalizedError {
        case http(Int, String)
        case cannotDownload(String)

        var errorDescription: String? {
            switch self {
            case let .http(status, message):
                return message.isEmpty ? "Google Drive returned HTTP \(status)." : message
            case let .cannotDownload(name):
                return "“\(name)” can't be downloaded. Open it in Google Drive instead."
            }
        }
    }

    let accessToken: (_ forceRefresh: Bool) async throws -> String
    var session: URLSession = .shared

    static let itemFields = "id,name,mimeType,modifiedTime,size,md5Checksum,webViewLink,shortcutDetails(targetId,targetMimeType)"

    func children(of folderID: String) async throws -> [DriveItem] {
        try await list(
            query: "'\(Self.escape(folderID))' in parents and trashed = false",
            orderBy: "folder,name_natural"
        )
    }

    func search(_ text: String) async throws -> [DriveItem] {
        try await list(
            query: "name contains '\(Self.escape(text))' and trashed = false",
            orderBy: "folder,modifiedTime desc",
            limit: 200
        )
    }

    /// The most recently modified child with exactly this name, if any.
    func child(named name: String, in folderID: String) async throws -> DriveItem? {
        try await list(
            query: "name = '\(Self.escape(name))' and '\(Self.escape(folderID))' in parents and trashed = false",
            orderBy: "modifiedTime desc",
            limit: 1
        ).first
    }

    func sharedDrives() async throws -> [FolderRef] {
        var drives: [FolderRef] = []
        var pageToken: String?
        repeat {
            var items = [URLQueryItem(name: "pageSize", value: "100")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: SharedDriveList = try await get("drives", query: items)
            drives += page.drives.map { FolderRef(id: $0.id, name: $0.name) }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return drives
    }

    /// The file's bytes; Google Docs editors files are exported (Docs as HTML).
    func content(of item: DriveItem) async throws -> Data {
        let target = item.resolved
        if let export = item.export {
            return try await data(
                "files/\(target.id)/export",
                query: [URLQueryItem(name: "mimeType", value: export.mimeType)]
            )
        }
        if item.isGoogleNative {
            throw DriveError.cannotDownload(item.name)
        }
        return try await data(
            "files/\(target.id)",
            query: [
                URLQueryItem(name: "alt", value: "media"),
                URLQueryItem(name: "supportsAllDrives", value: "true")
            ]
        )
    }

    private func list(query: String, orderBy: String, limit: Int? = nil) async throws -> [DriveItem] {
        var results: [DriveItem] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "orderBy", value: orderBy),
                URLQueryItem(name: "pageSize", value: String(min(limit ?? 1000, 1000))),
                URLQueryItem(name: "fields", value: "nextPageToken,files(\(Self.itemFields))"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: DriveFileList = try await get("files", query: items)
            results += page.files
            pageToken = page.nextPageToken
            if let limit, results.count >= limit { break }
        } while pageToken != nil
        return results
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        try JSONDecoder.drive.decode(T.self, from: try await data(path, query: query))
    }

    private func data(_ path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/\(path)")!
        components.queryItems = query
        // URLComponents leaves "+" alone, which Google reads as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        let url = components.url!
        var forceRefresh = false
        while true {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await accessToken(forceRefresh))", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && !forceRefresh {
                forceRefresh = true
                continue
            }
            guard (200..<300).contains(status) else {
                throw DriveError.http(status, Self.message(from: data))
            }
            return data
        }
    }

    /// Escapes a value for a single-quoted Drive query string.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private static func message(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message ?? ""
    }
}
