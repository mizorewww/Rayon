import XCTest

/// Drives the installed iOS app (bundle `wiki.qaq.ray0n`). Each test attaches
/// screenshots to the result bundle.
@MainActor
final class MRayonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "wiki.qaq.ray0n")
        // Skip the first-launch agreement through the argument domain; nothing
        // is written to the app's stored defaults.
        app.launchArguments += ["-licenseAgreed", "YES"]
        app.launch()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings() {
        let more = app.tabBars.buttons["More"]
        if more.waitForExistence(timeout: 5) {
            more.tap()
            app.buttons["Settings"].firstMatch.tap()
        } else {
            // iPad: Settings is a row in the sidebar, not a button.
            let row = app.cells.containing(.staticText, identifier: "Settings").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "The sidebar lists Settings")
            row.tap()
        }
    }

    func testLaunchShowsHome() {
        XCTAssertTrue(app.staticTexts["Home"].firstMatch.waitForExistence(timeout: 10))
        screenshot("Home")
    }

    func testSettingsUseTheSharedLayout() {
        openSettings()
        let expected = ["General", "Connection", "Text", "Colors", "Cursor", "Window",
                        "Mouse & Clipboard", "Keyboard", "Advanced", "About"]
        XCTAssertTrue(app.buttons["General"].firstMatch.waitForExistence(timeout: 5))
        for title in expected {
            let row = app.buttons[title].firstMatch
            if !row.exists { app.swipeUp() }
            XCTAssertTrue(row.exists, "Settings lists \(title)")
        }
        screenshot("Settings")
    }

    func testTextSettingsOfferInstalledFonts() {
        openSettings()
        app.buttons["Text"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Font"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Size"].firstMatch.exists)
        screenshot("Text")

        app.buttons["Built-in (JetBrains Mono)"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Menlo"].firstMatch.waitForExistence(timeout: 5), "The picker lists installed fonts")
        screenshot("Font picker")
    }

    func testKeyboardShortcutsReadAsKeyCaps() {
        openSettings()
        let keyboard = app.buttons["Keyboard"].firstMatch
        if !keyboard.exists { app.swipeUp() }
        keyboard.tap()
        XCTAssertTrue(app.staticTexts["Copy"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["⌘C"].firstMatch.exists)
        screenshot("Keyboard")
    }

    /// Opens a Quick Connect session to a closed local port: the Ghostty terminal
    /// appears, reports the failed connection, and offers Reconnect and Close.
    func testQuickConnectOpensTheGhosttyTerminal() {
        let field = app.textFields["ssh user@host -p 22"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("ssh test@127.0.0.1 -p 1\n")
        XCTAssertTrue(app.buttons["Close Session"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Reconnect"].firstMatch.waitForExistence(timeout: 15), "The closed session offers Reconnect")
        screenshot("Terminal")
    }
}
