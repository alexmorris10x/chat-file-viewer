# Chat File Viewer — Product Context Brief

**Audience:** AI or Voice-mode product partner
**Current as of:** 2026-07-24
**Source snapshot:** `main` at `9219fc8` (`Chat File Viewer` 0.1.0, build 1), plus the untracked Xcode Cloud target manifest present in the working tree
**Evidence status:** The implementation was inspected in live source. No current compile/link result, physical-device observation, App Store state, or production-use result was verified for this brief.

## How to advise on this product

Keep Chat File Viewer a small, dependable escape hatch for mobile chat artifacts. The near-term question is whether opening and sharing the supported formats is trustworthy on a real iPhone, not how to turn it into a general editor, file manager, cloud service, or authoring suite.

Favor a short end-to-end evidence pass over speculative feature breadth. Do not call a format supported merely because its text detector exists; support means the file opens from Files and the share sheet, renders legibly, handles malformed input, and does not create an unacceptable active-content risk.

## Product in one minute

Chat File Viewer is for people receiving generated files from AI chats and coding tools on an iPhone or iPad. Mobile chat can show a link or attachment but often cannot make a Mermaid diagram, SVG, Markdown document, or HTML artifact useful. The app accepts one text-based file, detects its markup, and renders it locally.

The main experience is deliberately direct: see a rendered preview, inspect or edit the source underneath it, open another file, or share the current source. A Share Extension named **Open in Chat File Viewer** can render a file or text without first navigating through the app.

The differentiator is local, format-aware previewing. Mermaid 11.15.0 and Marked 18.0.5 are bundled in the app and run inside a `WKWebView`; the renderer does not depend on a hosted Mermaid or Markdown service.

## Current product structure

| Surface | Input | Current behavior |
| --- | --- | --- |
| Main app | `.mmd`, `.svg`, `.md`, `.html`, `.txt`, or pasted/edited text | Detects the content, renders a preview, keeps the source editable, and can share the source |
| Share Extension | One file or a text item | Loads the shared text, detects the format, renders it, and dismisses with Done |
| Raw Mermaid | Text beginning with a recognized Mermaid diagram declaration | Renders with the bundled Mermaid library using its dark theme and strict security level |
| SVG | Text containing an opening and closing SVG element | Inserts the SVG into a scrollable preview |
| HTML | Text beginning with one of several common document/body elements | Inserts the markup into a light preview surface |
| Markdown or plain text | Everything else | Parses with bundled Marked; Mermaid code fences inside Markdown are rendered as diagrams |

The app starts with an example document. Empty input also resolves back to that example rather than showing an empty state. File import is single-selection and uses iOS security-scoped access while reading UTF-8 text.

## Confirmed current implementation

**Implemented:** The repository contains an iOS 17 SwiftUI app, an embedded Share Extension, a unit-test target, and a UI-test target. The main app display name is **Chat File Viewer** and the bundle identifier is `com.10x.chatfileviewer`.

**Implemented:** `MarkupDocument` uses lightweight content detection rather than trusting only the file extension. It recognizes raw Mermaid by its first line, checks for complete SVG markup, recognizes several common HTML opening elements, and otherwise treats the source as Markdown.

**Implemented:** `MarkupRenderView` uses a local `WKWebView` with JavaScript enabled. It bundles Mermaid and Marked as resource files, JSON-encodes source before placing it into the render document, escapes closing script tags in that literal, and shows render errors in the preview.

**Implemented:** The Share Extension advertises support for one file, text, and one web URL. Its loader currently handles a file URL, plain text, or text. It does not contain a dedicated web-URL loading path, so the advertised web-URL activation rule is broader than the loader’s explicit behavior.

**Implemented:** Four focused unit tests cover raw Mermaid, fenced Mermaid inside Markdown, SVG detection, and HTML detection. One UI smoke test checks that the navigation bar appears after launch. These files are test coverage in source; the tests were not run for this documentation update.

**Implemented:** The repository is public-facing and MIT-licensed, with contribution, security, support, CI, ownership, and issue-template controls. The untracked Xcode Cloud manifest identifies the `ChatFileViewer` target but does not itself prove any cloud build completed.

## Evidence boundary

