import XCTest

final class ChatFileViewerUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Chat File Viewer"].waitForExistence(timeout: 5))
    }
}
