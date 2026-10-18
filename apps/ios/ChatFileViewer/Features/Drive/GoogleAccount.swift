import AuthenticationServices
import Foundation
import UIKit

/// The signed-in Google account: sign-in through the system browser sheet, the
/// refresh token in the Keychain, and short-lived access tokens on demand.
@MainActor
final class GoogleAccount: ObservableObject {
    enum State: Equatable {
        case signedOut
        case signedIn(email: String)
    }

    enum AccountError: LocalizedError {
        case notConfigured
        case notSignedIn
        case cancelled
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Google sign-in isn't set up in this build."
            case .notSignedIn:
                return "Sign in with Google to browse your Drive."
            case .cancelled:
                return "Sign-in was cancelled."
            case let .badResponse(message):
                return message
            }
        }
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var isSigningIn = false
    @Published var lastError: String?

    let configuration: GoogleOAuthConfiguration?
    private let keychain: KeychainStore
    private let session: URLSession
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private var refreshTask: Task<GoogleTokenResponse, Error>?
    private var authSession: ASWebAuthenticationSession?
    private let presenter = WebAuthenticationPresenter()

    private static let refreshTokenKey = "refresh-token"
    private static let emailKey = "email"

    init(
        configuration: GoogleOAuthConfiguration? = .fromBundle(),
        keychain: KeychainStore = KeychainStore(service: (Bundle.main.bundleIdentifier ?? "chatfileviewer") + ".google"),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.keychain = keychain
        self.session = session
        if keychain.string(for: Self.refreshTokenKey) != nil {
            state = .signedIn(email: keychain.string(for: Self.emailKey) ?? "Google account")
        }
    }

    var email: String? {
        if case let .signedIn(email) = state { return email }
        return nil
    }

    func signIn() async {
        guard let configuration else {
            lastError = AccountError.notConfigured.localizedDescription
            return
        }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }
        do {
            let verifier = PKCE.makeVerifier()
            let expectedState = PKCE.makeVerifier()
            let url = configuration.authorizationURL(
                state: expectedState,
                codeChallenge: PKCE.challenge(for: verifier)
            )
            let callback = try await authenticate(url: url, scheme: configuration.redirectScheme)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw AccountError.badResponse(error == "access_denied" ? "Google sign-in was declined." : error)
            }
            guard
                items.first(where: { $0.name == "state" })?.value == expectedState,
                let code = items.first(where: { $0.name == "code" })?.value
            else {
                throw AccountError.badResponse("Google returned an unexpected sign-in response.")
            }
            let tokens = try await send(configuration.codeExchangeRequest(code: code, verifier: verifier))
            guard let refreshToken = tokens.refreshToken else {
                throw AccountError.badResponse("Google didn't return a lasting sign-in. Try again.")
            }
            let email = tokens.email ?? "Google account"
            keychain.set(refreshToken, for: Self.refreshTokenKey)
            keychain.set(email, for: Self.emailKey)
            accessToken = tokens.accessToken
            accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60))
            state = .signedIn(email: email)
        } catch AccountError.cancelled {
            // Closing the sheet isn't an error worth showing.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        let refreshToken = keychain.string(for: Self.refreshTokenKey)
        keychain.remove(Self.refreshTokenKey)
        keychain.remove(Self.emailKey)
        accessToken = nil
        accessTokenExpiry = .distantPast
        refreshTask?.cancel()
        refreshTask = nil
        // The next account shouldn't see this one's files offline or its Home folder.
        DriveStore.clearCache()
        UserDefaults.standard.removeObject(forKey: DriveBrowserView.homeTrailKey)
        state = .signedOut
        if let configuration, let refreshToken {
            let request = configuration.revokeRequest(token: refreshToken)
            Task { _ = try? await session.data(for: request) }
        }
    }

    /// A valid access token, refreshed when it's about to expire (or when forced
    /// after the API rejected the current one). Concurrent callers share one refresh.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let accessToken, accessTokenExpiry > Date() {
            return accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        guard let configuration else { throw AccountError.notConfigured }
        guard let refreshToken = keychain.string(for: Self.refreshTokenKey) else {
            state = .signedOut
            throw AccountError.notSignedIn
        }
        let task = Task<GoogleTokenResponse, Error> {
            try await self.send(configuration.refreshRequest(refreshToken: refreshToken))
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let tokens = try await task.value
            accessToken = tokens.accessToken
            accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60))
            return tokens.accessToken
        } catch let error as GoogleOAuthError where error.requiresSignIn {
            signOut()
            lastError = "Your Google sign-in expired. Sign in again."
            throw AccountError.notSignedIn
        }
    }

    private func send(_ request: URLRequest) async throws -> GoogleTokenResponse {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let error = try? JSONDecoder().decode(GoogleOAuthError.self, from: data) {
                throw error
            }
            throw AccountError.badResponse("Google sign-in failed (HTTP \(status)).")
        }
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion: (URL?, Error?) -> Void = { [weak self] callback, error in
                Task { @MainActor in self?.authSession = nil }
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AccountError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AccountError.cancelled)
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(scheme),
                    completionHandler: completion
                )
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: scheme,
                    completionHandler: completion
                )
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                authSession = nil
                continuation.resume(throwing: AccountError.badResponse("Couldn't open Google sign-in."))
            }
        }
    }
}

private final class WebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}
