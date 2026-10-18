import Foundation
import UniformTypeIdentifiers

/// One Drive file or folder, as returned by the Drive v3 API.
struct DriveItem: Codable, Hashable, Identifiable {
    struct ShortcutDetails: Codable, Hashable {
        let targetId: String?
        let targetMimeType: String?
    }

    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let size: Int64?
    let md5Checksum: String?
    let webViewLink: String?
    let shortcutDetails: ShortcutDetails?
    let parents: [String]?
    /// False for files other people shared; those render without access to Drive.
    let ownedByMe: Bool?

    init(
        id: String,
        name: String,
        mimeType: String,
        modifiedTime: Date? = nil,
        size: Int64? = nil,
        md5Checksum: String? = nil,
        webViewLink: String? = nil,
        shortcutDetails: ShortcutDetails? = nil,
        parents: [String]? = nil,
        ownedByMe: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.size = size
        self.md5Checksum = md5Checksum
        self.webViewLink = webViewLink
        self.shortcutDetails = shortcutDetails
        self.parents = parents
        self.ownedByMe = ownedByMe
    }

    enum CodingKeys: String, CodingKey {
        case id, name, mimeType, modifiedTime, size, md5Checksum, webViewLink, shortcutDetails, parents, ownedByMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        modifiedTime = try container.decodeIfPresent(Date.self, forKey: .modifiedTime)
        // The API sends sizes as strings; the local cache stores numbers.
        if let text = try? container.decodeIfPresent(String.self, forKey: .size) {
            size = Int64(text)
        } else {
            size = try container.decodeIfPresent(Int64.self, forKey: .size)
        }
        md5Checksum = try container.decodeIfPresent(String.self, forKey: .md5Checksum)
        webViewLink = try container.decodeIfPresent(String.self, forKey: .webViewLink)
        shortcutDetails = try container.decodeIfPresent(ShortcutDetails.self, forKey: .shortcutDetails)
        parents = try container.decodeIfPresent([String].self, forKey: .parents)
        ownedByMe = try container.decodeIfPresent(Bool.self, forKey: .ownedByMe)
    }

    static let folderMimeType = "application/vnd.google-apps.folder"
    static let shortcutMimeType = "application/vnd.google-apps.shortcut"

    /// The item a shortcut points to keeps the shortcut's name.
    var resolved: DriveItem {
        guard mimeType == Self.shortcutMimeType,
              let targetId = shortcutDetails?.targetId,
              let targetMimeType = shortcutDetails?.targetMimeType
        else {
            return self
        }
        return DriveItem(
            id: targetId,
            name: name,
            mimeType: targetMimeType,
            modifiedTime: modifiedTime,
            webViewLink: webViewLink,
            parents: parents,
            ownedByMe: ownedByMe
        )
    }

    var isShortcut: Bool {
        mimeType == Self.shortcutMimeType
    }

    var isFolder: Bool {
        resolved.mimeType == Self.folderMimeType
    }

    var isGoogleNative: Bool {
        resolved.mimeType.hasPrefix("application/vnd.google-apps.") && !isFolder
    }

    /// How a Google Docs editors file is downloaded, or nil if it can't be.
    var export: (mimeType: String, fileExtension: String)? {
        switch resolved.mimeType {
        case "application/vnd.google-apps.document":
            return ("text/html", "html")
        case "application/vnd.google-apps.spreadsheet", "application/vnd.google-apps.presentation":
            return ("application/pdf", "pdf")
        case "application/vnd.google-apps.drawing":
            return ("image/png", "png")
        default:
            return nil
        }
    }

    /// The file name used for the local copy and for choosing a renderer.
    var localFileName: String {
        guard let export else { return name }
        return (name as NSString).pathExtension.lowercased() == export.fileExtension
            ? name
            : "\(name).\(export.fileExtension)"
    }

    /// Changes whenever the file's content changes, so cached copies stay correct.
    var contentVersion: String {
        // A shortcut's own dates don't change when its target is edited.
        if isShortcut { return "shortcut" }
        if let md5Checksum { return md5Checksum }
        if let modifiedTime { return String(Int(modifiedTime.timeIntervalSince1970)) }
        return "unversioned"
    }

    var opensAsText: Bool {
        if export?.mimeType == "text/html" { return true }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        if Self.textExtensions.contains(fileExtension)
            || MarkupDocument.codeLanguages[fileExtension] != nil
            || MarkupDocument.codeLanguages[name.lowercased()] != nil {
            return true
        }
        let mime = resolved.mimeType
        return mime.hasPrefix("text/")
            || ["application/json", "application/xml", "application/javascript", "image/svg+xml"].contains(mime)
    }

    static let textExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "html", "htm", "xhtml", "svg", "mmd", "mermaid",
        "txt", "text", "log", "csv", "tsv"
    ]

    var symbolName: String {
        if isFolder { return "folder.fill" }
        switch resolved.mimeType {
        case "application/vnd.google-apps.document": return "doc.richtext"
        case "application/vnd.google-apps.spreadsheet": return "tablecells"
        case "application/vnd.google-apps.presentation": return "rectangle.on.rectangle"
        default: break
        }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "md", "markdown", "txt", "text", "log": return "doc.text"
        case "html", "htm": return "globe"
        case "csv", "tsv": return "tablecells"
        case "mmd", "mermaid": return "point.3.connected.trianglepath.dotted"
        case "pdf": return "doc.richtext"
        case "zip", "zst", "gz", "tar": return "doc.zipper"
        default: break
        }
        if MarkupDocument.codeLanguages[fileExtension] != nil {
            return "chevron.left.forwardslash.chevron.right"
        }
        if let type = UTType(mimeType: resolved.mimeType) {
            if type.conforms(to: .image) { return "photo" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
            if type.conforms(to: .audio) { return "waveform" }
        }
        return "doc"
    }
}

struct DriveFileList: Decodable {
    let files: [DriveItem]
    let nextPageToken: String?
}

struct SharedDriveList: Decodable {
    struct SharedDrive: Decodable {
        let id: String
        let name: String
    }

    let drives: [SharedDrive]
    let nextPageToken: String?
}

/// A folder on the path from the browsing root to the current folder.
struct FolderRef: Codable, Hashable {
    let id: String
    let name: String

    static let myDrive = FolderRef(id: "root", name: "My Drive")
}

enum DriveRoute: Hashable {
    /// `trail` runs from the browsing root to this folder, inclusive.
    case folder(FolderRef, trail: [FolderRef])
    /// `trail` runs from the browsing root to the folder holding the file.
    case file(DriveItem, trail: [FolderRef])
}

extension JSONDecoder {
    static let drive: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let text = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(text)")
        }
        return decoder
    }()
}
