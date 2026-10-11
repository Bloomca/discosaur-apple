#if os(macOS)
import XCTest

final class PlaylistRenamingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReturnCommitsTheNameAndUpdatesTheWindowTitle() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let editor = beginRename("New playlist", in: app)

        replaceName(with: "Favourites", in: editor)
        editor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(sidebar(in: app).staticTexts["Favourites"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.title, "Favourites")
        XCTAssertFalse(editor.exists)
    }

    @MainActor
    func testEscapeCancelsWithoutChangingTheName() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let editor = beginRename("New playlist", in: app)

        replaceName(with: "Cancelled name", in: editor)
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        XCTAssertTrue(sidebar(in: app).staticTexts["New playlist"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.title, "New playlist")
        XCTAssertFalse(sidebar(in: app).staticTexts["Cancelled name"].exists)
        XCTAssertFalse(editor.exists)
    }

    @MainActor
    func testCreatingAnotherPlaylistCommitsToThePreviouslyEditedPlaylist() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let editor = beginRename("New playlist", in: app)
        replaceName(with: "First playlist", in: editor)

        createPlaylist(in: app)

        XCTAssertTrue(sidebar(in: app).staticTexts["First playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar(in: app).staticTexts["New playlist"].exists)
        XCTAssertEqual(app.windows.firstMatch.title, "New playlist")
        XCTAssertFalse(editor.exists)
    }

    @MainActor
    func testEmptyNameLeavesTheExistingNameUnchanged() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let editor = beginRename("New playlist", in: app)
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        editor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(sidebar(in: app).staticTexts["New playlist"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.title, "New playlist")
        XCTAssertFalse(editor.exists)
    }

    @MainActor
    func testSelectingAnotherPlaylistCommitsToTheEditedItem() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let firstEditor = beginRename("New playlist", in: app)
        replaceName(with: "First playlist", in: firstEditor)
        firstEditor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(sidebar(in: app).staticTexts["First playlist"].waitForExistence(timeout: 5))
        createPlaylist(in: app)
        let secondEditor = beginRename("New playlist", in: app)
        replaceName(with: "Second playlist", in: secondEditor)

        sidebar(in: app).staticTexts["First playlist"].click()

        XCTAssertTrue(sidebar(in: app).staticTexts["Second playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar(in: app).staticTexts["First playlist"].exists)
        XCTAssertEqual(app.windows.firstMatch.title, "First playlist")
        XCTAssertFalse(secondEditor.exists)
    }

    @MainActor
    func testQuittingImmediatelyAfterRenameSavesAndRestoresThePlaylist() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let editor = beginRename("New playlist", in: app)
        replaceName(with: "Saved playlist", in: editor)
        editor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        app.launch()

        XCTAssertTrue(sidebar(in: app).staticTexts["Saved playlist"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.title, "Saved playlist")
    }

    @MainActor
    func testBrowsingSelectionSurvivesRelaunchInsteadOfSelectingTheFirstPlaylist() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(in: app)
        let firstEditor = beginRename("New playlist", in: app)
        replaceName(with: "First playlist", in: firstEditor)
        firstEditor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        createPlaylist(in: app)
        let secondEditor = beginRename("New playlist", in: app)
        replaceName(with: "Second playlist", in: secondEditor)
        secondEditor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        app.launch()

        XCTAssertTrue(sidebar(in: app).staticTexts["Second playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar(in: app).staticTexts["First playlist"].exists)
        XCTAssertEqual(app.windows.firstMatch.title, "Second playlist")
    }

    @MainActor
    private func sidebar(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["playlistSidebar"].firstMatch
    }

    @MainActor
    private func createPlaylist(in app: XCUIApplication) {
        let button = app.buttons["createPlaylistButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }

    @MainActor
    private func beginRename(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let row = sidebar(in: app).staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        let menuItem = app.menuItems["Rename"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5))
        menuItem.click()
        let editor = app.textFields["playlistNameEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        return editor
    }

    @MainActor
    private func replaceName(with name: String, in editor: XCUIElement) {
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(name)
    }
}
#endif
