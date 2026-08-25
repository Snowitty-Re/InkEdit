import CryptoKit
import Foundation

struct ProjectSnapshotEntry: Equatable, Sendable {
    var path: String
    var data: Data

    var digest: String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ProjectSnapshot: Equatable, Sendable {
    var entries: [ProjectSnapshotEntry]

    var hashes: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.digest) })
    }

    func archive(date: Date = .now) throws -> Data {
        try ZIPArchiveWriter().archive(
            entries: entries.map { ZIPArchiveEntry(path: $0.path, data: $0.data) },
            date: date
        )
    }

    static func decode(archive: Data) throws -> Self {
        Self(
            entries: try ZIPArchiveReader().entries(in: archive).map {
                ProjectSnapshotEntry(path: $0.path, data: $0.data)
            }
        )
    }
}

struct ProjectSnapshotStore {
    static let syncStateRelativePath = ".inkedit/cloud-sync.json"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func capture(rootURL: URL) throws -> ProjectSnapshot {
        guard
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { _, _ in false }
            )
        else { return ProjectSnapshot(entries: []) }

        var entries: [ProjectSnapshotEntry] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let path = relativePath(of: url, rootURL: rootURL)
            guard shouldInclude(path: path) else { continue }
            entries.append(ProjectSnapshotEntry(path: path, data: try Data(contentsOf: url)))
        }
        return ProjectSnapshot(
            entries: entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
    }

    func merge(
        remote: ProjectSnapshot,
        into rootURL: URL,
        baseHashes: [String: String],
        now: Date = .now
    ) throws -> CloudSyncResult {
        let local = try capture(rootURL: rootURL)
        let localByPath = Dictionary(uniqueKeysWithValues: local.entries.map { ($0.path, $0) })
        var changed = 0
        var conflicts = 0

        for remoteEntry in remote.entries {
            guard shouldInclude(path: remoteEntry.path) else { continue }
            let localEntry = localByPath[remoteEntry.path]
            guard localEntry?.digest != remoteEntry.digest else { continue }
            let baseDigest = baseHashes[remoteEntry.path]
            let localChanged = localEntry != nil && localEntry?.digest != baseDigest
            let remoteChanged = remoteEntry.digest != baseDigest
            if localChanged && remoteChanged {
                try writeConflict(remoteEntry, rootURL: rootURL, now: now)
                conflicts += 1
            } else {
                try AtomicFileWriter.write(remoteEntry.data, to: safeURL(for: remoteEntry.path, rootURL: rootURL))
                changed += 1
            }
        }
        return CloudSyncResult(changedFileCount: changed, conflictFileCount: conflicts, syncedAt: now)
    }

    func safeURL(for path: String, rootURL: URL) throws -> URL {
        try BookRepository().safeURL(for: path, in: rootURL)
    }

    private func writeConflict(_ entry: ProjectSnapshotEntry, rootURL: URL, now: Date) throws {
        let source = entry.path as NSString
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = " (云端冲突 \(formatter.string(from: now)))"
        let pathExtension = source.pathExtension
        let stem = source.lastPathComponent as NSString
        let filename = stem.deletingPathExtension + suffix
        let conflictName = pathExtension.isEmpty ? filename : "\(filename).\(pathExtension)"
        let directory = source.deletingLastPathComponent
        let relativePath = directory.isEmpty ? conflictName : "\(directory)/\(conflictName)"
        var destination = try safeURL(for: relativePath, rootURL: rootURL)
        var copyNumber = 2
        while fileManager.fileExists(atPath: destination.path) {
            let numberedName = "\(filename) \(copyNumber)" + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
            let numberedPath = directory.isEmpty ? numberedName : "\(directory)/\(numberedName)"
            destination = try safeURL(for: numberedPath, rootURL: rootURL)
            copyNumber += 1
        }
        try AtomicFileWriter.write(entry.data, to: destination)
    }

    private func relativePath(of url: URL, rootURL: URL) -> String {
        url.standardizedFileURL.pathComponents
            .dropFirst(rootURL.standardizedFileURL.pathComponents.count)
            .joined(separator: "/")
    }

    private func shouldInclude(path: String) -> Bool {
        let components = path.split(separator: "/")
        return !path.isEmpty
            && path != Self.syncStateRelativePath
            && !components.contains(".DS_Store")
            && !components.contains(".git")
    }
}
