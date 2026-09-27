import Foundation
import UniformTypeIdentifiers

struct ExportChapterSelection: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case partial

        var id: Self { self }
        var title: String { self == .all ? "全部章节" : "部分章节" }
    }

    var scope: Scope = .all
    var startChapterID: UUID?
    var endChapterID: UUID?
    var excludedChapterIDs: Set<UUID> = []

    init(chapters: [BookOutlineNode], currentChapterID: UUID?) {
        startChapterID = chapters.first?.id
        endChapterID = chapters.first { $0.id == currentChapterID }?.id ?? chapters.last?.id
    }

    func chaptersInRange(in chapters: [BookOutlineNode]) -> [BookOutlineNode] {
        guard
            let start = chapters.firstIndex(where: { $0.id == startChapterID }),
            let end = chapters.firstIndex(where: { $0.id == endChapterID }),
            start <= end
        else { return [] }
        return Array(chapters[start...end])
    }

    func selectedChapters(in chapters: [BookOutlineNode]) -> [BookOutlineNode] {
        guard scope == .partial else { return chapters }
        return chaptersInRange(in: chapters).filter { !excludedChapterIDs.contains($0.id) }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case html
    case pdf
    case epub
    case docx

    var id: Self { self }

    var title: String {
        switch self {
        case .html: "HTML 网页"
        case .pdf: "PDF 版式文档"
        case .epub: "EPUB 电子书"
        case .docx: "Word 文稿"
        }
    }

    var filenameExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .html: .html
        case .pdf: .pdf
        case .epub: UTType(filenameExtension: "epub") ?? .data
        case .docx: UTType(filenameExtension: "docx") ?? .data
        }
    }
}

struct PublicationChapter: Equatable, Sendable {
    var id: UUID
    var title: String
    var markdown: String
}

struct PublicationResource: Equatable, Sendable {
    var sourceReference: String
    var archivePath: String
    var mediaType: String
    var data: Data
}

struct PublicationDocument: Equatable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var language: String
    var summary: String
    var modifiedAt: Date
    var chapters: [PublicationChapter]
    var resources: [PublicationResource] = []

    var combinedMarkdown: String {
        var sections = ["# \(title)"]
        if !author.isEmpty {
            sections.append("作者：\(author)")
        }
        if !summary.isEmpty {
            sections.append(summary)
        }
        sections.append(
            contentsOf: chapters.map { chapter in
                "# \(chapter.title)\n\n\(chapter.markdown)"
            }
        )
        return sections.joined(separator: "\n\n---\n\n")
    }
}
