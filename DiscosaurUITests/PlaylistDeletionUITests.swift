#if os(macOS)
import XCTest

final class PlaylistDeletionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCancellingDeletionKeepsThePlaylist() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(named: "Keep me", in: app)

        beginDelete("Keep me", in: app)
        app.buttons["Cancel"].click()

        XCTAssertTrue(sidebar(in: app).staticTexts["Keep me"].exists)
        XCTAssertEqual(app.windows.firstMatch.title, "Keep me")
        XCTAssertFalse(app.staticTexts[confirmationMessage].exists)
    }

    @MainActor
    func testDeletingAPlaylistKeepsTheOtherOneAndPersistsAcrossRelaunch() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(named: "Delete me", in: app)
        createPlaylist(named: "Keep me", in: app)

        beginDelete("Delete me", in: app)
        app.buttons["Delete"].click()

        XCTAssertFalse(sidebar(in: app).staticTexts["Delete me"].exists)
        XCTAssertTrue(sidebar(in: app).staticTexts["Keep me"].exists)
        XCTAssertEqual(app.windows.firstMatch.title, "Keep me")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(sidebar(in: app).staticTexts["Keep me"].waitForExistence(timeout: 5))
        XCTAssertFalse(sidebar(in: app).staticTexts["Delete me"].exists)
    }

    @MainActor
    func testDeletingTheLastPlaylistShowsTheEmptyLibrary() {
        let app = makeTestApplication()
        app.launch()
        createPlaylist(named: "Delete me", in: app)

        beginDelete("Delete me", in: app)
        app.buttons["Delete"].click()

        XCTAssertFalse(sidebar(in: app).staticTexts["Delete me"].exists)
        XCTAssertTrue(app.staticTexts["No tracks yet"].exists)
        XCTAssertEqual(app.windows.firstMatch.title, "Discosaur")
    }

    private var confirmationMessage: String {
        "Are you sure you want to delete this playlist? It has 0 tracks?"
    }

    @MainActor
    private func sidebar(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["playlistSidebar"].firstMatch
    }

    @MainActor
    private func createPlaylist(named name: String, in app: XCUIApplication) {
        let button = app.buttons["createPlaylistButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        let row = sidebar(in: app).staticTexts["New playlist"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        let rename = app.menuItems["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.click()
        let editor = app.textFields["playlistNameEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(name)
        editor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(sidebar(in: app).staticTexts[name].waitForExistence(timeout: 5))
    }

    @MainActor
    private func beginDelete(_ name: String, in app: XCUIApplication) {
        let row = sidebar(in: app).staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        let delete = app.menuItems["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        XCTAssertTrue(app.staticTexts[confirmationMessage].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        // Opening the confirmation alone must not remove the target.
        XCTAssertTrue(sidebar(in: app).staticTexts[name].exists)
    }
}
#endif
