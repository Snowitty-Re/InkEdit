import Foundation

struct AnnotationRepository {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(in rootURL: URL) throws -> AnnotationDocument {
        let url = annotationsURL(in: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return AnnotationDocument() }
        return try decoder.decode(AnnotationDocument.self, from: Data(contentsOf: url))
    }

    func save(_ document: AnnotationDocument, in rootURL: URL) throws {
        try AtomicFileWriter.write(try encoder.encode(document), to: annotationsURL(in: rootURL))
    }

    private func annotationsURL(in rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent(BookRepository.metadataDirectoryName, isDirectory: true)
            .appendingPathComponent(BookRepository.annotationsFileName)
    }
}
