import XCTest

/// Captures screenshots of layouts that can't be reached from the command line, such as
/// landscape. Runs only on the disposable "Minidisc UX Verification" simulator, which already
/// has a server configured; screenshots are kept as test attachments.
final class LayoutCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Minidisc UX Verification" else {
            throw XCTSkip("Run only on the disposable simulator named Minidisc UX Verification.")
        }
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testLandscapeCapture() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        attach(app, "landscape-home")

        let library = app.tabBars.buttons.element(boundBy: 2)
        if library.exists { library.tap(); sleep(2); attach(app, "landscape-library") }

        let mini = app.staticTexts["player.mini.title"].firstMatch
        if mini.waitForExistence(timeout: 3) {
            mini.tap()
            sleep(3)
            attach(app, "landscape-player")
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
