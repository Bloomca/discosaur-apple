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
        let toolbar = app.toolbars.firstMatch
        let openFilesButton = toolbar.buttons["selectFilesButton"]
        XCTAssertTrue(openFilesButton.waitForExistence(timeout: 5))
        XCTAssertEqual(openFilesButton.label, "Open files/folder")
        XCTAssertGreaterThanOrEqual(openFilesButton.frame.width, 32)
        XCTAssertGreaterThanOrEqual(openFilesButton.frame.height, 32)
        XCTAssertGreaterThan(openFilesButton.frame.midX, toolbar.frame.midX)
        XCTAssertLessThanOrEqual(toolbar.frame.maxX - openFilesButton.frame.maxX, 32)
        XCTAssertTrue(app.staticTexts["No tracks yet"].exists)
        #else
        XCTAssertTrue(app.staticTexts["Hello, world!"].waitForExistence(timeout: 5))
        #endif
    }
}
