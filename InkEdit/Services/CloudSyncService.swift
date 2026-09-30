import Foundation

@MainActor
struct CloudSyncService {
    private let snapshotStore = ProjectSnapshotStore()
    private let repository = CloudSyncRepository()
    private let keychain: any CloudCredentialStore
    private let defaults: UserDefaults
    private let githubStore: GitHubSnapshotStore
    private let googleDriveStore: GoogleDriveSnapshotStore

    init(
        client: any CloudHTTPClient = URLSessionCloudHTTPClient(),
        defaults: UserDefaults = AppPreferences.defaults,
        credentials: any CloudCredentialStore = KeychainStore()
    ) {
        self.defaults = defaults
        keychain = credentials
        githubStore = GitHubSnapshotStore(client: client)
        googleDriveStore = GoogleDriveSnapshotStore(client: client)
    }

    func configuration(for provider: CloudProvider, rootURL: URL) throws -> CloudSyncConfiguration {
        let document = try repository.load(in: rootURL)
        if let existing = document.configurations.first(where: { $0.provider == provider }) { return existing }
        let project = try BookRepository().loadProject(at: rootURL)
        return try defaultConfiguration(for: provider, projectID: project.id)
    }

    func defaultConfiguration(for provider: CloudProvider, projectID: UUID) throws -> CloudSyncConfiguration {
        try AppPreferences.remote(in: defaults).configuration(for: provider, projectID: projectID)
    }

    func token(for provider: CloudProvider) throws -> String {
        try keychain.token(for: provider) ?? ""
    }

    @discardableResult
    func saveConnection(
        configuration: CloudSyncConfiguration,
        token: String,
        rootURL: URL
    ) throws -> CloudSyncConfiguration {
        var configuration = try configuration.normalized()
        let replacement = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = replacement.isEmpty ? try requiredToken(configuration.provider) : replacement
        guard !credential.isEmpty else { throw CloudSyncError.missingCredential }
        let old = try repository.load(in: rootURL).configuration(for: configuration.provider)
        configuration.resetSyncStateIfDestinationChanged(from: old)
        if !replacement.isEmpty { try keychain.saveToken(credential, for: configuration.provider) }
        try save(configuration, rootURL: rootURL)
        return configuration
    }

    func push(
        configuration: CloudSyncConfiguration,
        project: BookProject,
        rootURL: URL
    ) async throws -> (CloudSyncConfiguration, CloudSyncResult) {
        let token = try requiredToken(configuration.provider)
        let snapshot = try snapshotStore.capture(rootURL: rootURL)
        let archive = try snapshot.archive(date: .now)
        let upload: RemoteUploadResult
        switch configuration.provider {
        case .github:
            upload = try await githubStore.upload(
                archive,
                configuration: configuration,
                token: token,
                expectedRevision: configuration.remoteRevision
            )
        case .googleDrive:
            upload = try await googleDriveStore.upload(
                archive,
                configuration: configuration,
                projectID: project.id,
                projectTitle: project.title,
                token: token,
                expectedRevision: configuration.remoteRevision
            )
        }
        let now = Date.now
        var updated = configuration
        updated.remoteIdentifier = upload.identifier
        updated.remoteRevision = upload.revision
        updated.baseHashes = snapshot.hashes
        updated.lastSyncedAt = now
        try save(updated, rootURL: rootURL)
        return (
            updated,
            CloudSyncResult(changedFileCount: snapshot.entries.count, conflictFileCount: 0, syncedAt: now)
        )
    }

    func pull(
        configuration: CloudSyncConfiguration,
        project: BookProject,
        rootURL: URL
    ) async throws -> (CloudSyncConfiguration, CloudSyncResult) {
        let token = try requiredToken(configuration.provider)
        let remote: RemoteCloudSnapshot?
        switch configuration.provider {
        case .github:
            remote = try await githubStore.download(configuration: configuration, token: token)
        case .googleDrive:
            remote = try await googleDriveStore.download(
                configuration: configuration,
                projectID: project.id,
                token: token
            )
        }
        guard let remote else { throw CloudSyncError.noRemoteSnapshot }
        let remoteSnapshot = try ProjectSnapshot.decode(archive: remote.data)
        let result = try snapshotStore.merge(
            remote: remoteSnapshot,
            into: rootURL,
            baseHashes: configuration.baseHashes
        )
        var updated = configuration
        updated.remoteIdentifier = remote.identifier
        updated.remoteRevision = remote.revision
        updated.baseHashes = remoteSnapshot.hashes
        updated.lastSyncedAt = result.syncedAt
        try save(updated, rootURL: rootURL)
        return (updated, result)
    }

    private func requiredToken(_ provider: CloudProvider) throws -> String {
        guard let token = try keychain.token(for: provider), !token.isEmpty else {
            throw CloudSyncError.missingCredential
        }
        return token
    }

    private func save(_ configuration: CloudSyncConfiguration, rootURL: URL) throws {
        var document = try repository.load(in: rootURL)
        document.update(configuration)
        try repository.save(document, in: rootURL)
    }
}
