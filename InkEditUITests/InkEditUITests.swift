//
//  InkEditUITests.swift
//  InkEditUITests
//
//  Created by Snowitty on 2026/8/25.
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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
    func testEditsBookDetailsAndCoverWithSaveAndCancel() throws {
        try verifyBookDetails(useFileImporter: false)
    }

    @MainActor
    func testSelectsBookCoverThroughFileImporter() throws {
        try verifyBookDetails(useFileImporter: true)
    }

    @MainActor
    private func verifyBookDetails(useFileImporter: Bool) throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("cover-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: source) }
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 12, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 18))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-export", "-ui-testing-details-panel",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        ]
        if !useFileImporter {
            app.launchArguments += ["-ui-testing-cover-data", try Data(contentsOf: source).base64EncodedString()]
        }
        app.launch()
        defer { app.terminate() }
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["文件"].click()
            app.menuItems["新建窗口"].click()
        }
        let open = app.buttons["details-test-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        let author = app.textFields["details-author"]
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        author.click()
        author.typeKey("a", modifierFlags: .command)
        paste("新笔名 · 雪", into: author)
        if useFileImporter {
            app.buttons["choose-book-cover"].click()
            app.typeKey("g", modifierFlags: [.command, .shift])
            let path = app.textFields["PathTextField"]
            XCTAssertTrue(path.waitForExistence(timeout: 5))
            path.typeKey("a", modifierFlags: .command)
            paste(source.path, into: path)
            path.typeKey(.return, modifierFlags: [])
            let navigated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: path)
            XCTAssertEqual(XCTWaiter.wait(for: [navigated], timeout: 5), .completed)
            let choose = app.buttons["OKButton"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            choose.click()
        }
        let remove = app.buttons["remove-book-cover"]
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "作品信息与封面预览"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["save-book-details"].click()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: author)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)

        open.click()
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertEqual(author.value as? String, "新笔名 · 雪")
        XCTAssertTrue(remove.isEnabled)
        remove.click()
        app.buttons["取消"].click()
        open.click()
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertTrue(remove.isEnabled)
        remove.click()
        app.buttons["save-book-details"].click()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: author)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        open.click()
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertFalse(remove.isEnabled)
    }

    @MainActor
    private func paste(_ text: String, into element: XCUIElement) {
        // Preserve the user's clipboard and avoid changing their active input method.
        let pasteboard = NSPasteboard.general
        let original = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(original)
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        element.typeKey("v", modifierFlags: .command)
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
