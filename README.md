# Chat File Viewer

Chat File Viewer is a small iOS app for previewing files shared from AI chats and coding tools.

Use it to make mobile chat feel less like a dead-end text window: save or share generated `.html`, `.svg`, `.md`, `.mmd`, and `.txt` files into the app, then render them locally.

## What it does

- Renders raw Mermaid source in a native SwiftUI app.
- Displays standalone SVG.
- Renders HTML snippets and documents.
- Renders Markdown through bundled Marked `18.0.5`.
- Extracts the first Mermaid code fence from Markdown text.
- Opens `.mmd`, `.svg`, `.md`, `.html`, and `.txt` files from the app.
- Adds a Share Extension named `Open in Chat File Viewer` so Files can send text/file input straight to the renderer.
- Bundles Mermaid `11.15.0` locally through `WKWebView`; no hosted renderer is required.

## Build

```bash
xcodegen generate
xcodebuild -project apps/ios/ChatFileViewer.xcodeproj -scheme ChatFileViewer -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Contributing and support

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes.
- Use [GitHub Issues](https://github.com/alexmorris10x/chat-file-viewer/issues) for reproducible bugs and focused feature requests.
- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability.
- Support is best-effort; see [SUPPORT.md](SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).


<!-- canonical-product-docs -->
## Product documentation

Durable Chat File Viewer product documentation starts with [Product Context Brief](docs/product/Product%20Context%20Brief.md) and stays in this repository. Dated work packets and temporary evidence stay in the owning 10x-os lifecycle folder.
