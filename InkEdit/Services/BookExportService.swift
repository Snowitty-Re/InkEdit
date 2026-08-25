import Foundation
import UniformTypeIdentifiers

enum BookExportError: LocalizedError {
    case noChapters

    var errorDescription: String? {
        switch self {
        case .noChapters: "书籍中没有可导出的章节。"
        }
    }
}

@MainActor
struct BookExportService {
    private let repository = BookRepository()
    private let htmlRenderer = MarkdownHTMLRenderer()

    func publication(project: BookProject, rootURL: URL) throws -> PublicationDocument {
        let chapters = try project.chapters.map { chapter in
            PublicationChapter(
                id: chapter.id,
                title: chapter.title,
                markdown: try repository.readChapter(chapter, in: rootURL)
            )
        }
        guard !chapters.isEmpty else { throw BookExportError.noChapters }
        return PublicationDocument(
            id: project.id,
            title: project.title,
            author: project.author,
            language: project.language,
            summary: project.summary,
            modifiedAt: project.modifiedAt,
            chapters: chapters,
            resources: try resources(in: chapters, rootURL: rootURL)
        )
    }

    func export(
        _ format: ExportFormat,
        project: BookProject,
        rootURL: URL,
        destinationURL: URL
    ) async throws {
        let publication = try publication(project: project, rootURL: rootURL)
        let data: Data
        switch format {
        case .html:
            data = Data(html(publication).utf8)
        case .pdf:
            data = try await PDFDataExporter().render(html: html(publication), baseURL: rootURL)
        case .epub:
            data = try EPUBBuilder().build(publication)
        case .docx:
            data = try DOCXBuilder().build(publication)
        }
        try AtomicFileWriter.write(data, to: destinationURL)
    }

    private func html(_ publication: PublicationDocument) -> String {
        let markdown = replacingResourcesWithDataURLs(
            in: publication.combinedMarkdown,
            resources: publication.resources
        )
        return htmlRenderer.render(
            markdown: markdown,
            title: publication.title,
            theme: .light,
            annotations: [],
            interactive: false
        )
    }

    private func resources(
        in chapters: [PublicationChapter],
        rootURL: URL
    ) throws -> [PublicationResource] {
        let references =
            chapters
            .flatMap { imageReferences(in: $0.markdown) }
            .reduce(into: [String]()) { result, reference in
                if !result.contains(reference) { result.append(reference) }
            }
        return try references.enumerated().compactMap { index, reference in
            guard
                !reference.hasPrefix("#"),
                URL(string: reference)?.scheme == nil
            else { return nil }
            let decoded = reference.removingPercentEncoding ?? reference
            let sourceURL = try repository.safeURL(for: decoded, in: rootURL)
            guard
                FileManager.default.fileExists(atPath: sourceURL.path),
                !sourceURL.hasDirectoryPath
            else { return nil }
            let pathExtension = sourceURL.pathExtension.lowercased()
            let mediaType = UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let filename =
                String(format: "resource-%03d", index + 1)
                + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
            return PublicationResource(
                sourceReference: reference,
                archivePath: "images/\(filename)",
                mediaType: mediaType,
                data: try Data(contentsOf: sourceURL)
            )
        }
    }

    private func imageReferences(in markdown: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"!\[[^]]*\]\(([^)]+)\)"#) else { return [] }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return expression.matches(in: markdown, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: markdown) else { return nil }
            return String(markdown[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func replacingResourcesWithDataURLs(
        in markdown: String,
        resources: [PublicationResource]
    ) -> String {
        resources.reduce(markdown) { result, resource in
            let dataURL = "data:\(resource.mediaType);base64,\(resource.data.base64EncodedString())"
            return result.replacingOccurrences(
                of: "](\(resource.sourceReference))",
                with: "](\(dataURL))"
            )
        }
    }
}
