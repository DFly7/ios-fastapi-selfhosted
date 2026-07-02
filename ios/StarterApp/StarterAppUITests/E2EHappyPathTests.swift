//
//  E2EHappyPathTests.swift
//  StarterAppUITests
//

import XCTest

final class E2EHappyPathTests: XCTestCase {

    private let e2eEmail = "e2e@example.com"
    private let e2ePassword = "E2ETest123!"
    private let noteTitle = "E2E smoke note"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInSecureTestAndCreateNote() throws {
        let app = XCUIApplication()
        app.launch()

        // Signed out
        XCTAssertTrue(app.staticTexts["Sign in to continue"].waitForExistence(timeout: 10))

        app.buttons["auth.openSignIn"].tap()

        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(e2eEmail)

        let passwordField = app.secureTextFields["auth.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(e2ePassword)

        app.buttons["auth.submit"].tap()

        // Signed in — main screen
        XCTAssertTrue(app.navigationBars["Starter"].waitForExistence(timeout: 15))

        // Secure test
        let secureTestButton = app.buttons["home.secureTest"]
        XCTAssertTrue(secureTestButton.waitForExistence(timeout: 5))
        secureTestButton.tap()

        let result = app.staticTexts["home.secureTestResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        XCTAssertFalse(result.label.isEmpty)

        // Create note
        app.buttons["notes.add"].tap()

        let titleField = app.textFields["notes.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(noteTitle)

        app.buttons["notes.save"].tap()

        // Note appears in list
        let noteRow = app.staticTexts["notes.row.\(noteTitle)"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 15))
    }
}
