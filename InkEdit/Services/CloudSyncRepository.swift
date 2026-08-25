import Foundation

struct CloudSyncRepository {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(in rootURL: URL) throws -> CloudSyncDocument {
        let url = stateURL(in: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return CloudSyncDocument() }
        return try decoder.decode(CloudSyncDocument.self, from: Data(contentsOf: url))
    }

    func save(_ document: CloudSyncDocument, in rootURL: URL) throws {
        try AtomicFileWriter.write(try encoder.encode(document), to: stateURL(in: rootURL))
    }

    private func stateURL(in rootURL: URL) -> URL {
        rootURL.appendingPathComponent(ProjectSnapshotStore.syncStateRelativePath)
    }
}
