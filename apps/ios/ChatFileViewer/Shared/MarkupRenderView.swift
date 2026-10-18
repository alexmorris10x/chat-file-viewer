import SwiftUI
import WebKit

/// Where a rendered page lives: the base URL its relative links and images resolve
/// against, an optional handler that serves those files, and what to do when the
/// reader taps a link. The default renders a standalone document, as before.
struct MarkupRenderContext {
    var baseURL: URL?
    var schemeHandler: WKURLSchemeHandler?
    var onOpenLink: ((URL) -> Void)?

    static let standalone = MarkupRenderContext()
}

struct MarkupRenderView: UIViewRepresentable {
    let document: MarkupDocument
    var renderContext: MarkupRenderContext = .standalone

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        if let handler = renderContext.schemeHandler, let scheme = renderContext.baseURL?.scheme {
            configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.scrollView.bouncesZoom = true
        webView.scrollView.pinchGestureRecognizer?.isEnabled = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.onOpenLink = renderContext.onOpenLink
        load(document, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenLink = renderContext.onOpenLink
        load(document, in: webView, coordinator: context.coordinator)
    }

    private func load(_ document: MarkupDocument, in webView: WKWebView, coordinator: Coordinator) {
        let key = Coordinator.LoadKey(document: document, baseURL: renderContext.baseURL)
        guard coordinator.loaded != key else { return }
        coordinator.loaded = key
        if document.kind == .html {
            let base = renderContext.baseURL ?? Self.applicationBaseURL
            coordinator.loadedBaseURL = base
            webView.loadHTMLString(standaloneHTML(from: document.source), baseURL: base)
        } else {
            let base = renderContext.baseURL ?? Bundle.main.resourceURL
            coordinator.loadedBaseURL = base
            webView.loadHTMLString(renderHTML(for: document), baseURL: base)
        }
    }

    private func renderHTML(for document: MarkupDocument) -> String {
        if document.kind == .html {
            return standaloneHTML(from: document.source)
        }

        return #"""
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          \#(Self.viewportMeta)
          <script>\#(Self.mermaidScript)</script>
          <script>\#(Self.markedScript)</script>
          <script>\#(Self.highlightScript)</script>
          <style>\#(Self.highlightTheme)</style>
          <style>
            :root {
              color-scheme: light dark;
              --bg: #0b0f14;
              --fg: #eef2ff;
              --muted: #9ca3af;
              --panel: #111827;
              --line: #374151;
              --link: #7dd3fc;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            @media (prefers-color-scheme: light) {
              :root {
                --bg: #ffffff;
                --fg: #111827;
                --muted: #6b7280;
                --panel: #f3f4f6;
                --line: #d1d5db;
                --link: #0369a1;
              }
            }
            html, body {
              width: 100%;
              min-height: 100%;
              margin: 0;
              background: var(--bg);
              color: var(--fg);
            }
            body {
              box-sizing: border-box;
              padding: max(16px, env(safe-area-inset-top)) max(16px, env(safe-area-inset-right)) max(16px, env(safe-area-inset-bottom)) max(16px, env(safe-area-inset-left));
            }
            a { color: var(--link); }
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
              overflow-wrap: anywhere;
            }
            .markdown h1, .markdown h2, .markdown h3 {
              line-height: 1.15;
            }
            .markdown pre, pre.code, pre.plain {
              overflow: auto;
              background: var(--panel);
              border: 1px solid var(--line);
              border-radius: 8px;
              padding: 12px;
            }
            pre.code, pre.plain {
              margin: 0;
              font-size: 13px;
              line-height: 1.5;
            }
            pre.plain {
              white-space: pre-wrap;
              overflow-wrap: anywhere;
            }
            code, pre {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
            }
            pre code.hljs {
              padding: 0;
              background: transparent;
            }
            .markdown img, .markdown video {
              max-width: 100%;
              height: auto;
            }
            .markdown table, table.csv {
              display: block;
              max-width: 100%;
              overflow-x: auto;
              border-collapse: collapse;
            }
            .markdown th, .markdown td, table.csv th, table.csv td {
              border: 1px solid var(--line);
              padding: 8px 10px;
              text-align: left;
              vertical-align: top;
            }
            table.csv {
              font-size: 13px;
            }
            table.csv th {
              position: sticky;
              top: 0;
              background: var(--panel);
            }
            .note {
              color: var(--muted);
              font-size: 13px;
              margin: 10px 0;
            }
            details.front-matter {
              color: var(--muted);
              font-size: 13px;
              margin-bottom: 12px;
            }
            iframe.render-frame {
              display: block;
              width: 100%;
              height: 120px;
              border: 0;
              margin: 12px 0;
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
            const source = \#(jsonLiteral(document.source));
            const kind = "\#(document.kind.rawValue)";
            const language = \#(jsonLiteral(document.language ?? ""));
            const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
            let frameCount = 0;

            function showError(error) {
              document.body.innerHTML = "<pre class='error'></pre>";
              document.body.firstChild.textContent = String(error);
            }

            function initMermaid() {
              mermaid.initialize({
                startOnLoad: false,
                theme: dark ? "dark" : "default",
                securityLevel: "strict"
              });
            }

            // An html-render block runs in a sandboxed frame that reports its height.
            function frameDocument(html, id) {
              // Content sized to the frame itself (100vh) has no height of its own, so
              // the frame only resizes when the content differs from the frame.
              const reporter = "<script>(function(){function post(){" +
                "var h=Math.ceil(document.documentElement.getBoundingClientRect().height);" +
                "if(Math.abs(h-window.innerHeight)>1){parent.postMessage({cfvFrame:" + JSON.stringify(id) + ",height:h},'*');}}" +
                "new ResizeObserver(post).observe(document.documentElement);addEventListener('load',post);post();})();<\/script>";
              if (/<\/body>/i.test(html)) {
                return html.replace(/<\/body>/i, reporter + "</body>");
              }
              const color = dark ? "#eef2ff" : "#111827";
              return "<!doctype html><html><head><meta charset='utf-8'>" +
                "<meta name='viewport' content='width=device-width, initial-scale=1'>" +
                "<style>:root{color-scheme:light dark}html,body{margin:0;background:transparent}" +
                "body{font:15px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;color:" + color + "}</style>" +
                "</head><body>" + html + reporter + "</body></html>";
            }

            // A frame whose content grows with the frame (e.g. min-height: 100vh)
            // would keep growing, so each frame gets a bounded number of resizes.
            const frameResizes = {};
            window.addEventListener("message", function(event) {
              const data = event.data;
              if (data && data.cfvFrame && typeof data.height === "number") {
                const frame = document.getElementById(data.cfvFrame);
                const count = (frameResizes[data.cfvFrame] || 0) + 1;
                frameResizes[data.cfvFrame] = count;
                if (frame && count <= 40) {
                  frame.style.height = Math.min(20000, Math.max(20, data.height)) + "px";
                }
              }
            });

            function parseCSV(text, separator) {
              const rows = [];
              let row = [], field = "", quoted = false;
              for (let i = 0; i < text.length; i++) {
                const c = text[i];
                if (quoted) {
                  if (c === '"') {
                    if (text[i + 1] === '"') { field += '"'; i++; } else { quoted = false; }
                  } else {
                    field += c;
                  }
                } else if (c === '"') {
                  quoted = true;
                } else if (c === separator) {
                  row.push(field); field = "";
                } else if (c === "\n") {
                  row.push(field); rows.push(row); row = []; field = "";
                } else if (c !== "\r") {
                  field += c;
                }
              }
              if (field.length || row.length) { row.push(field); rows.push(row); }
              return rows;
            }

            function renderCSV(preview) {
              const rows = parseCSV(source, language || ",");
              const limit = 2000;
              const table = document.createElement("table");
              table.className = "csv";
              rows.slice(0, limit + 1).forEach(function(cells, index) {
                const tr = document.createElement("tr");
                cells.forEach(function(value) {
                  const cell = document.createElement(index === 0 ? "th" : "td");
                  cell.textContent = value;
                  tr.appendChild(cell);
                });
                table.appendChild(tr);
              });
              preview.appendChild(table);
              if (rows.length > limit + 1) {
                const note = document.createElement("p");
                note.className = "note";
                note.textContent = "Showing the first " + limit.toLocaleString() + " of " + (rows.length - 1).toLocaleString() + " rows.";
                preview.appendChild(note);
              }
            }

            function renderCode(preview) {
              const pre = document.createElement("pre");
              pre.className = "code";
              const code = document.createElement("code");
              code.textContent = source;
              pre.appendChild(code);
              preview.appendChild(pre);
              if (language && source.length < 400000 && hljs.getLanguage(language)) {
                code.className = "language-" + language;
                hljs.highlightElement(code);
              }
            }

            function splitFrontMatter(text) {
              const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n/.exec(text);
              return match ? { meta: match[1], body: text.slice(match[0].length) } : { meta: null, body: text };
            }

            async function renderMarkdown(preview) {
              preview.className = "markdown";
              const parts = splitFrontMatter(source);
              preview.innerHTML = marked.parse(parts.body);
              if (parts.meta) {
                const details = document.createElement("details");
                details.className = "front-matter";
                const summary = document.createElement("summary");
                summary.textContent = "Page details";
                const pre = document.createElement("pre");
                pre.textContent = parts.meta;
                details.append(summary, pre);
                preview.prepend(details);
              }
              let hasMermaid = false;
              for (const code of preview.querySelectorAll("pre > code")) {
                const pre = code.parentElement;
                const languageClass = Array.from(code.classList).find(function(name) { return name.startsWith("language-"); });
                const fence = languageClass ? languageClass.slice("language-".length).toLowerCase() : "";
                if (fence === "mermaid" || fence === "mmd") {
                  const block = document.createElement("pre");
                  block.className = "mermaid";
                  block.textContent = code.textContent;
                  pre.replaceWith(block);
                  hasMermaid = true;
                } else if (fence === "html-render" || fence === "html-preview") {
                  const frame = document.createElement("iframe");
                  frame.id = "cfv-frame-" + (++frameCount);
                  frame.className = "render-frame";
                  frame.setAttribute("sandbox", "allow-scripts allow-popups");
                  frame.srcdoc = frameDocument(code.textContent, frame.id);
                  pre.replaceWith(frame);
                } else if (fence && hljs.getLanguage(fence)) {
                  hljs.highlightElement(code);
                }
              }
              if (hasMermaid) {
                initMermaid();
                await mermaid.run({ querySelector: ".mermaid" });
              }
            }

            async function render() {
              try {
                const preview = document.getElementById("preview");

                if (kind === "mermaid") {
                  preview.innerHTML = "<pre class='mermaid'></pre>";
                  preview.querySelector(".mermaid").textContent = source;
                  initMermaid();
                  await mermaid.run({ querySelector: ".mermaid" });
                  return;
                }

                if (kind === "svg") {
                  preview.className = "svg-preview";
                  preview.innerHTML = source;
                  return;
                }

                if (kind === "code") {
                  renderCode(preview);
                  return;
                }

                if (kind === "text") {
                  const pre = document.createElement("pre");
                  pre.className = "plain";
                  pre.textContent = source;
                  preview.appendChild(pre);
                  return;
                }

                if (kind === "csv") {
                  renderCSV(preview);
                  return;
                }

                await renderMarkdown(preview);
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
        """#
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

        // "<" as \u003c keeps "</script>" and "<!--" in the text from ending or
        // swallowing the surrounding script element.
        return literal.replacingOccurrences(of: "<", with: "\\u003c")
    }

    private static func bundledText(_ name: String, fallback: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return fallback
        }

        return text.replacingOccurrences(of: "</script>", with: "<\\/script>")
    }

    private static let mermaidScript = bundledText(
        "mermaid.min",
        fallback: "window.mermaidLoadError = 'Could not load bundled Mermaid renderer.';"
    )

    private static let markedScript = bundledText(
        "marked.min",
        fallback: "window.marked = { parse: function(value) { return '<pre>' + value + '</pre>'; } };"
    )

    private static let highlightScript = bundledText(
        "highlight.min",
        fallback: "window.hljs = { getLanguage: function() { return null; }, highlightElement: function() {} };"
    )

    private static let highlightTheme = bundledText("highlight-theme.css", fallback: "")

    private static let viewportMeta =
        #"<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes, viewport-fit=cover">"#

    private static let applicationBaseURL = URL(
        string: "https://\(Bundle.main.bundleIdentifier?.lowercased() ?? "com.10x.chatfileviewer")/"
    )

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        struct LoadKey: Equatable {
            let document: MarkupDocument
            let baseURL: URL?
        }

        var loaded: LoadKey?
        var loadedBaseURL: URL?
        var onOpenLink: ((URL) -> Void)?

        /// With a link handler (Drive pages), taps open through the handler and
        /// nothing else may replace the page: script redirects, meta refreshes and
        /// form posts are blocked. Frames inside the page load normally.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard
                let onOpenLink,
                let url = navigationAction.request.url,
                navigationAction.targetFrame?.isMainFrame ?? true,
                !Self.isSameDocument(url, as: webView.url)
            else {
                return .allow
            }
            if navigationAction.navigationType == .linkActivated {
                onOpenLink(url)
                return .cancel
            }
            if url.scheme == "about" || url.absoluteString == loadedBaseURL?.absoluteString {
                return .allow
            }
            return .cancel
        }

        /// Links that ask for a new window (`target="_blank"`) open the same way as taps.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                onOpenLink?(url)
            }
            return nil
        }

        static func isSameDocument(_ url: URL, as current: URL?) -> Bool {
            guard let current, url.fragment != nil else { return false }
            var target = URLComponents(url: url, resolvingAgainstBaseURL: true)
            var page = URLComponents(url: current, resolvingAgainstBaseURL: true)
            target?.fragment = nil
            page?.fragment = nil
            return target?.url == page?.url
        }
    }
}
