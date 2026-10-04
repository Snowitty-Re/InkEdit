import Foundation
import PDFKit
import Testing
import os

@testable import InkEdit

@MainActor
struct BookExportServiceTests {
    @Test(arguments: ExportFormat.allCases)
    func exportsOnlySelectedChaptersInEveryFormat(_ format: ExportFormat) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 5, paragraphCount: 1)
        var selection = ExportChapterSelection(chapters: project.chapters, currentChapterID: project.chapters[3].id)
        selection.scope = .partial
        selection.startChapterID = project.chapters[1].id
        selection.excludedChapterIDs = [project.chapters[2].id]
        let ids = Set(selection.selectedChapters(in: project.chapters).map(\.id))
        let destination = root.appendingPathComponent("部分成书.\(format.filenameExtension)")
        try await BookExportService().export(
            format, project: project, rootURL: root, destinationURL: destination, chapterIDs: ids)

        let text: String
        switch format {
        case .html:
            text = try String(contentsOf: destination, encoding: .utf8)
        case .pdf:
            text = try #require(PDFDocument(url: destination)?.string)
        case .epub, .docx:
            let entries = try ZIPArchiveReader().entries(in: Data(contentsOf: destination))
            text = entries.map { String(decoding: $0.data, as: UTF8.self) }.joined()
            if format == .epub {
                #expect(entries.filter { $0.path.hasPrefix("EPUB/text/") }.count == 2)
                let navigation = try #require(entries.first { $0.path == "EPUB/nav.xhtml" })
                let contents = String(decoding: navigation.data, as: UTF8.self)
                #expect(contents.contains("第2章"))
                #expect(contents.contains("第4章"))
                #expect(!contents.contains("第3章"))
            }
        }
        #expect(text.contains("章节终点2"))
        #expect(text.contains("章节终点4"))
        for index in [1, 3, 5] {
            #expect(!text.contains("章节终点\(index)"))
        }
        #expect(try #require(text.range(of: "章节终点2")).lowerBound < #require(text.range(of: "章节终点4")).lowerBound)
    }

    @Test func excludedChaptersAreNotReadAndTheirImagesAreNotCollected() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 3, paragraphCount: 1)
        try "![保留](keep.png)".write(to: root.appendingPathComponent("第1章.md"), atomically: true, encoding: .utf8)
        try "![排除](omit.png)".write(to: root.appendingPathComponent("第2章.md"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: root.appendingPathComponent("keep.png"))
        try Data([2]).write(to: root.appendingPathComponent("omit.png"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("第3章.md"))
        let publication = try await BookExportService().publication(
            project: project, rootURL: root, chapterIDs: [project.chapters[0].id])
        #expect(publication.chapters.map(\.id) == [project.chapters[0].id])
        #expect(publication.resources.map(\.sourceReference) == ["keep.png"])
    }

    @Test func emptySelectionDoesNotOverwriteDestination() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 1, paragraphCount: 1)
        let destination = root.appendingPathComponent("成书.html")
        try Data("已有导出".utf8).write(to: destination)
        do {
            try await BookExportService().export(
                .html, project: project, rootURL: root, destinationURL: destination, chapterIDs: [])
            Issue.record("Empty selection unexpectedly exported the book")
        } catch BookExportError.noChapters {}
        #expect(try String(contentsOf: destination, encoding: .utf8) == "已有导出")
    }

    @Test(arguments: [ExportFormat.epub, .docx])
    func exportsLargeManuscriptWhileMainActorRemainsResponsive(_ format: ExportFormat) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 24, paragraphCount: 180)
        let destination = root.appendingPathComponent("成书.\(format.filenameExtension)")
        let mainThreadObservations = OSAllocatedUnfairLock(initialState: [Bool]())
        let service = BookExportService { _ in
            mainThreadObservations.withLock { $0.append(Thread.isMainThread) }
        }

        try await service.export(format, project: project, rootURL: root, destinationURL: destination)

        // Verify real preparation/build/write execution, not scheduler-dependent heartbeat counts.
        let observations = mainThreadObservations.withLock { $0 }
        #expect(observations.count == 3)
        #expect(observations.allSatisfy { !$0 })
        let entries = try ZIPArchiveReader().entries(in: Data(contentsOf: destination))
        let lastChapter = format == .epub ? "EPUB/text/chapter-024.xhtml" : "word/document.xml"
        let content = try #require(entries.first { $0.path == lastChapter })
        #expect(String(decoding: content.data, as: UTF8.self).contains("章节终点24"))
    }

    @Test func exportsPaginatedA4PDFWithFirstAndLastChapter() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 2, paragraphCount: 12)
        let destination = root.appendingPathComponent("成书.pdf")

        try await BookExportService().export(.pdf, project: project, rootURL: root, destinationURL: destination)

        let document = try #require(PDFDocument(url: destination))
        #expect(document.pageCount > 1)
        #expect(document.string?.contains("章节终点1") == true)
        #expect(document.string?.contains("章节终点2") == true)
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            #expect(abs(page.bounds(for: .mediaBox).width - 595.2) < 1)
            #expect(abs(page.bounds(for: .mediaBox).height - 841.8) < 1)
        }
    }

    @Test func cancellationPreservesExistingDestination() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 1, paragraphCount: 1)
        let destination = root.appendingPathComponent("成书.epub")
        let original = Data("existing export".utf8)
        try original.write(to: destination)
        let task = Task { @MainActor in
            try await BookExportService().export(.epub, project: project, rootURL: root, destinationURL: destination)
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("Cancelled export unexpectedly succeeded")
        } catch is CancellationError {}
        #expect(try Data(contentsOf: destination) == original)
    }

    @Test func pdfTimeoutAndCancellationReturnErrors() async throws {
        let root = FileManager.default.temporaryDirectory
        do {
            _ = try await PDFDataExporter().render(html: "<p>正文</p>", baseURL: root, timeout: .zero)
            Issue.record("PDF rendering ignored its deadline")
        } catch PDFExportError.timedOut {}
        var started = false
        let task = Task { @MainActor in
            started = true
            return try await PDFDataExporter.renderDocument(html: "<p>正文</p>", baseURL: root)
        }
        while !started { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled PDF unexpectedly succeeded")
        } catch is CancellationError {}
    }

    private func manuscript(in root: URL, chapterCount: Int, paragraphCount: Int) throws -> BookProject {
        let paragraph = String(repeating: "长夜将尽，星河欲晓。作者在窗前写下新的篇章。", count: 8)
        let outline = try (1...chapterCount).map { index in
            let name = "第\(index)章"
            let markdown =
                "# \(name)\n\n" + String(repeating: paragraph + "\n\n", count: paragraphCount)
                + "\n\n章节终点\(index)"
            try markdown.write(to: root.appendingPathComponent(name + ".md"), atomically: true, encoding: .utf8)
            return BookOutlineNode.chapter(title: name, relativePath: name + ".md")
        }
        return BookProject(title: "导出回归", author: "作者", outline: outline)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
