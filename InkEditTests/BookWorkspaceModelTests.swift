import Foundation
import Testing

@testable import InkEdit

@MainActor
struct BookWorkspaceModelTests {
    @Test func sustainedInteractionBlocksSaveUntilItEnds() async throws {
        try await withWorkspace { model, repository, project in
            let chapter = try #require(model.selectedChapter)
            let originalText = model.chapterText
            model.updateText("待保存")
            model.recordEditorActivity(isBusy: true, chapterID: chapter.id)
            try await Task.sleep(for: .milliseconds(450))
            #expect(model.saveState == .unsaved)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == originalText)

            model.recordEditorActivity(isBusy: false, chapterID: chapter.id)
            try await Task.sleep(for: .milliseconds(80))
            #expect(model.saveState == .unsaved)
            try await waitForAutosave(model)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "待保存")
        }
    }

    @Test func continuousEditsSaveOnlyAfterIdle() async throws {
        try await withWorkspace { model, repository, project in
            let chapter = try #require(model.selectedChapter)
            let originalText = model.chapterText
            for index in 1...5 {
                model.updateText("正文 \(index)")
                try await Task.sleep(for: .milliseconds(70))
                #expect(model.saveState == .unsaved)
                #expect(try repository.readChapter(chapter, in: project.rootURL) == originalText)
            }
            try await waitForAutosave(model)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "正文 5")
        }
    }

    @Test func cleanActivityDoesNotSaveAgain() async throws {
        try await withWorkspace { model, _, _ in
            let chapter = try #require(model.selectedChapter)
            let originalState = model.saveState
            model.recordEditorActivity(isBusy: true, chapterID: chapter.id)
            model.recordEditorActivity(isBusy: false, chapterID: chapter.id)
            try await Task.sleep(for: .milliseconds(450))
            #expect(model.saveState == originalState)

            model.updateText("保存一次")
            try await waitForAutosave(model)
            let savedState = model.saveState
            model.recordEditorActivity(isBusy: false, chapterID: chapter.id)
            try await Task.sleep(for: .milliseconds(450))
            #expect(model.saveState == savedState)
        }
    }

    @Test func explicitSaveIsImmediateAndCancelsPendingAutosave() async throws {
        try await withWorkspace { model, repository, project in
            let chapter = try #require(model.selectedChapter)
            model.updateText("第一版")
            model.updateText("最新版本")
            model.flushCurrentChapter()
            let savedState = model.saveState
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "最新版本")
            try await Task.sleep(for: .milliseconds(450))
            #expect(model.saveState == savedState)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "最新版本")
        }
    }

    @Test func revertingToOriginalTextDoesNotLeaveUnsavedState() async throws {
        try await withWorkspace { model, repository, project in
            let chapter = try #require(model.selectedChapter)
            let originalText = model.chapterText
            model.updateText("临时修改")
            model.updateText(originalText)
            try await waitForAutosave(model)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == originalText)
        }
    }

    @Test func switchingChaptersFlushesAndIgnoresOldEditorActivity() async throws {
        try await withWorkspace { model, repository, project in
            let firstChapter = try #require(model.selectedChapter)
            model.updateText("第一章内容")
            model.recordEditorActivity(isBusy: true, chapterID: firstChapter.id)
            model.addChapter(title: "第二章")
            let secondChapter = try #require(model.selectedChapter)
            #expect(firstChapter.id != secondChapter.id)
            #expect(try repository.readChapter(firstChapter, in: project.rootURL) == "第一章内容")

            model.updateText("第二章内容")
            model.recordEditorActivity(isBusy: true, chapterID: firstChapter.id)
            try await waitForAutosave(model)
            #expect(try repository.readChapter(secondChapter, in: project.rootURL) == "第二章内容")
            #expect(try repository.readChapter(firstChapter, in: project.rootURL) == "第一章内容")
        }
    }

    private func withWorkspace(
        _ body: (BookWorkspaceModel, BookRepository, OpenBookProject) async throws -> Void
    ) async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repository = BookRepository()
        let project = try repository.createBook(title: "闲置保存", author: "", in: parent)
        let model = BookWorkspaceModel(project: project, autosaveIdleDuration: .milliseconds(200))
        model.start()
        try await body(model, repository, project)
    }

    private func waitForAutosave(_ model: BookWorkspaceModel) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if case .saved = model.saveState { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Autosave did not complete: \(model.saveState)")
    }
}
