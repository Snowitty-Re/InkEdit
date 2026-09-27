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
        try verifyEveryFormatExport(standalone: false)
    }

    @MainActor
    func testExportsEveryFormatFromStandaloneSheet() throws {
        try verifyEveryFormatExport(standalone: true)
    }

    @MainActor
    private func verifyEveryFormatExport(standalone: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-export", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        ]
        if standalone { app.launchArguments.append("-ui-testing-export-panel") }
        app.launch()
        defer { app.terminate() }
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["文件"].click()
            app.menuItems["新建窗口"].click()
        }
        let ready = standalone ? app.buttons["export-test-open"] : app.textViews.firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        for label in ["EPUB 电子书", "Word 文稿", "PDF 版式文档", "HTML 网页"] {
            app.typeKey("e", modifierFlags: [.command, .shift])
            let format = app.radioButtons[label]
            XCTAssertTrue(format.waitForExistence(timeout: 5))
            format.click()
            let chooseDestination = app.buttons["choose-export-destination"]
            chooseDestination.click()
            let save = app.buttons["OKButton"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            let filename = app.textFields["saveAsNameTextField"]
            filename.click()
            filename.typeKey("a", modifierFlags: .command)
            filename.typeText("InkEdit-UITest-\(UUID().uuidString)")
            save.click()
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: chooseDestination)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 20), .completed, app.debugDescription)
        }
    }

    @MainActor
    func testPartialExportDefaultsToCurrentChapterAndAllowsExclusions() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-export", "-ui-testing-export-range",
            "-ui-testing-export-panel",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        ]
        app.launch()
        defer { app.terminate() }
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["文件"].click()
            app.menuItems["新建窗口"].click()
        }
        XCTAssertTrue(app.buttons["export-test-open"].waitForExistence(timeout: 5))
        app.typeKey("e", modifierFlags: [.command, .shift])
        let partial = app.radioButtons["部分章节"]
        XCTAssertTrue(partial.waitForExistence(timeout: 5))
        partial.click()
        let count = app.staticTexts["export-chapter-count"]
        XCTAssertEqual(count.value as? String, "已选择 2 / 3 章", count.debugDescription)
        app.checkBoxes["export-include-第一章"].click()
        XCTAssertEqual(count.value as? String, "已选择 1 / 3 章")
        app.checkBoxes["export-include-第二章"].click()
        XCTAssertFalse(app.buttons["choose-export-destination"].isEnabled)
        app.checkBoxes["export-include-第二章"].click()
        app.popUpButtons["export-end-chapter"].click()
        app.menuItems["3. 第三章"].click()
        app.popUpButtons["export-start-chapter"].click()
        app.menuItems["2. 第二章"].click()
        XCTAssertEqual(count.value as? String, "已选择 2 / 3 章")
        XCTAssertFalse(app.checkBoxes["export-include-第一章"].exists)
        XCTAssertTrue(app.checkBoxes["export-include-第三章"].exists)
        app.radioButtons["全部章节"].click()
        XCTAssertEqual(count.value as? String, "已选择 3 / 3 章")
        XCTAssertTrue(app.buttons["choose-export-destination"].isEnabled)
        app.radioButtons["部分章节"].click()
        XCTAssertEqual(count.value as? String, "已选择 2 / 3 章")
        app.radioButtons["HTML 网页"].click()
        let chooseDestination = app.buttons["choose-export-destination"]
        chooseDestination.click()
        let save = app.buttons["OKButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let filename = app.textFields["saveAsNameTextField"]
        filename.click()
        filename.typeKey("a", modifierFlags: .command)
        filename.typeText("InkEdit-UITest-\(UUID().uuidString)")
        save.click()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: chooseDestination)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 20), .completed, app.debugDescription)
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
