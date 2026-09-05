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
    func testExportsEveryFormatFromWorkspaceSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-export", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        ]
        app.launch()
        defer { app.terminate() }
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["文件"].click()
            app.menuItems["新建窗口"].click()
        }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        for label in ["EPUB 电子书", "Word 文稿", "PDF 版式文档", "HTML 网页"] {
            app.typeKey("e", modifierFlags: [.command, .shift])
            let format = app.radioButtons[label]
            XCTAssertTrue(format.waitForExistence(timeout: 5))
            format.click()
            let chooseDestination = app.buttons["choose-export-destination"]
            chooseDestination.click()
            let save = app.buttons["OKButton"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            save.click()
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: chooseDestination)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 20), .completed, app.debugDescription)
        }
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
