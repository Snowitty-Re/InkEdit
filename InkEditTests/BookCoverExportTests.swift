import Foundation
import PDFKit
import Testing

@testable import InkEdit

extension BookDetailsServiceTests {
    @Test(arguments: ExportFormat.allCases)
    func exportsSavedCoverAndAuthor(_ format: ExportFormat) async throws {
        try await withBook { project, _ in
            var draft = BookDetailsDraft(project: project.metadata)
            draft.author = "雪与星"
            draft.summary = "封面回归简介"
            draft.cover = .replace(try imageData())
            let updated = try await BookDetailsService().save(
                draft, projectID: project.metadata.id, rootURL: project.rootURL)
            let destination = project.rootURL.appendingPathComponent("带封面.\(format.filenameExtension)")
            try await BookExportService().export(
                format, project: updated, rootURL: project.rootURL, destinationURL: destination)
            switch format {
            case .html:
                let html = try String(contentsOf: destination, encoding: .utf8)
                #expect(html.contains("data:image/png;base64,"))
                #expect(html.contains("雪与星"))
                #expect(html.contains("封面回归简介"))
            case .pdf:
                let pdf = try #require(PDFDocument(url: destination))
                #expect(pdf.pageCount >= 2)
                #expect(pdf.string?.contains("雪与星") == true)
                #expect(pdf.page(at: 0)?.string?.contains("第一章") != true)
            case .epub, .docx:
                let entries = try ZIPArchiveReader().entries(in: Data(contentsOf: destination))
                let coverPath = format == .epub ? "EPUB/images/cover.png" : "word/media/cover.png"
                #expect(entries.contains { $0.path == coverPath })
                for entry in entries
                where entry.path.hasSuffix(".xml") || entry.path.hasSuffix(".opf") || entry.path.hasSuffix(".xhtml") {
                    #expect(XMLParser(data: entry.data).parse(), "Invalid XML: \(entry.path)")
                }
                let searchable = entries.map { String(decoding: $0.data, as: UTF8.self) }.joined()
                #expect(searchable.contains("雪与星"))
                if format == .epub {
                    #expect(searchable.contains("properties=\"cover-image\""))
                    #expect(searchable.contains("封面回归简介"))
                } else {
                    #expect(searchable.contains("r:embed=\"rIdCover\""))
                    #expect(searchable.contains("Target=\"media/cover.png\""))
                }
            }
        }
    }
}
