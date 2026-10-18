import XCTest
@testable import ChatFileViewer

final class GoogleOAuthTests: XCTestCase {
    private let configuration = GoogleOAuthConfiguration(
        clientID: "123-abc.apps.googleusercontent.com",
        hostedDomain: "example.com"
    )

    func testRedirectUsesReversedClientID() {
        XCTAssertEqual(configuration.redirectScheme, "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(configuration.redirectURI, "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    func testPKCEChallengeIsSHA256Base64URL() {
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mJ92K9pqk-cIl0Ip1Su2rcmvFaxuZs"),
            "2WCYk8UpUk2nAs5U3oXFdPYVMRv1OARzPgWJt90y1SY"
        )
        let verifier = PKCE.makeVerifier()
        XCTAssertEqual(verifier.count, 43)
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizationURLCarriesPKCEScopesAndDomain() throws {
        let url = configuration.authorizationURL(state: "s1", codeChallenge: "c1")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["code_challenge"], "c1")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["state"], "s1")
        XCTAssertEqual(values["hd"], "example.com")
        XCTAssertEqual(values["redirect_uri"], configuration.redirectURI)
        XCTAssertTrue(values["scope"]?.contains("https://www.googleapis.com/auth/drive.readonly") ?? false)
    }

    func testFormBodyEncodesReservedCharacters() {
        let body = String(decoding: GoogleOAuthConfiguration.formBody(["a": "x y+z/=", "b": "1"]), as: UTF8.self)
        XCTAssertEqual(body, "a=x%20y%2Bz%2F%3D&b=1")
    }

    func testIDTokenEmail() {
        let payload = Data(#"{"email":"alex@example.com"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = GoogleTokenResponse(accessToken: "a", expiresIn: 3600, refreshToken: nil, idToken: "x.\(payload).y")
        XCTAssertEqual(token.email, "alex@example.com")
    }
}

final class DriveLinkTests: XCTestCase {
    func testBaseURLRoundTripsNamesWithSpacesAndSymbols() throws {
        let base = DriveLink.baseURL(rootID: "root", folderNames: ["Plans", "Daily notes #2", "10 October"])
        XCTAssertTrue(base.absoluteString.hasSuffix("/"))
        let link = try XCTUnwrap(DriveLink(url: base))
        XCTAssertEqual(link.rootID, "root")
        XCTAssertEqual(link.names, ["Plans", "Daily notes #2", "10 October"])
    }

    func testRelativeLinksResolveAgainstTheFolder() throws {
        let base = DriveLink.baseURL(rootID: "abc_ID-1", folderNames: ["Plans", "Daily"])
        let sibling = try XCTUnwrap(URL(string: "../Client%20pipeline.md", relativeTo: base))
        XCTAssertEqual(DriveLink(url: sibling), DriveLink(url: DriveLink.baseURL(rootID: "abc_ID-1", folderNames: ["Plans", "Client pipeline.md"])))
        let image = try XCTUnwrap(URL(string: "assets/chart.png", relativeTo: base))
        XCTAssertEqual(DriveLink(url: image)?.names, ["Plans", "Daily", "assets", "chart.png"])
    }

    func testRootIDKeepsItsCase() throws {
        let base = DriveLink.baseURL(rootID: "0AbCdEf", folderNames: [])
        XCTAssertEqual(DriveLink(url: base)?.rootID, "0AbCdEf")
    }

    func testQueryEscaping() {
        XCTAssertEqual(DriveClient.escape("Alex's \\ notes"), "Alex\\'s \\\\ notes")
    }

    func testSafeCacheNames() {
        XCTAssertEqual(DriveStore.safeName("a/b:c"), "a_b_c")
        XCTAssertEqual(DriveStore.safeName(".."), "_")
    }
}

final class DriveItemTests: XCTestCase {
    func testDecodesAPISizeStringsAndDates() throws {
        let json = #"""
        {"files":[{"id":"1","name":"Report.md","mimeType":"text/markdown","size":"2048",
          "modifiedTime":"2026-10-18T05:10:05.123Z","md5Checksum":"abc"}],"nextPageToken":null}
        """#
        let list = try JSONDecoder.drive.decode(DriveFileList.self, from: Data(json.utf8))
        let item = try XCTUnwrap(list.files.first)
        XCTAssertEqual(item.size, 2048)
        XCTAssertNotNil(item.modifiedTime)
        XCTAssertEqual(item.contentVersion, "abc")
        XCTAssertTrue(item.opensAsText)

        // The local listing cache round-trips through the default encoder.
        let cached = try JSONDecoder.drive.decode([DriveItem].self, from: JSONEncoder().encode([item]))
        XCTAssertEqual(cached, [item])
    }

    func testGoogleDocsExportAsHTMLAndShortcutsResolve() {
        let doc = DriveItem(id: "d", name: "Brief", mimeType: "application/vnd.google-apps.document")
        XCTAssertEqual(doc.localFileName, "Brief.html")
        XCTAssertTrue(doc.opensAsText)

        let shortcut = DriveItem(
            id: "s",
            name: "Plans",
            mimeType: DriveItem.shortcutMimeType,
            shortcutDetails: .init(targetId: "f", targetMimeType: DriveItem.folderMimeType)
        )
        XCTAssertTrue(shortcut.isFolder)
        XCTAssertEqual(shortcut.resolved.id, "f")
    }

    func testBinaryFilesUseQuickLook() {
        XCTAssertFalse(DriveItem(id: "p", name: "Statement.PDF", mimeType: "application/pdf").opensAsText)
        XCTAssertFalse(DriveItem(id: "i", name: "chart.jpg", mimeType: "image/jpeg").opensAsText)
        XCTAssertTrue(DriveItem(id: "c", name: "main.swift", mimeType: "text/x-swift").opensAsText)
    }
}
