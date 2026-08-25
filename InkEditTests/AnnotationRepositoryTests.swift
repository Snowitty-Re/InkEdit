import Foundation
import Testing

@testable import InkEdit

struct AnnotationRepositoryTests {
    @Test func persistsAnnotationsInProjectSidecar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metadataDirectory = root.appendingPathComponent(BookRepository.metadataDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let annotation = BookAnnotation(
            chapterRelativePath: "第一章.md",
            kind: .note,
            selectedText: "长夜将尽",
            prefix: "",
            suffix: "，星河欲晓",
            utf16Location: 0,
            utf16Length: 4,
            chapterDigest: "digest",
            note: "修改开篇节奏",
            createdAt: timestamp,
            modifiedAt: timestamp
        )
        let document = AnnotationDocument(annotations: [annotation])
        let repository = AnnotationRepository()

        try repository.save(document, in: root)

        #expect(try repository.load(in: root) == document)
        #expect(
            FileManager.default.fileExists(
                atPath: metadataDirectory.appendingPathComponent(BookRepository.annotationsFileName).path
            )
        )
    }
}
