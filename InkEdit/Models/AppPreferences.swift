import Foundation

struct RemoteConnectionDefaults: Codable, Equatable, Sendable {
    var githubOwner = ""
    var githubRepository = ""
    var githubBranch = "main"
    var googleDriveFolderID = ""

    func configuration(for provider: CloudProvider, projectID: UUID) -> CloudSyncConfiguration {
        var result = CloudSyncConfiguration(provider: provider)
        if provider == .github {
            result.githubOwner = githubOwner
            result.githubRepository = githubRepository
            result.githubBranch = githubBranch
            result.githubSnapshotPath = ".inkedit/books/\(projectID.uuidString).zip"
        } else {
            result.googleDriveFolderID = googleDriveFolderID.isEmpty ? nil : googleDriveFolderID
        }
        return result
    }
}

@MainActor
enum AppPreferences {
    static let penNameKey = "inkedit.authorPenName"
    static let remoteKey = "inkedit.remoteDefaults"
    static let defaults: UserDefaults = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                let name = "com.snowitty.InkEdit.UITests.preferences"
                let store = UserDefaults(suiteName: name)!
                store.removePersistentDomain(forName: name)
                return store
            }
        #endif
        return .standard
    }()

    static func penName(in store: UserDefaults = defaults) -> String {
        (store.string(forKey: penNameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func remote(in store: UserDefaults = defaults) throws -> RemoteConnectionDefaults {
        guard let data = store.data(forKey: remoteKey) else { return RemoteConnectionDefaults() }
        return try JSONDecoder().decode(RemoteConnectionDefaults.self, from: data)
    }

    static func saveRemote(_ value: RemoteConnectionDefaults, in store: UserDefaults = defaults) throws {
        store.set(try JSONEncoder().encode(value), forKey: remoteKey)
    }
}
