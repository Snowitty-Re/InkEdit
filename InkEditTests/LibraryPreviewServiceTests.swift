import Foundation
import Testing

@testable import InkEdit

struct LibraryPreviewServiceTests {
    @Test func previewReadsRealSummaryAndCountsWithoutChangingFiles() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repository = BookRepository()
        var project = try repository.createBook(title: "预览", author: "作者", in: parent)
        project.metadata.summary = "真实简介"
        project.metadata = try repository.addChapter(title: "第二章", to: project.metadata, in: project.rootURL)
        for chapter in project.metadata.chapters {
            try repository.writeChapter("你好 world", chapter: chapter, in: project.rootURL)
        }
        try repository.saveProject(project.metadata, at: project.rootURL)
        let preview = try await LibraryPreviewService().load(at: project.rootURL)
        #expect(preview.summary == "真实简介")
        #expect(preview.chapterCount == 2)
        #expect(preview.wordCount == 6)
        #expect(try repository.loadProject(at: project.rootURL) == project.metadata)
        #expect(project.metadata.coverRelativePath == nil)
        for chapter in project.metadata.chapters {
            #expect(try repository.readChapter(chapter, in: project.rootURL) == "你好 world")
        }
    }

    @Test func missingProjectDoesNotShowInventedStatistics() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await LibraryPreviewService().load(at: missing)
            Issue.record("Missing projects must surface a read error")
        } catch {}
    }
}
