import Foundation
import XCTest

@MainActor
func makeTestApplication() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["DISCOSAUR_TEST_LIBRARY_ID"] = UUID().uuidString
    return app
}
