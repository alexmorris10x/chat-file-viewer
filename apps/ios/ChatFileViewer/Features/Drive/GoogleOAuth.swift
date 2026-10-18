import CryptoKit
import Foundation

/// Google sign-in for an iOS OAuth client: authorization code flow with PKCE and the
/// client's reversed-ID redirect scheme. iOS clients have no client secret.
struct GoogleOAuthConfiguration: Equatable {
    static let scopes = [
        "openid",
        "email",
        "https://www.googleapis.com/auth/drive.readonly"
    ]

    let clientID: String
    /// Optional Workspace domain hint so Google offers the right account first.
    let hostedDomain: String?

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String {
        "\(redirectScheme):/oauth2redirect"
    }

    static func fromBundle(_ bundle: Bundle = .main) -> GoogleOAuthConfiguration? {
        guard
            let clientID = bundle.object(forInfoDictionaryKey: "GoogleIOSClientID") as? String,
            clientID.hasSuffix(".apps.googleusercontent.com")
        else {
            return nil
        }
        let domain = (bundle.object(forInfoDictionaryKey: "GoogleHostedDomain") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return GoogleOAuthConfiguration(
            clientID: clientID,
            hostedDomain: domain?.isEmpty == false ? domain : nil
        )
    }

    func authorizationURL(state: String, codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if let hostedDomain {
            items.append(URLQueryItem(name: "hd", value: hostedDomain))
        }
        components.queryItems = items
        return components.url!
    }

    func codeExchangeRequest(code: String, verifier: String) -> URLRequest {
        tokenRequest([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
    }

    func refreshRequest(refreshToken: String) -> URLRequest {
        tokenRequest([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
    }

    func revokeRequest(token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["token": token])
        return request
    }

    private func tokenRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)
        return request
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

enum PKCE {
    /// A 43-character URL-safe verifier from 32 random bytes.
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }

    /// The signed-in email from the ID token. Only used for display, so the token
    /// (which came straight from Google over TLS) is decoded without verification.
    var email: String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["email"] as? String
    }
}

struct GoogleOAuthError: LocalizedError, Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    /// The saved sign-in no longer works (revoked, expired or the account changed).
    var requiresSignIn: Bool {
        error == "invalid_grant" || error == "unauthorized_client"
    }
}
