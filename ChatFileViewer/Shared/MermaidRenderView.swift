import SwiftUI
import WebKit

struct MarkupRenderView: UIViewRepresentable {
    let document: MarkupDocument

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(renderHTML(for: document), baseURL: Bundle.main.resourceURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(renderHTML(for: document), baseURL: Bundle.main.resourceURL)
    }

    private func renderHTML(for document: MarkupDocument) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
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
            .html-preview {
              background: #ffffff;
              color: #111827;
              border-radius: 8px;
              padding: 16px;
              min-height: calc(100vh - 32px);
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

                if (kind === "html") {
                  preview.className = "html-preview";
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
}
