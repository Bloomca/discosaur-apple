#if os(iOS)
import XCTest

final class IOSBackgroundPlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAudioContinuesWhenTheAppIsBackgrounded() async throws {
        let app = launchPlaybackApplication()
        startPlayback(in: app)
        let before = elapsedSeconds(in: app)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        // Allow real audio render time to advance with UI polling disabled.
        try await Task.sleep(for: .seconds(4))
        app.activate()

        waitForLabel("Pause", on: app.buttons["miniPlayerPlayPause"])
        XCTAssertGreaterThanOrEqual(elapsedSeconds(in: app), before + 3)
        XCTAssertEqual(app.staticTexts["miniPlayerTrackTitle"].label, "Test Track 1")
    }

    @MainActor
    func testTheQueueAdvancesToTheNextFileInTheBackground() async throws {
        let app = launchPlaybackApplication(trackDuration: 15)
        startPlayback(in: app)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        try await Task.sleep(for: .seconds(16))
        app.activate()

        waitForLabel("Test Track 2", on: app.staticTexts["miniPlayerTrackTitle"])
        waitForLabel("Pause", on: app.buttons["miniPlayerPlayPause"])
        XCTAssertTrue(app.buttons["miniPlayerPrevious"].isEnabled)
    }

    @MainActor
    private func launchPlaybackApplication(trackDuration: Int = 60) -> XCUIApplication {
        let app = makeTestApplication()
        app.launchEnvironment["DISCOSAUR_TEST_PLAYBACK_FIXTURE"] = "1"
        app.launchEnvironment["DISCOSAUR_TEST_TRACK_DURATION"] = String(trackDuration)
        app.launch()
        XCTAssertTrue(app.navigationBars["Playback Tests"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func startPlayback(in app: XCUIApplication) {
        let track = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "playback-", "Test Track 1"
        )).firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        track.tap()
        waitForLabel("Pause", on: app.buttons["miniPlayerPlayPause"])
    }

    @MainActor
    private func elapsedSeconds(in app: XCUIApplication) -> Int {
        let text = app.staticTexts["miniPlayerElapsedTime"].label.replacingOccurrences(of: "Elapsed time: ", with: "")
        let parts = text.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
#endif
