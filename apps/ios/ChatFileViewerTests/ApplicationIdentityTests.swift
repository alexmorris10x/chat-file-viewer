import Foundation
import XCTest

final class ApplicationIdentityTests: XCTestCase {
    func testHostedAppAndShareExtensionHaveMatchingIdentities() throws {
        #if DEBUG
        let appIdentifier = "com.10x.chatfileviewer.dev"
        let displaySuffix = " Dev"
        #else
        let appIdentifier = "com.10x.chatfileviewer"
        let displaySuffix = ""
        #endif

        XCTAssertEqual(Bundle.main.bundleIdentifier, appIdentifier)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "Chat File Viewer" + displaySuffix
        )

        let pluginsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let extensionURL = pluginsURL.appendingPathComponent("ChatFileViewerShare.appex")
        let extensionBundle = try XCTUnwrap(Bundle(url: extensionURL))
        XCTAssertEqual(extensionBundle.bundleIdentifier, appIdentifier + ".share")
        XCTAssertEqual(
            extensionBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "Open in Chat File Viewer" + displaySuffix
        )
    }
}
