import Foundation

enum CloudProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case googleDrive
    case github

    var id: Self { self }

    var title: String {
        switch self {
        case .googleDrive: "Google Drive"
        case .github: "GitHub 私有仓库"
        }
    }
}

struct CloudSyncConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var provider: CloudProvider
    var githubOwner = ""
    var githubRepository = ""
    var githubBranch = "main"
    // Optional fields preserve decoding of existing per-book connections.
    var githubSnapshotPath: String?
    var googleDriveFolderID: String?
    var remoteIdentifier: String?
    var remoteRevision: String?
    var baseHashes: [String: String] = [:]
    var lastSyncedAt: Date?

    var snapshotPath: String { githubSnapshotPath ?? ".inkedit/InkEdit-backup.zip" }

    func normalized() throws -> Self {
        var result = self
        result.githubOwner = githubOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        result.githubRepository = githubRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        result.githubBranch = githubBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = googleDriveFolderID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        result.googleDriveFolderID = folder.isEmpty ? nil : folder
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if provider == .github {
            guard !result.githubOwner.isEmpty, !result.githubRepository.isEmpty,
                result.githubOwner.unicodeScalars.allSatisfy({ safe.contains($0) }),
                result.githubRepository.unicodeScalars.allSatisfy({ safe.contains($0) }),
                ![".", ".."].contains(result.githubOwner), ![".", ".."].contains(result.githubRepository),
                !result.githubBranch.isEmpty,
                !result.githubBranch.contains(".."),
                !result.githubBranch.unicodeScalars.contains(where: {
                    CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
                }),
                !result.snapshotPath.hasPrefix("/"),
                !result.snapshotPath.split(separator: "/").contains("..")
            else { throw CloudSyncError.invalidConfiguration("请填写有效的 GitHub 所有者、仓库名和分支；不要填写仓库网址。") }
        } else if !folder.isEmpty {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
            guard folder.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw CloudSyncError.invalidConfiguration("请填写 Google Drive 文件夹 ID，而不是完整网址。")
            }
        }
        return result
    }

    mutating func resetSyncStateIfDestinationChanged(from old: Self) {
        // An explicit switch from a folder to the blank/default location means My Drive,
        // not "search all folders". Preserve nil on unchanged legacy connections.
        if provider == .googleDrive, googleDriveFolderID == nil, old.googleDriveFolderID != nil {
            googleDriveFolderID = "root"
        }
        let changed =
            provider != old.provider
            || (provider == .github
                ? githubOwner != old.githubOwner || githubRepository != old.githubRepository
                    || githubBranch != old.githubBranch || snapshotPath != old.snapshotPath
                : googleDriveFolderID != old.googleDriveFolderID)
        if changed {
            remoteIdentifier = nil
            remoteRevision = nil
            baseHashes = [:]
            lastSyncedAt = nil
        }
    }
}

struct CloudSyncDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var configurations: [CloudSyncConfiguration] = []

    func configuration(for provider: CloudProvider) -> CloudSyncConfiguration {
        configurations.first { $0.provider == provider } ?? CloudSyncConfiguration(provider: provider)
    }

    mutating func update(_ configuration: CloudSyncConfiguration) {
        configurations.removeAll { $0.provider == configuration.provider }
        configurations.append(configuration)
    }
}

struct CloudSyncResult: Equatable, Sendable {
    var changedFileCount: Int
    var conflictFileCount: Int
    var syncedAt: Date
}
