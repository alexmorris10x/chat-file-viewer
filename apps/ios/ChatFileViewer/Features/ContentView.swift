import SwiftUI

struct ContentView: View {
    @State private var document = MarkupDocument.detect(from: MarkupSamples.markdownExample)
    @State private var errorMessage: String?

    var body: some View {
        MarkupRenderView(document: document)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onOpenURL { url in
                loadFile(url)
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

    private func loadFile(_ url: URL) {
        do {
            try loadFileContents(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFileContents(_ url: URL) throws {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        document = MarkupDocument.detect(from: source)
    }
}

#Preview {
    ContentView()
}
