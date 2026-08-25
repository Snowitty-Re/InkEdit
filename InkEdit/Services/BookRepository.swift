import Foundation

enum BookRepositoryError: LocalizedError, Equatable {
    case emptyTitle
    case projectAlreadyExists(String)
    case invalidProject
    case unsupportedSchema(Int)
    case unsafeRelativePath(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            String(localized: "书名不能为空。")
        case .projectAlreadyExists(let name):
            String(localized: "“\(name)”已经存在，请换一个书名或位置。")
        case .invalidProject:
            String(localized: "这个文件夹不是有效的 InkEdit 项目。")
        case .unsupportedSchema(let version):
            String(localized: "项目格式版本 \(version) 高于当前 InkEdit 支持的版本。")
        case .unsafeRelativePath(let path):
            String(localized: "项目包含不安全的文件路径：\(path)")
        }
    }
}

struct BookRepository {
    static let metadataDirectoryName = ".inkedit"
    static let projectFileName = "project.json"
    static let annotationsFileName = "annotations.json"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func createBook(title: String, author: String, in parentDirectory: URL) throws -> OpenBookProject {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw BookRepositoryError.emptyTitle
        }

        let folderName = safeFileName(normalizedTitle)
        let rootURL = parentDirectory.appendingPathComponent(folderName, isDirectory: true)
        guard !fileManager.fileExists(atPath: rootURL.path) else {
            throw BookRepositoryError.projectAlreadyExists(folderName)
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: false)
        do {
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent("assets", isDirectory: true),
                withIntermediateDirectories: false
            )
            let chapterName = "第一章.md"
            try AtomicFileWriter.write("# 第一章\n\n", to: rootURL.appendingPathComponent(chapterName))
            let project = BookProject(
                title: normalizedTitle,
                author: author.trimmingCharacters(in: .whitespacesAndNewlines),
                outline: [.chapter(title: "第一章", relativePath: chapterName)]
            )
            try initializeSidecars(project, at: rootURL)
            return OpenBookProject(rootURL: rootURL, metadata: try loadProject(at: rootURL))
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }

    func importMarkdown(_ sourceURL: URL, into parentDirectory: URL) throws -> OpenBookProject {
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let rootURL = parentDirectory.appendingPathComponent(safeFileName(title), isDirectory: true)
        guard !fileManager.fileExists(atPath: rootURL.path) else {
            throw BookRepositoryError.projectAlreadyExists(rootURL.lastPathComponent)
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: false)
        do {
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent("assets", isDirectory: true),
                withIntermediateDirectories: false
            )
            let destinationName = sourceURL.lastPathComponent
            try fileManager.copyItem(at: sourceURL, to: rootURL.appendingPathComponent(destinationName))
            let project = BookProject(
                title: title,
                outline: [.chapter(title: title, relativePath: destinationName)]
            )
            try initializeSidecars(project, at: rootURL)
            return OpenBookProject(rootURL: rootURL, metadata: try loadProject(at: rootURL))
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }

    func openOrImportFolder(_ rootURL: URL) throws -> OpenBookProject {
        let projectURL = metadataURL(for: rootURL)
        if fileManager.fileExists(atPath: projectURL.path) {
            return OpenBookProject(rootURL: rootURL, metadata: try loadProject(at: rootURL))
        }

        let outline = try scanOutline(in: rootURL)
        guard !outline.isEmpty else {
            throw BookRepositoryError.invalidProject
        }
        let project = BookProject(title: rootURL.lastPathComponent, outline: outline)
        try initializeSidecars(project, at: rootURL)
        return OpenBookProject(rootURL: rootURL, metadata: try loadProject(at: rootURL))
    }

    func loadProject(at rootURL: URL) throws -> BookProject {
        let data = try Data(contentsOf: metadataURL(for: rootURL))
        let project = try decoder.decode(BookProject.self, from: data)
        guard project.schemaVersion <= BookProject.currentSchemaVersion else {
            throw BookRepositoryError.unsupportedSchema(project.schemaVersion)
        }
        for chapter in project.chapters {
            if let relativePath = chapter.relativePath {
                _ = try safeURL(for: relativePath, in: rootURL)
            }
        }
        return project
    }

    func saveProject(_ project: BookProject, at rootURL: URL) throws {
        var updatedProject = project
        updatedProject.modifiedAt = .now
        try AtomicFileWriter.write(try encoder.encode(updatedProject), to: metadataURL(for: rootURL))
    }

    func readChapter(_ chapter: BookOutlineNode, in rootURL: URL) throws -> String {
        guard chapter.kind == .chapter, let relativePath = chapter.relativePath else {
            throw BookRepositoryError.invalidProject
        }
        return try String(contentsOf: safeURL(for: relativePath, in: rootURL), encoding: .utf8)
    }

    func writeChapter(_ content: String, chapter: BookOutlineNode, in rootURL: URL) throws {
        guard chapter.kind == .chapter, let relativePath = chapter.relativePath else {
            throw BookRepositoryError.invalidProject
        }
        try AtomicFileWriter.write(content, to: safeURL(for: relativePath, in: rootURL))
    }

    func addChapter(title: String, to project: BookProject, in rootURL: URL) throws -> BookProject {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw BookRepositoryError.emptyTitle
        }

        let baseName = safeFileName(normalizedTitle)
        var fileName = "\(baseName).md"
        var suffix = 2
        while fileManager.fileExists(atPath: rootURL.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(suffix).md"
            suffix += 1
        }

        try AtomicFileWriter.write("# \(normalizedTitle)\n\n", to: rootURL.appendingPathComponent(fileName))
        var updated = project
        updated.outline.append(.chapter(title: normalizedTitle, relativePath: fileName))
        do {
            try saveProject(updated, at: rootURL)
            return try loadProject(at: rootURL)
        } catch {
            try? fileManager.removeItem(at: rootURL.appendingPathComponent(fileName))
            throw error
        }
    }

    func safeURL(for relativePath: String, in rootURL: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\0") else {
            throw BookRepositoryError.unsafeRelativePath(relativePath)
        }
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw BookRepositoryError.unsafeRelativePath(relativePath)
        }
        return candidate
    }

    private func initializeSidecars(_ project: BookProject, at rootURL: URL) throws {
        let metadataDirectory = rootURL.appendingPathComponent(Self.metadataDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try AtomicFileWriter.write(try encoder.encode(project), to: metadataURL(for: rootURL))
        try AtomicFileWriter.write(
            try encoder.encode(AnnotationDocument()),
            to: metadataDirectory.appendingPathComponent(Self.annotationsFileName)
        )
    }

    private func metadataURL(for rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent(Self.metadataDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.projectFileName)
    }

    private func scanOutline(in directory: URL, relativeTo rootURL: URL? = nil) throws -> [BookOutlineNode] {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let rootURL = (rootURL ?? directory).standardizedFileURL.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return try contents.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isHidden != true else { return nil }
            if values.isDirectory == true {
                let children = try scanOutline(in: url, relativeTo: rootURL)
                return children.isEmpty ? nil : .part(title: url.lastPathComponent, children: children)
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { return nil }
            let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
            let relativePath = String(normalizedURL.path.dropFirst(rootURL.path.count + 1))
            return .chapter(title: url.deletingPathExtension().lastPathComponent, relativePath: relativePath)
        }
    }

    private func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let components = name.components(separatedBy: invalid).filter { !$0.isEmpty }
        let result = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "未命名书籍" : result
    }
}