- **Decided:** The checked-in README and product structure establish a narrow local preview utility for artifacts from mobile chats and coding tools.
- **Implemented:** Main-app import/edit/share, content detection, four render modes, bundled render libraries, and the Share Extension are present at the source snapshot above.
- **Compile/link verified:** Unverified for the current snapshot. CI is configured to build the app and tests for a generic iOS Simulator, but no current CI result was inspected.
- **Manually verified:** Unverified. No current iPhone or iPad journey was observed.
- **Unverified:** Real Files and share-sheet compatibility across all advertised extensions; large-file behavior; malformed markup; VoiceOver and Dynamic Type; rendering on iPad; offline behavior after install; release/signing state; and the safety of opening untrusted HTML or SVG.

The working tree is not clean: it contains an untracked Xcode Cloud manifest. The manifest was included in the inspection and left unchanged.

## Approved ambition versus current scaffold

The source supports a useful prototype-sized promise: turn a small set of text artifacts into readable local previews. There is no current product document approving a broader document workspace, persistence library, syntax editor, export system, or hosted collaboration layer.

The renderer’s convenience should not be mistaken for a settled trust model. Mermaid uses a strict security setting, but HTML and SVG are inserted as markup into a JavaScript-enabled web view. Whether the product is for the user’s own generated artifacts or arbitrary files from other people materially changes the security requirement.

## Current priority and decision gate

The next gate is a bounded real-device artifact pass. On one current iPhone, open a valid and malformed example of Mermaid, Markdown-with-Mermaid, SVG, HTML, and plain text from Files; then repeat the supported cases through **Open in Chat File Viewer**. Record whether each loads, renders, scrolls, edits, shares, and fails safely.

After that pass, decide the trust boundary:

- personal/generated artifacts only, with clear product language; or
- arbitrary shared artifacts, which requires a stronger HTML/SVG sanitization and navigation policy.

Until the file/share matrix and trust boundary are resolved, broader editing and library features are premature.

## Locked constraints and deferred work

- Keep rendering local and avoid a hosted renderer unless a concrete requirement changes the privacy or reliability tradeoff.
- Keep the supported set text-based and UTF-8 for the current product gate.
- Preserve the one-file, immediate-preview journey.
- Do not imply that CI configuration, unit-test source, or an Xcode Cloud manifest proves current behavior.
- Defer persistence, recent files, cloud sync, syntax tooling, and additional formats until repeated use exposes a clear need.
- Do not claim untrusted HTML/SVG is safe without a dedicated security review and runtime evidence.

## Open product questions

1. Is the supported input explicitly limited to artifacts the user created or requested from a trusted AI tool?
2. Should the Share Extension really advertise web URLs, and if so, should it preview the URL text or retrieve remote content?
3. Is source editing part of the promise or only a debugging convenience?
4. Which real-device failure would block a first useful release: incorrect rendering, share-sheet incompatibility, active-content risk, or all three?

## Source hierarchy

1. [Live app experience](file:///Users/10x/dev/apps/chat-file-viewer/ChatFileViewer/Features/ContentView.swift) and [Share Extension source](file:///Users/10x/dev/apps/chat-file-viewer/ChatFileViewerShare/ShareViewController.swift) win for implementation truth.
2. [README](file:///Users/10x/dev/apps/chat-file-viewer/README.md) owns the current checked-in product description.
3. [Project configuration](file:///Users/10x/dev/apps/chat-file-viewer/project.yml) owns target, version, bundle, and deployment settings.
4. [Focused tests](file:///Users/10x/dev/apps/chat-file-viewer/ChatFileViewerTests/MarkupDocumentTests.swift) describe intended detector behavior but do not replace a current test result.

If these sources conflict, live source wins for what exists, a current manual device observation wins for behavior, and an explicit new Alex decision wins for direction.

## Decision handoff and maintenance rule

Refresh this brief after a material scope or trust-boundary decision, a meaningful real-device artifact pass, or an accepted build. Do not turn it into a commit diary.

At the end of a Voice-mode product discussion, return:

- **Decision:** The direction Alex chose.
- **Why:** The mobile artifact problem it solves.
- **What changes:** The affected importer, detector, renderer, share flow, or product language.
- **What stays locked:** Local rendering, narrow scope, and any settled trust boundary not being reopened.
- **Evidence needed:** The exact file/share journey Alex should observe next.
- **Implementation requested:** None, documentation only, or a narrow code change.
