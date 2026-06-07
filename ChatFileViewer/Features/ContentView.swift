import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var input = MarkupSamples.markdownExample
    @State private var document = MarkupDocument.detect(from: MarkupSamples.markdownExample)
    @State private var isImporterPresented = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MarkupRenderView(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 180)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onChange(of: input) { _, newValue in
                        document = MarkupDocument.detect(from: newValue)
                    }
            }
            .navigationTitle("Chat File Viewer")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open", systemImage: "folder")
                    }

                    ShareLink(item: document.source) {
                        Label("Share Source", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.plainText, .text, .html, .markdown, .sourceCode, .svg],
                allowsMultipleSelection: false
            ) { result in
                loadFile(result)
            }
            .alert("Could not open file", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            input = try String(contentsOf: url, encoding: .utf8)
            document = MarkupDocument.detect(from: input)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension UTType {
    static let markdown = UTType(filenameExtension: "md") ?? .plainText
    static let sourceCode = UTType(filenameExtension: "mmd") ?? .plainText
    static let svg = UTType(filenameExtension: "svg") ?? .plainText
}

#Preview {
    ContentView()
}
