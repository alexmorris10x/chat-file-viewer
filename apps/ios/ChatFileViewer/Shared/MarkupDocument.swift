import Foundation

struct MarkupDocument: Equatable {
    enum Kind: String {
        case mermaid
        case svg
        case html
        case markdown
        case code
        case text
        case csv
    }

    let source: String
    let kind: Kind
    /// highlight.js language for `.code`, or the field separator for `.csv`.
    let language: String?

    init(source: String, kind: Kind, language: String? = nil) {
        self.source = source
        self.kind = kind
        self.language = language
    }

    static func detect(from text: String) -> MarkupDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? MarkupSamples.markdownExample : trimmed

        if looksLikeMermaid(source) {
            return MarkupDocument(source: source, kind: .mermaid)
        }

        if looksLikeSVG(source) {
            return MarkupDocument(source: source, kind: .svg)
        }

        if looksLikeHTML(source) {
            return MarkupDocument(source: source, kind: .html)
        }

        return MarkupDocument(source: source, kind: .markdown)
    }

    /// Chooses the renderer from the file name first, then falls back to the content.
    static func forFile(named name: String, text: String) -> MarkupDocument {
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "md", "markdown", "mdown", "mkd":
            return MarkupDocument(source: text, kind: .markdown)
        case "html", "htm", "xhtml":
            return MarkupDocument(source: text, kind: .html)
        case "svg":
            return MarkupDocument(source: text, kind: .svg)
        case "mmd", "mermaid":
            return MarkupDocument(source: text, kind: .mermaid)
        case "csv":
            return MarkupDocument(source: text, kind: .csv, language: ",")
        case "tsv":
            return MarkupDocument(source: text, kind: .csv, language: "\t")
        case "txt", "text", "log":
            return MarkupDocument(source: text, kind: .text)
        default:
            if let language = codeLanguages[fileExtension] {
                return MarkupDocument(source: text, kind: .code, language: language)
            }
            if let language = codeLanguages[name.lowercased()] {
                return MarkupDocument(source: text, kind: .code, language: language)
            }
            return detect(from: text)
        }
    }

    /// File extensions (and a few whole file names) that render as highlighted code.
    static let codeLanguages: [String: String] = [
        "swift": "swift", "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "jsx": "javascript", "ts": "typescript", "tsx": "typescript", "py": "python",
        "rb": "ruby", "go": "go", "rs": "rust", "java": "java", "kt": "kotlin", "kts": "kotlin",
        "c": "c", "h": "c", "cc": "cpp", "cpp": "cpp", "hpp": "cpp", "m": "objectivec",
        "mm": "objectivec", "cs": "csharp", "php": "php", "sh": "bash", "bash": "bash",
        "zsh": "bash", "json": "json", "jsonl": "json", "yaml": "yaml", "yml": "yaml",
        "toml": "ini", "ini": "ini", "conf": "ini", "css": "css", "scss": "scss", "less": "less",
        "sql": "sql", "xml": "xml", "plist": "xml", "graphql": "graphql", "gql": "graphql",
        "diff": "diff", "patch": "diff", "lua": "lua", "r": "r", "pl": "perl",
        "makefile": "makefile", "mk": "makefile"
    ]

    private static func looksLikeMermaid(_ text: String) -> Bool {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        return [
            "flowchart", "graph", "sequencediagram", "statediagram", "statediagram-v2",
            "classdiagram", "erdiagram", "journey", "gantt", "pie", "mindmap",
            "timeline", "gitgraph", "quadrantchart", "requirementdiagram",
            "c4context", "sankey-beta", "xychart-beta", "block-beta", "architecture-beta"
        ].contains { firstLine.hasPrefix($0) }
    }

    private static func looksLikeSVG(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("<svg") && lowercased.contains("</svg>")
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.hasPrefix("<!doctype html")
            || lowercased.hasPrefix("<html")
            || lowercased.hasPrefix("<body")
            || lowercased.hasPrefix("<article")
            || lowercased.hasPrefix("<section")
            || lowercased.hasPrefix("<div")
            || lowercased.hasPrefix("<table")
            || lowercased.hasPrefix("<p")
    }
}

enum MarkupSamples {
    static let markdownExample = """
    # Chat File Viewer

    Preview Mermaid, SVG, Markdown, and HTML files from mobile chats and coding tools.

    ```mermaid
    flowchart LR
      Chat["Mobile chat"]
      File["Shared file"]
      Detect["Detect type"]
      Render["Render preview"]
      Share["Use from Files"]

      Chat --> File --> Detect --> Render --> Share
    ```
    """
}
