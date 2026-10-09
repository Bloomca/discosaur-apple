//
//  DiscosaurUITests.swift
//  DiscosaurUITests
//
//  Created by Seva on 10/9/26.
//

import XCTest

final class DiscosaurUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInitialScreen() throws {
        let app = XCUIApplication()
        app.launch()

        #if os(macOS)
        XCTAssertTrue(app.buttons["selectFilesButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No tracks yet"].exists)
        #else
        XCTAssertTrue(app.staticTexts["Hello, world!"].waitForExistence(timeout: 5))
        #endif
    }
}
