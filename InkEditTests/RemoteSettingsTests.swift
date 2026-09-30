import Foundation
import Testing

@testable import InkEdit

@MainActor
struct RemoteSettingsTests {
    @Test func profileAndProviderDefaultsAreSeparateFromCredentials() throws {
        try withPreferences { defaults in
            defaults.set("  山间来客  ", forKey: AppPreferences.penNameKey)
            #expect(AppPreferences.penName(in: defaults) == "山间来客")
            let credentials = MemoryCredentials()
            let service = RemoteSettingsService(defaults: defaults, credentials: credentials)
            var github = CloudSyncConfiguration(provider: .github, githubOwner: " writer ", githubRepository: "books")
            try service.save(github, replacementToken: " secret-github ")
            var drive = CloudSyncConfiguration(provider: .googleDrive)
            drive.googleDriveFolderID = " folder_123 "
            try service.save(drive, replacementToken: "secret-drive")
            github.githubBranch = "draft/next"
            try service.save(github, replacementToken: "")
            #expect(try service.token(for: .github, replacement: "") == "secret-github")
            #expect(try service.token(for: .googleDrive, replacement: "") == "secret-drive")
            let saved = try AppPreferences.remote(in: defaults)
            #expect(saved.githubOwner == "writer")
            #expect(saved.githubBranch == "draft/next")
            #expect(saved.googleDriveFolderID == "folder_123")
            let data = try #require(defaults.data(forKey: AppPreferences.remoteKey))
            #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
            try service.removeCredential(for: .github)
            #expect(try !service.hasCredential(for: .github))
            #expect(try service.hasCredential(for: .googleDrive))
            #expect(try AppPreferences.remote(in: defaults) == saved)
        }
    }

    @Test func credentialFailureDoesNotReplaceDefaults() throws {
        try withPreferences { defaults in
            let credentials = MemoryCredentials()
            let service = RemoteSettingsService(defaults: defaults, credentials: credentials)
            let config = CloudSyncConfiguration(provider: .github, githubOwner: "writer", githubRepository: "books")
            try service.save(config, replacementToken: "original")
            let original = try AppPreferences.remote(in: defaults)
            credentials.failWrites = true
            var changed = config
            changed.githubRepository = "new-books"
            #expect(throws: KeychainStoreError.self) { try service.save(changed, replacementToken: "replacement") }
            #expect(try AppPreferences.remote(in: defaults) == original)
            #expect(try service.token(for: .github, replacement: "") == "original")
        }
    }

    @Test func newConnectionsInheritDefaultsButExistingConnectionsStayIndependent() throws {
        try withPreferences { defaults in
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }
            let project = try BookRepository().createBook(title: "测试作品", author: "", in: parent)
            var remote = RemoteConnectionDefaults(githubOwner: "writer", githubRepository: "books")
            try AppPreferences.saveRemote(remote, in: defaults)
            let credentials = MemoryCredentials()
            let service = CloudSyncService(defaults: defaults, credentials: credentials)
            var config = try service.configuration(for: .github, rootURL: project.rootURL)
            #expect(config.snapshotPath.contains(project.metadata.id.uuidString))
            #expect(
                !FileManager.default.fileExists(
                    atPath: project.rootURL.appendingPathComponent(ProjectSnapshotStore.syncStateRelativePath).path))
            config = try service.saveConnection(configuration: config, token: "test-token", rootURL: project.rootURL)
            // An empty replacement uses the current Keychain token, never a stale form copy.
            #expect(try service.saveConnection(configuration: config, token: "", rootURL: project.rootURL) == config)
            try credentials.deleteToken(for: .github)
            #expect(throws: CloudSyncError.missingCredential) {
                try service.saveConnection(configuration: config, token: "", rootURL: project.rootURL)
            }
            remote.githubRepository = "different"
            try AppPreferences.saveRemote(remote, in: defaults)
            #expect(try service.configuration(for: .github, rootURL: project.rootURL) == config)
            #expect(
                try service.defaultConfiguration(for: .github, projectID: project.metadata.id).githubRepository
                    == "different")
        }
    }

    @Test func oldConnectionsDecodeAndRetainTheirSnapshotPath() throws {
        let config = CloudSyncConfiguration(provider: .github, githubOwner: "writer", githubRepository: "books")
        let data = try JSONEncoder().encode(config)
        #expect(!String(decoding: data, as: UTF8.self).contains("githubSnapshotPath"))
        let decoded = try JSONDecoder().decode(CloudSyncConfiguration.self, from: data)
        #expect(decoded.snapshotPath == ".inkedit/InkEdit-backup.zip")
        let defaults = RemoteConnectionDefaults(githubOwner: "writer", githubRepository: "books")
        #expect(
            defaults.configuration(for: .github, projectID: UUID()).snapshotPath
                != defaults.configuration(for: .github, projectID: UUID()).snapshotPath)
    }

    @Test func changingDestinationClearsOnlyItsSynchronizationBaseline() {
        var original = CloudSyncConfiguration(provider: .github, githubOwner: "writer", githubRepository: "books")
        original.remoteIdentifier = "snapshot"
        original.remoteRevision = "revision"
        original.baseHashes = ["第一章.md": "hash"]
        original.lastSyncedAt = .now
        var unchanged = original
        unchanged.resetSyncStateIfDestinationChanged(from: original)
        #expect(unchanged == original)
        var changed = original
        changed.githubBranch = "draft"
        changed.resetSyncStateIfDestinationChanged(from: original)
        #expect(changed.remoteIdentifier == nil && changed.remoteRevision == nil)
        #expect(changed.baseHashes.isEmpty && changed.lastSyncedAt == nil)
        #expect(changed.githubOwner == original.githubOwner)
        var drive = original
        drive.provider = .googleDrive
        var moved = drive
        moved.googleDriveFolderID = "new-folder"
        moved.resetSyncStateIfDestinationChanged(from: drive)
        #expect(moved.remoteIdentifier == nil)
    }

    @Test func invalidLocationsAreRejectedBeforeSaving() throws {
        try withPreferences { defaults in
            let credentials = MemoryCredentials()
            let service = RemoteSettingsService(defaults: defaults, credentials: credentials)
            let config = CloudSyncConfiguration(
                provider: .github, githubOwner: "https://github.com/writer", githubRepository: "books")
            #expect(throws: CloudSyncError.self) { try service.save(config, replacementToken: "secret") }
            #expect(credentials.values.isEmpty)
            var drive = CloudSyncConfiguration(provider: .googleDrive)
            drive.googleDriveFolderID = "folder' or trashed=true"
            #expect(throws: CloudSyncError.self) { try drive.normalized() }
        }
    }

    private func withPreferences(_ body: (UserDefaults) throws -> Void) throws {
        let name = "InkEdit-RemoteSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}

private final class MemoryCredentials: CloudCredentialStore {
    var values: [CloudProvider: String] = [:]
    var failWrites = false
    func token(for provider: CloudProvider) throws -> String? { values[provider] }
    func saveToken(_ token: String, for provider: CloudProvider) throws {
        if failWrites { throw KeychainStoreError.unexpectedStatus(-1) }
        values[provider] = token
    }
    func deleteToken(for provider: CloudProvider) throws { values[provider] = nil }
}
