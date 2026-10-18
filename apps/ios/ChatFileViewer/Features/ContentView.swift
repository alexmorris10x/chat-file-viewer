import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var account = GoogleAccount()
    @State private var localFile: LocalFile?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch account.state {
            case .signedIn:
                DriveBrowserView(account: account, openLocalFile: { isImporting = true })
            case .signedOut:
                SignInView(account: account, openLocalFile: { isImporting = true })
            }
        }
        .onOpenURL { url in
            loadFile(url)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
            switch result {
            case let .success(url):
                loadFile(url)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $localFile) { file in
            NavigationStack {
                MarkupRenderView(document: file.document)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(file.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { localFile = nil }
                        }
                    }
            }
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
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            localFile = LocalFile(
                name: url.lastPathComponent,
                document: MarkupDocument.forFile(named: url.lastPathComponent, text: source)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LocalFile: Identifiable {
    let id = UUID()
    let name: String
    let document: MarkupDocument
}

struct SignInView: View {
    @ObservedObject var account: GoogleAccount
    let openLocalFile: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("Chat File Viewer")
                    .font(.largeTitle.bold())
                Text("Read your Google Drive files the way they're meant to look: Markdown, HTML pages, code, tables and diagrams.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            VStack(spacing: 12) {
                Button {
                    Task { await account.signIn() }
                } label: {
                    if account.isSigningIn {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in with Google")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(account.isSigningIn || account.configuration == nil)

                Button("Open a File on This Device", action: openLocalFile)
                    .controlSize(.large)
            }
            .frame(maxWidth: 360)
            if let message = account.lastError
                ?? (account.configuration == nil ? GoogleAccount.AccountError.notConfigured.localizedDescription : nil) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
