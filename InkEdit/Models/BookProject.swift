import Foundation

struct BookProject: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var title: String
    var author: String
    var language: String
    var summary: String
    var coverRelativePath: String?
    var outline: [BookOutlineNode]
    var createdAt: Date
    var modifiedAt: Date
    var exportPreset: ExportPreset

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        language: String = "zh-Hans",
        summary: String = "",
        coverRelativePath: String? = nil,
        outline: [BookOutlineNode] = [],
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        exportPreset: ExportPreset = .novel
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.author = author
        self.language = language
        self.summary = summary
        self.coverRelativePath = coverRelativePath
        self.outline = outline
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.exportPreset = exportPreset
    }

    var chapters: [BookOutlineNode] {
        outline.flatMap(\.flattenedChapters)
    }
}

struct BookOutlineNode: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case part
        case chapter
    }

    var id: UUID
    var kind: Kind
    var title: String
    var relativePath: String?
    var children: [BookOutlineNode]

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        relativePath: String? = nil,
        children: [BookOutlineNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.relativePath = relativePath
        self.children = children
    }

    static func chapter(title: String, relativePath: String) -> Self {
        Self(kind: .chapter, title: title, relativePath: relativePath)
    }

    static func part(title: String, children: [Self]) -> Self {
        Self(kind: .part, title: title, children: children)
    }

    var flattenedChapters: [Self] {
        switch kind {
        case .part:
            children.flatMap(\.flattenedChapters)
        case .chapter:
            [self]
        }
    }
}

enum ExportPreset: String, Codable, CaseIterable, Sendable {
    case novel
    case manuscript
    case screen
}

struct AnnotationDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var annotations: [BookAnnotation] = []
}

struct BookAnnotation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case highlight
        case note
    }

    var id: UUID
    var chapterRelativePath: String
    var kind: Kind
    var colorName: String
    var selectedText: String
    var prefix: String
    var suffix: String
    var utf16Location: Int
    var utf16Length: Int
    var chapterDigest: String
    var note: String
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        chapterRelativePath: String,
        kind: Kind,
        colorName: String = "yellow",
        selectedText: String,
        prefix: String,
        suffix: String,
        utf16Location: Int,
        utf16Length: Int,
        chapterDigest: String,
        note: String = "",
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.chapterRelativePath = chapterRelativePath
        self.kind = kind
        self.colorName = colorName
        self.selectedText = selectedText
        self.prefix = prefix
        self.suffix = suffix
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.chapterDigest = chapterDigest
        self.note = note
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

struct OpenBookProject: Sendable {
    var rootURL: URL
    var metadata: BookProject
}
