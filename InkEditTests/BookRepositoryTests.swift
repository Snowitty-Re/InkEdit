import Foundation
import Testing

@testable import InkEdit

struct BookRepositoryTests {
    @Test func createsPortableBookProject() throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let opened = try BookRepository().createBook(title: "长夜 / 星河", author: "雪", in: parent)

        #expect(opened.metadata.title == "长夜 / 星河")
        #expect(opened.metadata.author == "雪")
        #expect(opened.metadata.chapters.map(\.relativePath) == ["第一章.md"])
        #expect(FileManager.default.fileExists(atPath: opened.rootURL.appendingPathComponent("第一章.md").path))
        #expect(
            FileManager.default.fileExists(
                atPath: opened.rootURL.appendingPathComponent(".inkedit/project.json").path
            )
        )
    }

    @Test func importsNestedMarkdownFolderInNaturalOrder() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("中文书稿")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# 第二章".write(to: root.appendingPathComponent("02 第二章.md"), atomically: true, encoding: .utf8)
        try "# 第一章".write(to: root.appendingPathComponent("01 第一章.md"), atomically: true, encoding: .utf8)
        let part = root.appendingPathComponent("第二卷")
        try FileManager.default.createDirectory(at: part, withIntermediateDirectories: true)
        try "# 第三章".write(to: part.appendingPathComponent("03 第三章.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: parent) }

        let opened = try BookRepository().openOrImportFolder(root)

        #expect(opened.metadata.chapters.map(\.relativePath) == ["01 第一章.md", "02 第二章.md", "第二卷/03 第三章.md"])
        #expect(try BookRepository().loadProject(at: root) == opened.metadata)
    }

    @Test func importsChineseNumberedChaptersInNumericOrder() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("中文章节排序")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileNames = [
            "第一百章.md", "第十一章.md", "第二章.md", "第二十一章.md", "第十章.md", "第一章.md", "第三章.md",
        ]
        for fileName in fileNames {
            try "# \(fileName)".write(
                to: root.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }
        defer { try? FileManager.default.removeItem(at: parent) }

        let opened = try BookRepository().openOrImportFolder(root)

        #expect(
            opened.metadata.chapters.map(\.relativePath) == [
                "第一章.md", "第二章.md", "第三章.md", "第十章.md", "第十一章.md", "第二十一章.md", "第一百章.md",
            ])
    }

    @Test func importsChineseNumberedPartsInNumericOrder() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("中文分卷排序")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for partName in ["第十卷", "第二卷", "第一卷"] {
            let part = root.appendingPathComponent(partName, isDirectory: true)
            try FileManager.default.createDirectory(at: part, withIntermediateDirectories: false)
            try "# 第一章".write(
                to: part.appendingPathComponent("第一章.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        defer { try? FileManager.default.removeItem(at: parent) }

        let opened = try BookRepository().openOrImportFolder(root)

        #expect(opened.metadata.outline.map(\.title) == ["第一卷", "第二卷", "第十卷"])
        #expect(
            opened.metadata.chapters.map(\.relativePath) == [
                "第一卷/第一章.md", "第二卷/第一章.md", "第十卷/第一章.md",
            ])
    }

    @Test func rejectsPathTraversal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: BookRepositoryError.unsafeRelativePath("../秘密.md")) {
            _ = try BookRepository().safeURL(for: "../秘密.md", in: root)
        }
    }

    @Test func refusesToOverwriteExistingProject() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try BookRepository().createBook(title: "同名书", author: "", in: root)

        #expect(throws: BookRepositoryError.projectAlreadyExists("同名书")) {
            _ = try BookRepository().createBook(title: "同名书", author: "", in: root)
        }
    }

    @Test func addsChapterWithoutOverwritingDuplicateNames() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let opened = try BookRepository().createBook(title: "章节测试", author: "", in: root)

        let first = try BookRepository().addChapter(title: "尾声", to: opened.metadata, in: opened.rootURL)
        let second = try BookRepository().addChapter(title: "尾声", to: first, in: opened.rootURL)

        #expect(second.chapters.map(\.relativePath) == ["第一章.md", "尾声.md", "尾声 2.md"])
        #expect(FileManager.default.fileExists(atPath: opened.rootURL.appendingPathComponent("尾声 2.md").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
