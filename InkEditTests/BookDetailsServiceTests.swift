import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import InkEdit

@MainActor
struct BookDetailsServiceTests {
    @Test func savesMetadataAndCoverWithoutChangingChapters() async throws {
        try await withBook { project, repository in
            var draft = BookDetailsDraft(project: project.metadata)
            draft.title = "  长夜新篇  "
            draft.author = "  雪 & 星  "
            draft.summary = "  中文简介\n第二行  "
            draft.cover = .replace(try imageData())
            let updated = try await BookDetailsService().save(
                draft, projectID: project.metadata.id, rootURL: project.rootURL)
            #expect(updated.title == "长夜新篇")
            #expect(updated.author == "雪 & 星")
            #expect(updated.summary == "中文简介\n第二行")
            #expect(updated.chapters == project.metadata.chapters)
            #expect(updated.id == project.metadata.id)
            #expect(try repository.loadProject(at: project.rootURL) == updated)
            let path = try #require(updated.coverRelativePath)
            #expect(path.hasPrefix("assets/cover-"))
            let image = try Data(contentsOf: repository.safeURL(for: path, in: project.rootURL))
            #expect(image.starts(with: [0x89, 0x50, 0x4e, 0x47]))
            let snapshot = try ProjectSnapshotStore().capture(rootURL: project.rootURL)
            #expect(snapshot.entries.contains { $0.path == path && $0.data == image })
        }
    }

    @Test func importingAndCancellingDoNotModifyProject() async throws {
        try await withBook { project, repository in
            let source = project.rootURL.appendingPathComponent("original.jpg")
            let original = try imageData()
            try original.write(to: source)
            let imported = try await BookDetailsService().importCover(from: source)
            #expect(imported.starts(with: [0x89, 0x50, 0x4e, 0x47]))
            #expect(try Data(contentsOf: source) == original)
            #expect(try repository.loadProject(at: project.rootURL) == project.metadata)
            #expect(
                try FileManager.default.contentsOfDirectory(
                    atPath: project.rootURL.appendingPathComponent("assets").path
                ).isEmpty)
        }
    }

    @Test func replacesAndRemovesCoverWithoutDeletingSharedImages() async throws {
        try await withBook { project, repository in
            let service = BookDetailsService()
            var draft = BookDetailsDraft(project: project.metadata)
            draft.cover = .replace(try imageData())
            let first = try await service.save(draft, projectID: project.metadata.id, rootURL: project.rootURL)
            let second = try await service.save(draft, projectID: first.id, rootURL: project.rootURL)
            #expect(first.coverRelativePath != second.coverRelativePath)
            draft.cover = .remove
            let removed = try await service.save(draft, projectID: first.id, rootURL: project.rootURL)
            #expect(removed.coverRelativePath == nil)
            for path in [try #require(first.coverRelativePath), try #require(second.coverRelativePath)] {
                #expect(
                    FileManager.default.fileExists(atPath: try repository.safeURL(for: path, in: project.rootURL).path))
            }
        }
    }

    @Test func rejectsInvalidInputWithoutReplacingExistingMetadata() async throws {
        try await withBook { project, repository in
            let service = BookDetailsService()
            var draft = BookDetailsDraft(project: project.metadata)
            draft.title = "  \n "
            do {
                _ = try await service.save(draft, projectID: project.metadata.id, rootURL: project.rootURL)
                Issue.record("Accepted an empty title")
            } catch BookRepositoryError.emptyTitle {}
            draft.title = "不应保存"
            draft.cover = .replace(Data("not an image".utf8))
            do {
                _ = try await service.save(draft, projectID: project.metadata.id, rootURL: project.rootURL)
                Issue.record("Accepted an invalid cover")
            } catch BookDetailsError.invalidImage {}
            #expect(try repository.loadProject(at: project.rootURL) == project.metadata)
            do {
                _ = try await service.coverData(relativePath: "../outside.png", rootURL: project.rootURL)
                Issue.record("Accepted a cover outside the project")
            } catch BookRepositoryError.unsafeRelativePath {}
            #expect(throws: BookDetailsError.self) {
                try CoverImageProcessor.pngData(from: Data(repeating: 0, count: 20 * 1024 * 1024 + 1))
            }
        }
    }

    @Test func staleDraftPreservesNewChaptersAndPendingEditorText() async throws {
        try await withBook { project, repository in
            let model = BookWorkspaceModel(project: project)
            model.start()
            model.updateText("还没保存的正文")
            let chapterID = model.selectedChapterID
            var draft = BookDetailsDraft(project: project.metadata)
            draft.author = "新笔名"
            let expanded = try repository.addChapter(title: "第二章", to: project.metadata, in: project.rootURL)
            let updated = try await BookDetailsService().save(
                draft, projectID: project.metadata.id, rootURL: project.rootURL)
            #expect(updated.chapters == expanded.chapters)
            model.applyProjectDetails(updated)
            #expect(model.chapterText == "还没保存的正文")
            #expect(model.selectedChapterID == chapterID)
            #expect(model.project.author == "新笔名")
            model.flushCurrentChapter()
        }
    }

    func imageData() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 12, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 18))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func withBook(_ body: (OpenBookProject, BookRepository) async throws -> Void) async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repository = BookRepository()
        let project = try repository.createBook(title: "原书名", author: "原作者", in: parent)
        try await body(project, repository)
    }
}
