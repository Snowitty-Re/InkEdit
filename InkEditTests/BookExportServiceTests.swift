import Foundation
import PDFKit
import Testing

@testable import InkEdit

@MainActor
struct BookExportServiceTests {
    @Test(arguments: [ExportFormat.epub, .docx])
    func exportsLargeManuscriptWhileMainActorRemainsResponsive(_ format: ExportFormat) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try manuscript(in: root, chapterCount: 24, paragraphCount: 180)
        let destination = root.appendingPathComponent("成书.\(format.filenameExtension)")
        var ticks = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(5))
                ticks += 1
            }
        }
        defer { heartbeat.cancel() }

        try await BookExportService().export(format, project: project, rootURL: root, destinationURL: destination)

        #expect(ticks > 1)
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
