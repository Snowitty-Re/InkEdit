import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BookDetailsError: LocalizedError {
    case invalidImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取封面图片，请选择有效的 PNG、JPEG 或 HEIC 图片。"
        case .imageTooLarge: "封面图片不能超过 20 MB。"
        }
    }
}

struct BookDetailsDraft: Sendable {
    enum CoverChange: Sendable {
        case unchanged
        case remove
        case replace(Data)
    }

    var title: String
    var author: String
    var summary: String
    var cover: CoverChange = .unchanged

    init(project: BookProject) {
        title = project.title
        author = project.author
        summary = project.summary
    }
}

enum CoverImageProcessor {
    static func pngData(from data: Data) throws -> Data {
        guard data.count <= 20 * 1024 * 1024 else { throw BookDetailsError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2000,
                ] as CFDictionary)
        else { throw BookDetailsError.invalidImage }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil)
        else { throw BookDetailsError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BookDetailsError.invalidImage }
        return result as Data
    }

    static func read(from url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try pngData(from: file.read(upToCount: 20 * 1024 * 1024 + 1) ?? Data())
    }
}

actor BookDetailsService {
    private let repository = BookRepository()

    func importCover(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try CoverImageProcessor.read(from: url)
    }

    func coverData(relativePath: String?, rootURL: URL) throws -> Data? {
        guard let relativePath else { return nil }
        return try CoverImageProcessor.read(from: repository.safeURL(for: relativePath, in: rootURL))
    }

    func libraryCover(bookmark: Data, relativePath: String?) throws -> Data? {
        guard relativePath != nil else { return nil }
        let access = try BookAccessController.resolve(bookmark)
        defer { access.stop() }
        return try coverData(relativePath: relativePath, rootURL: access.url)
    }

    func save(_ draft: BookDetailsDraft, projectID: UUID, rootURL: URL) throws -> BookProject {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw BookRepositoryError.emptyTitle }
        // Reload to preserve chapters and settings changed since the panel was opened.
        var project = try repository.loadProject(at: rootURL)
        guard project.id == projectID else { throw BookRepositoryError.invalidProject }
        project.title = title
        project.author = draft.author.trimmingCharacters(in: .whitespacesAndNewlines)
        project.summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.cover {
        case .unchanged: break
        case .remove: project.coverRelativePath = nil
        case .replace(let data):
            let normalized = try CoverImageProcessor.pngData(from: data)
            let path = "assets/cover-\(UUID().uuidString).png"
            let destination = try repository.safeURL(for: path, in: rootURL)
            try AtomicFileWriter.write(normalized, to: destination)
            project.coverRelativePath = path
        }
        // Old images are deliberately retained: they may also be used in chapter content.
        try repository.saveProject(project, at: rootURL)
        return try repository.loadProject(at: rootURL)
    }
}
