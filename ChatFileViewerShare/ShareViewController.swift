import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareRenderModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground

        let host = UIHostingController(rootView: ShareRenderContainer(
            model: model,
            onDone: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        model.load(from: extensionContext)
    }
}

struct ShareRenderContainer: View {
    @ObservedObject var model: ShareRenderModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView("Could not render file", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    MarkupRenderView(document: model.document)
                }
            }
            .navigationTitle("Chat File Viewer")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

@MainActor
final class ShareRenderModel: ObservableObject {
    @Published var document = MarkupDocument.detect(from: MarkupSamples.markdownExample)
    @Published var isLoading = true
    @Published var errorMessage: String?

    func load(from extensionContext: NSExtensionContext?) {
        Task {
            do {
                let text = try await SharedTextLoader.loadText(from: extensionContext)
                document = MarkupDocument.detect(from: text)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

enum SharedTextLoader {
    static func loadText(from extensionContext: NSExtensionContext?) async throws -> String {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments,
              let provider = providers.first
        else {
            throw SharedTextError.noInput
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await loadFileText(from: provider)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await loadPlainText(from: provider)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            return try await loadPlainText(from: provider)
        }

        throw SharedTextError.unsupportedInput
    }

    private static func loadPlainText(from provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: SharedTextError.unsupportedInput)
                }
            }
        }
    }

    private static func loadFileText(from provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard let url else {
                    continuation.resume(throwing: SharedTextError.unsupportedInput)
                    return
                }

                do {
                    continuation.resume(returning: try String(contentsOf: url, encoding: .utf8))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum SharedTextError: LocalizedError {
    case noInput
    case unsupportedInput

    var errorDescription: String? {
        switch self {
        case .noInput:
            "No shared file or text was provided."
        case .unsupportedInput:
            "Share a .mmd, .svg, .md, .html, or .txt file."
        }
    }
}
