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
    var remoteIdentifier: String?
    var remoteRevision: String?
    var baseHashes: [String: String] = [:]
    var lastSyncedAt: Date?
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
