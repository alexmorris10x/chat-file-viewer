import SwiftUI
import WebKit

struct MarkupRenderView: UIViewRepresentable {
    let document: MarkupDocument

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.scrollView.bouncesZoom = true
        webView.scrollView.pinchGestureRecognizer?.isEnabled = true
        load(document, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        load(document, in: webView, coordinator: context.coordinator)
    }

    private func load(_ document: MarkupDocument, in webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.loadedDocument != document else { return }
        coordinator.loadedDocument = document
        webView.loadHTMLString(renderHTML(for: document), baseURL: Bundle.main.resourceURL)
    }

    private func renderHTML(for document: MarkupDocument) -> String {
        if document.kind == .html {
            return standaloneHTML(from: document.source)
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          \(Self.viewportMeta)
          <script>\(Self.mermaidScript)</script>
          <script>\(Self.markedScript)</script>
          <style>
            :root {
              color-scheme: dark;
              background: #0b0f14;
              color: #eef2ff;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            html, body {
              width: 100%;
              min-height: 100%;
              margin: 0;
              background: #0b0f14;
            }
            body {
              box-sizing: border-box;
              padding: max(16px, env(safe-area-inset-top)) max(16px, env(safe-area-inset-right)) max(16px, env(safe-area-inset-bottom)) max(16px, env(safe-area-inset-left));
            }
            #preview {
              width: 100%;
              overflow: auto;
            }
            .mermaid {
              width: max-content;
              max-width: 1200px;
              overflow: visible;
            }
            svg {
              width: auto;
              max-width: none;
              height: auto;
            }
            .mermaid svg {
              min-width: 640px;
            }
            .error {
              max-width: 680px;
              color: #fecaca;
              background: #450a0a;
              border: 1px solid #ef4444;
              border-radius: 8px;
              padding: 14px;
              white-space: pre-wrap;
            }
            .markdown {
              max-width: 760px;
              margin: 0 auto;
              line-height: 1.55;
              font-size: 16px;
            }
            .markdown h1, .markdown h2, .markdown h3 {
              line-height: 1.15;
            }
            .markdown pre {
              overflow: auto;
              background: #111827;
              border: 1px solid #374151;
              border-radius: 8px;
              padding: 12px;
            }
            .markdown code {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
            }
            .markdown img, .markdown video {
              max-width: 100%;
              height: auto;
            }
            .markdown table {
              display: block;
              max-width: 100%;
              overflow-x: auto;
              border-collapse: collapse;
            }
            .markdown th, .markdown td {
              border: 1px solid #374151;
              padding: 8px 10px;
              text-align: left;
            }
            .svg-preview {
              display: flex;
              align-items: flex-start;
              justify-content: flex-start;
              min-width: max-content;
            }
          </style>
        </head>
        <body>
          <main id="preview"></main>
          <script>
            const source = \(jsonLiteral(document.source));
            const kind = "\(document.kind.rawValue)";

            function showError(error) {
              document.body.innerHTML = "<pre class='error'>" + String(error) + "</pre>";
            }

            async function render() {
              try {
                const preview = document.getElementById("preview");

                if (kind === "mermaid") {
                  preview.innerHTML = "<pre class='mermaid'></pre>";
                  preview.querySelector(".mermaid").textContent = source;
                  mermaid.initialize({
                    startOnLoad: false,
                    theme: "dark",
                    securityLevel: "strict"
                  });
                  await mermaid.run({ querySelector: ".mermaid" });
                  return;
                }

                if (kind === "svg") {
                  preview.className = "svg-preview";
                  preview.innerHTML = source;
                  return;
                }

                preview.className = "markdown";
                preview.innerHTML = marked.parse(source);
                for (const code of preview.querySelectorAll("code.language-mermaid, code.language-mmd")) {
                  const mermaidBlock = document.createElement("pre");
                  mermaidBlock.className = "mermaid";
                  mermaidBlock.textContent = code.textContent;
                  const pre = code.closest("pre");
                  if (pre) {
                    pre.replaceWith(mermaidBlock);
                  }
                }
                if (preview.querySelector(".mermaid")) {
                  mermaid.initialize({
                    startOnLoad: false,
                    theme: "dark",
                    securityLevel: "strict"
                  });
                  await mermaid.run({ querySelector: ".mermaid" });
                }
              } catch (error) {
                showError(error);
              }
            }
            window.addEventListener("load", render);
            window.addEventListener("error", function(event) {
              showError(event.message);
            });
          </script>
        </body>
        </html>
        """
    }

    private func standaloneHTML(from source: String) -> String {
        let viewportPattern = #"<meta\b(?=[^>]*\bname\s*=\s*["']viewport["'])[^>]*>"#
        if let expression = try? NSRegularExpression(
            pattern: viewportPattern,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            if expression.firstMatch(in: source, range: range) != nil {
                return expression.stringByReplacingMatches(
                    in: source,
                    range: range,
                    withTemplate: Self.viewportMeta
                )
            }
        }

        if let headEnd = source.range(of: "</head>", options: .caseInsensitive) {
            var result = source
            result.insert(contentsOf: "\(Self.viewportMeta)\n", at: headEnd.lowerBound)
            return result
        }

        if let headStart = source.range(of: "<head", options: .caseInsensitive),
           let openingTagEnd = source.range(
               of: ">",
               range: headStart.lowerBound..<source.endIndex
           ) {
            var result = source
            result.insert(contentsOf: "\n\(Self.viewportMeta)", at: openingTagEnd.upperBound)
            return result
        }

        if let htmlStart = source.range(of: "<html", options: .caseInsensitive),
           let openingTagEnd = source.range(
               of: ">",
               range: htmlStart.lowerBound..<source.endIndex
           ) {
            var result = source
            result.insert(
                contentsOf: "\n<head>\(Self.viewportMeta)</head>",
                at: openingTagEnd.upperBound
            )
            return result
        }

        if source.range(of: "<!doctype", options: .caseInsensitive) != nil,
           let doctypeEnd = source.range(of: ">") {
            var result = source
            result.insert(
                contentsOf: "\n<head>\(Self.viewportMeta)</head>",
                at: doctypeEnd.upperBound
            )
            return result
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          \(Self.viewportMeta)
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0;
              padding: 20px;
              box-sizing: border-box;
              font: 17px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              overflow-wrap: anywhere;
            }
            img, video { max-width: 100%; height: auto; }
            table { display: block; max-width: 100%; overflow-x: auto; }
          </style>
        </head>
        <body>
          \(source)
        </body>
        </html>
        """
    }

    private func jsonLiteral(_ text: String) -> String {
        guard
            let data = try? JSONEncoder().encode(text),
            let literal = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        return literal.replacingOccurrences(of: "</script>", with: "<\\/script>")
    }

    private static let mermaidScript: String = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "txt"),
              let script = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "window.mermaidLoadError = 'Could not load bundled Mermaid renderer.';"
        }

        return script.replacingOccurrences(of: "</script>", with: "<\\/script>")
    }()

    private static let markedScript: String = {
        guard let url = Bundle.main.url(forResource: "marked.min", withExtension: "txt"),
              let script = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "window.marked = { parse: function(value) { return '<pre>' + value + '</pre>'; } };"
        }

        return script.replacingOccurrences(of: "</script>", with: "<\\/script>")
    }()

    private static let viewportMeta =
        #"<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes, viewport-fit=cover">"#

    final class Coordinator {
        var loadedDocument: MarkupDocument?
    }
}
