import Foundation

struct MarkupDocument: Equatable {
    enum Kind: String {
        case mermaid
        case svg
        case html
        case markdown
    }

    let source: String
    let kind: Kind

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
