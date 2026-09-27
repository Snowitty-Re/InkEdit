#if DEBUG
    import Foundation
    import SwiftData

    /// Only used with an explicit UI-test launch argument and an in-memory library.
    @MainActor
    enum ShowcaseFixtures {
        static func populate(_ context: ModelContext) throws {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent("showcase-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let repository = BookRepository()
            let titles = ["山月来信", "潮汐之间", "春山可望", "长街听雨", "远岸", "风经过的地方"]
            let authors = ["林见山", "陆听澜", "许知春", "沈迟", "温书", "南枝"]
            for (index, title) in titles.enumerated() {
                var project = try repository.createBook(title: title, author: authors[index], in: parent)
                project.metadata.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!
                project.metadata.summary = "在平凡的日子里，拾起那些被风吹散的片段。关于故乡、远行，与岁月深处未曾寄出的信。"
                for chapterTitle in ["第二章 · 风起", "第三章 · 归途"] {
                    project.metadata = try repository.addChapter(
                        title: chapterTitle, to: project.metadata, in: project.rootURL)
                }
                for chapter in project.metadata.chapters {
                    try repository.writeChapter(
                        "# \(chapter.title)\n\n傍晚的风穿过旧街，带来一阵遥远的松香。她在窗前坐下，把一封没有写完的信重新展开。\n\n院子里的树已经很高了，光从枝叶之间落下来，像散在纸上的旧时光。\n\n## 一封未寄出的信\n\n**有些故事，要等到安静下来才听得见。**\n\n她写下第一个字，停了一会儿，又继续写下去。窗外的山色一点一点地沉入暮色，而灯下的纸仍然温暖。\n\n> 我们终将走向远方，也终将学会回望。\n",
                        chapter: chapter, in: project.rootURL)
                }
                try repository.saveProject(project.metadata, at: project.rootURL)
                let book = LibraryBook(
                    projectID: project.metadata.id, title: title, author: authors[index],
                    rootPath: project.rootURL.path,
                    rootBookmark: try BookAccessController.makeBookmark(for: project.rootURL))
                book.lastOpenedAt = Date.now.addingTimeInterval(Double(-index) * 3600)
                book.isFavorite = index == 0 || index == 2
                context.insert(book)
            }
            try context.save()
        }
    }
#endif
