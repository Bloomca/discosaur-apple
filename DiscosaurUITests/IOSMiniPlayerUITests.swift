#if os(iOS)
import XCTest

final class IOSMiniPlayerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTransportControlsFollowThePlayingQueue() {
        let app = launchPlaybackApplication()
        startPlayback(in: app)
        let previous = app.buttons["miniPlayerPrevious"]
        let next = app.buttons["miniPlayerNext"]
        let playPause = app.buttons["miniPlayerPlayPause"]

        XCTAssertFalse(previous.isEnabled)
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(app.sliders["playerSeekSlider"].isEnabled)
        XCTAssertEqual(app.staticTexts["miniPlayerDuration"].label, "Duration: 1:00")
        let bar = app.descendants(matching: .any)["miniPlayerView"].firstMatch
        XCTAssertFalse(bar.buttons["Stop"].exists)
        XCTAssertFalse(bar.buttons["Volume"].exists)

        playPause.tap()
        waitForLabel("Play", on: playPause)
        playPause.tap()
        waitForLabel("Pause", on: playPause)

        next.tap()
        waitForLabel("Test Track 2", on: app.staticTexts["miniPlayerTrackTitle"])
        XCTAssertTrue(previous.isEnabled)
        next.tap()
        waitForLabel("Test Track 3", on: app.staticTexts["miniPlayerTrackTitle"])
        XCTAssertFalse(next.isEnabled)

        previous.tap()
        waitForLabel("Test Track 2", on: app.staticTexts["miniPlayerTrackTitle"])
        previous.tap()
        waitForLabel("Test Track 1", on: app.staticTexts["miniPlayerTrackTitle"])
        XCTAssertFalse(previous.isEnabled)
    }

    @MainActor
    func testSeekingWhilePausedDoesNotResumePlayback() throws {
        let app = launchPlaybackApplication()
        startPlayback(in: app)
        let playPause = app.buttons["miniPlayerPlayPause"]
        playPause.tap()
        waitForLabel("Play", on: playPause)

        let slider = app.sliders["playerSeekSlider"]
        XCTAssertTrue(slider.isEnabled)
        slider.adjust(toNormalizedSliderPosition: 0.5)

        let elapsed = app.staticTexts["miniPlayerElapsedTime"].label
            .replacingOccurrences(of: "Elapsed time: ", with: "")
        let parts = elapsed.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        let seconds = try XCTUnwrap(parts.last)
        XCTAssertGreaterThanOrEqual(seconds, 25)
        XCTAssertLessThanOrEqual(seconds, 35)
        XCTAssertEqual(playPause.label, "Play")
        XCTAssertEqual(app.staticTexts["miniPlayerTrackTitle"].label, "Test Track 1")

        playPause.tap()
        waitForLabel("Pause", on: playPause)
    }

    @MainActor
    func testRestoredTrackCannotSeekUntilAudioIsLoaded() {
        let app = launchPlaybackApplication()
        startPlayback(in: app)
        app.buttons["miniPlayerPlayPause"].tap()
        waitForLabel("Play", on: app.buttons["miniPlayerPlayPause"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.terminate()
        app.launch()

        let playPause = app.buttons["miniPlayerPlayPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        XCTAssertEqual(playPause.label, "Play")
        XCTAssertFalse(app.sliders["playerSeekSlider"].isEnabled)
        playPause.tap()
        waitForLabel("Pause", on: playPause)
        XCTAssertTrue(app.sliders["playerSeekSlider"].isEnabled)
    }

    @MainActor
    private func launchPlaybackApplication() -> XCUIApplication {
        let app = makeTestApplication()
        app.launchEnvironment["DISCOSAUR_TEST_PLAYBACK_FIXTURE"] = "1"
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
    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
#endif
