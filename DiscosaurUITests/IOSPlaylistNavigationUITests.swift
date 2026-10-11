#if os(iOS)
import XCTest

final class IOSPlaylistNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreatingTheFirstPlaylistOpensItsEmptyDetail() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)

        XCTAssertTrue(app.navigationBars["New playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add music to this playlist"].exists)
        XCTAssertTrue(app.buttons["addMusicButton"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["miniPlayerView"].exists)

        showPlaylistList(in: app)
        XCTAssertTrue(app.staticTexts["New playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 tracks"].exists)
        playlistList(in: app).staticTexts["New playlist"].tap()
        XCTAssertTrue(app.navigationBars["New playlist"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRenamingAndCancellingDeletionKeepThePlaylist() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        renamePlaylist(to: "Favorites", in: app)

        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
        app.buttons["playlistActionsButton"].tap()
        app.buttons["Delete Playlist"].tap()
        XCTAssertTrue(app.buttons["confirmDeletePlaylistButton"].firstMatch.waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // Native popovers omit Cancel and dismiss when tapping outside.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).tap()
        }
        XCTAssertFalse(app.buttons["confirmDeletePlaylistButton"].firstMatch.exists)

        XCTAssertTrue(app.navigationBars["Favorites"].exists)
        showPlaylistList(in: app)
        XCTAssertTrue(app.staticTexts["Favorites"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeletingTheLastPlaylistReturnsToTheEmptyLibrary() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)

        app.buttons["playlistActionsButton"].tap()
        app.buttons["Delete Playlist"].tap()
        let confirmation = app.buttons["confirmDeletePlaylistButton"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(app.staticTexts["Add your music"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["libraryActionsButton"].exists)
        XCTAssertFalse(app.staticTexts["Add music to this playlist"].exists)
    }

    @MainActor
    func testRelaunchOpensTheRememberedPlaylist() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        renamePlaylist(to: "First playlist", in: app)
        showPlaylistList(in: app)
        createPlaylist(in: app)
        renamePlaylist(to: "Second playlist", in: app)
        showPlaylistList(in: app)
        playlistList(in: app).staticTexts["First playlist"].tap()
        XCTAssertTrue(app.navigationBars["First playlist"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.terminate()
        app.launch()

        XCTAssertTrue(app.navigationBars["First playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add music to this playlist"].exists)
        showPlaylistList(in: app)
        XCTAssertTrue(app.staticTexts["First playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Second playlist"].exists)
    }

    @MainActor
    func testCancellingTheFilePickerLeavesTheLibraryEmpty() {
        let app = makeTestApplication()
        app.launch()
        let addMusic = app.buttons["addMusicButton"]
        XCTAssertTrue(addMusic.waitForExistence(timeout: 5))
        addMusic.tap()
        app.buttons["Choose Files"].tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        XCTAssertTrue(app.staticTexts["Add your music"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["New playlist"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    private func createPlaylist(in app: XCUIApplication) {
        let actions = app.buttons["libraryActionsButton"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["createPlaylistButton"].tap()
        XCTAssertTrue(app.buttons["playlistActionsButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func renamePlaylist(to name: String, in app: XCUIApplication) {
        app.buttons["playlistActionsButton"].tap()
        app.buttons["Rename Playlist"].tap()
        let field = app.alerts["Rename playlist"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + name)
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    @MainActor
    private func playlistList(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["iosPlaylistList"].firstMatch
    }

    @MainActor
    private func showPlaylistList(in app: XCUIApplication) {
        // iPad already shows the sidebar; iPhone needs to pop the compact detail.
        let libraryActions = app.buttons["libraryActionsButton"]
        if !libraryActions.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(libraryActions.waitForExistence(timeout: 5))
    }
}
#endif
