import Foundation
import Testing

@testable import InkEdit

@MainActor
struct ExportBuilderTests {
    @Test func createsEPUBWithNavigationMetadataAndResources() throws {
        let publication = samplePublication(
            resources: [
                PublicationResource(
                    sourceReference: "images/cover.png",
                    archivePath: "images/resource-001.png",
                    mediaType: "image/png",
                    data: Data([0x89, 0x50, 0x4E, 0x47])
                )
            ]
        )

        let archive = try EPUBBuilder().build(publication)
        let searchable = String(decoding: archive, as: UTF8.self)

        #expect(archive.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        #expect(searchable.contains("application/epub+zip"))
        #expect(searchable.contains("EPUB/package.opf"))
        #expect(searchable.contains("EPUB/nav.xhtml"))
        #expect(searchable.contains("第一章"))
        #expect(searchable.contains("images/resource-001.png"))
        #expect(!searchable.contains("https://example.com/image.png"))
    }

    @Test func createsDOCXWithChineseBookStylesAndChapterText() throws {
        let archive = try DOCXBuilder().build(samplePublication())
        let searchable = String(decoding: archive, as: UTF8.self)

        #expect(searchable.contains("[Content_Types].xml"))
        #expect(searchable.contains("word/document.xml"))
        #expect(searchable.contains("word/styles.xml"))
        #expect(searchable.contains("宋体"))
        #expect(searchable.contains("长夜将尽"))
    }

    @Test func packagesLocalImagesFromBookFolder() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let repository = BookRepository()
        let opened = try repository.createBook(title: "插图测试", author: "雪", in: parent)
        let images = opened.rootURL.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: images.appendingPathComponent("封面.png"))
        try repository.writeChapter(
            "![封面](images/封面.png)",
            chapter: try #require(opened.metadata.chapters.first),
            in: opened.rootURL
        )

        let publication = try BookExportService().publication(
            project: opened.metadata,
            rootURL: opened.rootURL
        )

        #expect(publication.resources.count == 1)
        #expect(publication.resources.first?.mediaType == "image/png")
        #expect(publication.resources.first?.data == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func rejectsUnsafeZIPPaths() {
        #expect(throws: ZIPArchiveError.invalidPath("../secret")) {
            _ = try ZIPArchiveWriter().archive(
                entries: [ZIPArchiveEntry(path: "../secret", data: Data())]
            )
        }
    }

    private func samplePublication(resources: [PublicationResource] = []) -> PublicationDocument {
        PublicationDocument(
            id: UUID(uuidString: "42F62E6A-A1F7-4C94-BF89-6CA678679683")!,
            title: "长夜",
            author: "雪",
            language: "zh-Hans",
            summary: "一部测试书稿",
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            chapters: [
                PublicationChapter(
                    id: UUID(uuidString: "C0B44CA7-F8F4-4DF1-B33C-D5876410AB65")!,
                    title: "第一章",
                    markdown: "长夜将尽，**星河**欲晓。\n\n![封面](images/cover.png)\n\n![远程图](https://example.com/image.png)"
                )
            ],
            resources: resources
        )
    }
}
