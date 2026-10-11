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
        let app = makeTestApplication()
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
        XCTAssertTrue(app.descendants(matching: .any)["playlistViewControls"].exists)
        XCTAssertTrue(app.buttons["playlistListView"].exists)
        XCTAssertTrue(app.buttons["playlistAlbumsView"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["trackList"].exists)
        #else
        XCTAssertTrue(app.staticTexts["Hello, world!"].waitForExistence(timeout: 5))
        #endif
    }

    #if os(macOS)
    @MainActor
    func testPlaylistViewButtonsSwitchViews() throws {
        let app = makeTestApplication()
        app.launch()
        let albumsButton = app.buttons["playlistAlbumsView"]
        XCTAssertTrue(albumsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No tracks yet"].exists)

        albumsButton.click()
        XCTAssertTrue(app.staticTexts["No albums yet"].waitForExistence(timeout: 5))

        app.buttons["playlistListView"].click()
        XCTAssertTrue(app.staticTexts["No tracks yet"].waitForExistence(timeout: 5))
    }
    #endif
}
