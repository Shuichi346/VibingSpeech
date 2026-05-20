import XCTest

final class VibingSpeechUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows["VibingSpeech"].waitForExistence(timeout: 5))
    }
}

