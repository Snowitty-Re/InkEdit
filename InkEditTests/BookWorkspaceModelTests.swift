import Foundation
import Testing

@testable import InkEdit

@MainActor
struct BookWorkspaceModelTests {
    @Test func failedSaveKeepsDraftAndBlocksChapterNavigationUntilRetry() async throws {
        try await withWorkspace { model, repository, project, clock in
            let first = try #require(model.selectedChapter)
            model.addChapter(title: "第二章")
            let second = try #require(model.selectedChapter)
            model.selectChapter(id: first.id)
            model.updateText("不能丢失的未保存书稿")
            let file = try repository.safeURL(for: try #require(first.relativePath), in: project.rootURL)
            let backup = file.appendingPathExtension("test-backup")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

            model.selectChapter(id: second.id)
            #expect(model.selectedChapterID == first.id)
            #expect(model.chapterText == "不能丢失的未保存书稿")
            #expect(model.errorMessage != nil)
            model.addChapter(title: "不应创建的第三章")
            #expect(model.chapters.count == 2)
            #expect(model.chapterText == "不能丢失的未保存书稿")
            #expect(!model.flushCurrentChapter())

            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: backup, to: file)
            #expect(model.flushCurrentChapter())
            #expect(try repository.readChapter(first, in: project.rootURL) == "不能丢失的未保存书稿")
            model.selectChapter(id: second.id)
            #expect(model.selectedChapterID == second.id)
        }
    }

    @Test func repeatedStartDoesNotDiscardAnUnsavedDraft() async throws {
        try await withWorkspace { model, _, _, clock in
            model.updateText("视图重新出现时也必须保留")
            model.start()
            #expect(model.chapterText == "视图重新出现时也必须保留")
            #expect(model.saveState == .unsaved)
            model.flushCurrentChapter()
        }
    }

    @Test func failedChapterReadDoesNotRetargetEditorOrOverwriteMissingChapter() async throws {
        try await withWorkspace { model, repository, project, clock in
            let first = try #require(model.selectedChapter)
            model.addChapter(title: "第二章")
            let second = try #require(model.selectedChapter)
            model.selectChapter(id: first.id)
            let file = try repository.safeURL(for: try #require(second.relativePath), in: project.rootURL)
            try FileManager.default.removeItem(at: file)

            model.selectChapter(id: second.id)
            #expect(model.selectedChapterID == first.id)
            model.updateText("仍在编辑第一章")
            model.flushCurrentChapter()
            #expect(try repository.readChapter(first, in: project.rootURL) == "仍在编辑第一章")
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func initialReadFailureDoesNotExposeAnEditableChapter() async throws {
        try await withWorkspace { model, repository, project, clock in
            let chapter = try #require(model.selectedChapter)
            let file = try repository.safeURL(for: try #require(chapter.relativePath), in: project.rootURL)
            try FileManager.default.removeItem(at: file)
            let reopened = BookWorkspaceModel(project: project)
            reopened.start()
            #expect(reopened.selectedChapter == nil)
            reopened.updateText("不应写入读取失败的章节")
            reopened.flushCurrentChapter()
            #expect(reopened.chapterText.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func sustainedInteractionBlocksSaveUntilItEnds() async throws {
        try await withWorkspace { model, repository, project, clock in
            let chapter = try #require(model.selectedChapter)
            let originalText = model.chapterText
            model.updateText("待保存")
            model.recordEditorActivity(isBusy: true, chapterID: chapter.id)
            await clock.advance(by: .milliseconds(450))
            #expect(model.saveState == .unsaved)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == originalText)

            model.recordEditorActivity(isBusy: false, chapterID: chapter.id)
            await clock.advance(by: .milliseconds(80))
            #expect(model.saveState == .unsaved)
            try await clock.waitForAutosave(model)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "待保存")
        }
    }

    @Test func continuousEditsSaveOnlyAfterIdle() async throws {
        try await withWorkspace { model, repository, project, clock in
            let chapter = try #require(model.selectedChapter)
            let originalText = model.chapterText
            for index in 1...5 {
                model.updateText("正文 \(index)")
                await clock.advance(by: .milliseconds(70))
                #expect(model.saveState == .unsaved)
                #expect(try repository.readChapter(chapter, in: project.rootURL) == originalText)
            }
            try await clock.waitForAutosave(model)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "正文 5")
        }
    }

    @Test func cleanActivityDoesNotSaveAgain() async throws {
        try await withWorkspace { model, _, _, clock in
            let chapter = try #require(model.selectedChapter)
            let originalState = model.saveState
            model.recordEditorActivity(isBusy: true, chapterID: chapter.id)
            model.recordEditorActivity(isBusy: false, chapterID: chapter.id)
            await clock.advance(by: .milliseconds(450))
            #expect(model.saveState == originalState)

            model.updateText("保存一次")
            try await clock.waitForAutosave(model)
            let savedState = model.saveState
            model.recordEditorActivity(isBusy: false, chapterID: chapter.id)
            await clock.advance(by: .milliseconds(450))
            #expect(model.saveState == savedState)
        }
    }

    @Test func explicitSaveIsImmediateAndCancelsPendingAutosave() async throws {
        try await withWorkspace { model, repository, project, clock in
            let chapter = try #require(model.selectedChapter)
            model.updateText("第一版")
            model.updateText("最新版本")
            model.flushCurrentChapter()
            let savedState = model.saveState
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "最新版本")
            await clock.advance(by: .milliseconds(450))
            #expect(model.saveState == savedState)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "最新版本")
        }
    }

    @Test func revertingToOriginalTextDoesNotLeaveUnsavedState() async throws {
        try await withWorkspace { model, repository, project, clock in
            let chapter = try #require(model.selectedChapter)
            let originalText = model.chapterText
            model.updateText("临时修改")
            model.updateText(originalText)
            try await clock.waitForAutosave(model)
            #expect(try repository.readChapter(chapter, in: project.rootURL) == originalText)
        }
    }

    @Test func switchingChaptersFlushesAndIgnoresOldEditorActivity() async throws {
        try await withWorkspace { model, repository, project, clock in
            let firstChapter = try #require(model.selectedChapter)
            model.updateText("第一章内容")
            model.recordEditorActivity(isBusy: true, chapterID: firstChapter.id)
            model.addChapter(title: "第二章")
            let secondChapter = try #require(model.selectedChapter)
            #expect(firstChapter.id != secondChapter.id)
            #expect(try repository.readChapter(firstChapter, in: project.rootURL) == "第一章内容")

            model.updateText("第二章内容")
            model.recordEditorActivity(isBusy: true, chapterID: firstChapter.id)
            try await clock.waitForAutosave(model)
            #expect(try repository.readChapter(secondChapter, in: project.rootURL) == "第二章内容")
            #expect(try repository.readChapter(firstChapter, in: project.rootURL) == "第一章内容")
        }
    }

    private func withWorkspace(
        _ body: (BookWorkspaceModel, BookRepository, OpenBookProject, ManualAutosaveClock) async throws -> Void
    ) async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repository = BookRepository()
        let project = try repository.createBook(title: "闲置保存", author: "", in: parent)
        let clock = ManualAutosaveClock()
        let model = BookWorkspaceModel(project: project, autosaveIdleDuration: .milliseconds(200), autosaveClock: clock)
        model.start()
        try await body(model, repository, project, clock)
    }

}
