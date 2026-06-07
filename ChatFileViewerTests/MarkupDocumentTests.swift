import XCTest
@testable import ChatFileViewer

final class MarkupDocumentTests: XCTestCase {
    func testUsesRawMermaidWhenNoFenceExists() {
        let document = MarkupDocument.detect(from: "flowchart LR\n  A --> B")

        XCTAssertEqual(document.source, "flowchart LR\n  A --> B")
        XCTAssertEqual(document.kind, .mermaid)
    }

    func testTreatsMermaidFenceAsMarkdownDocument() {
        let markdown = """
        # Example

        ```mermaid
        sequenceDiagram
          Alice->>Bob: Hello
        ```
        """

        let document = MarkupDocument.detect(from: markdown)

        XCTAssertEqual(document.kind, .markdown)
    }

    func testDetectsSVG() {
        let document = MarkupDocument.detect(from: "<svg viewBox=\"0 0 10 10\"><circle cx=\"5\" cy=\"5\" r=\"5\" /></svg>")

        XCTAssertEqual(document.kind, .svg)
    }

    func testDetectsHTML() {
        let document = MarkupDocument.detect(from: "<article><h1>Hello</h1></article>")

        XCTAssertEqual(document.kind, .html)
    }
}
