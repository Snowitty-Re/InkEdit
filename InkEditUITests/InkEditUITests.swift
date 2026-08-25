//
//  InkEditUITests.swift
//  InkEditUITests
//
//  Created by Snowitty on 2026/8/25.
//

import XCTest

final class InkEditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreatesBookSheetWithChineseFields() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let createButton = app.buttons["create-book-button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.click()

        XCTAssertTrue(app.textFields["book-title-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["book-author-field"].exists)
        XCTAssertFalse(app.buttons["confirm-create-book-button"].isEnabled)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
        }
    }
}
