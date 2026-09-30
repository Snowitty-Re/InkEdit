import Foundation

@MainActor
struct RemoteSettingsService {
    let defaults: UserDefaults
    let credentials: any CloudCredentialStore

    init(defaults: UserDefaults = AppPreferences.defaults, credentials: any CloudCredentialStore = KeychainStore()) {
        self.defaults = defaults
        self.credentials = credentials
    }

    func configuration(for provider: CloudProvider) throws -> CloudSyncConfiguration {
        try AppPreferences.remote(in: defaults).configuration(for: provider, projectID: UUID())
    }

    func hasCredential(for provider: CloudProvider) throws -> Bool {
        !(try credentials.token(for: provider) ?? "").isEmpty
    }

    func token(for provider: CloudProvider, replacement: String) throws -> String {
        let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = replacement.isEmpty ? try credentials.token(for: provider) ?? "" : replacement
        guard !value.isEmpty else { throw CloudSyncError.missingCredential }
        return value
    }

    func save(_ configuration: CloudSyncConfiguration, replacementToken: String) throws {
        let config = try configuration.normalized()
        var value = try AppPreferences.remote(in: defaults)
        if config.provider == .github {
            value.githubOwner = config.githubOwner
            value.githubRepository = config.githubRepository
            value.githubBranch = config.githubBranch
        } else {
            value.googleDriveFolderID = config.googleDriveFolderID ?? ""
        }
        let credential = replacementToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !credential.isEmpty { try credentials.saveToken(credential, for: config.provider) }
        try AppPreferences.saveRemote(value, in: defaults)
    }

    func removeCredential(for provider: CloudProvider) throws {
        try credentials.deleteToken(for: provider)
    }
}
