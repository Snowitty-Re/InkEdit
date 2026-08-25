import Foundation

@MainActor
struct CloudSyncService {
    private let snapshotStore = ProjectSnapshotStore()
    private let repository = CloudSyncRepository()
    private let keychain = KeychainStore()
    private let githubStore: GitHubSnapshotStore
    private let googleDriveStore: GoogleDriveSnapshotStore

    init(client: any CloudHTTPClient = URLSessionCloudHTTPClient()) {
        githubStore = GitHubSnapshotStore(client: client)
        googleDriveStore = GoogleDriveSnapshotStore(client: client)
    }

    func configuration(for provider: CloudProvider, rootURL: URL) throws -> CloudSyncConfiguration {
        try repository.load(in: rootURL).configuration(for: provider)
    }

    func token(for provider: CloudProvider) throws -> String {
        try keychain.token(for: provider) ?? ""
    }

    func saveConnection(
        configuration: CloudSyncConfiguration,
        token: String,
        rootURL: URL
    ) throws {
        let credential = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { throw CloudSyncError.missingCredential }
        if configuration.provider == .github {
            guard
                !configuration.githubOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !configuration.githubRepository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !configuration.githubBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw CloudSyncError.invalidConfiguration("请完整填写 GitHub 私有仓库信息。") }
        }
        try keychain.saveToken(credential, for: configuration.provider)
        try save(configuration, rootURL: rootURL)
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
