import Foundation

struct LibraryPreview: Sendable {
    let summary: String
    let chapterCount: Int
    let wordCount: Int
}

actor LibraryPreviewService {
    func load(bookmark: Data) throws -> LibraryPreview {
        let access = try BookAccessController.resolve(bookmark)
        defer { access.stop() }
        return try load(at: access.url)
    }

    /// The caller owns security-scoped access for the lifetime of this read.
    func load(at rootURL: URL) throws -> LibraryPreview {
        try Task.checkCancellation()
        let repository = BookRepository()
        let project = try repository.loadProject(at: rootURL)
        var words = 0
        for chapter in project.chapters {
            try Task.checkCancellation()
            let text = try repository.readChapter(chapter, in: rootURL)
            words += WritingStatistics(markdown: text).wordCount
        }
        return LibraryPreview(summary: project.summary, chapterCount: project.chapters.count, wordCount: words)
    }
}
