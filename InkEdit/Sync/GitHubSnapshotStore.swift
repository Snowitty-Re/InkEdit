import Foundation

struct GitHubSnapshotStore {
    private struct RepositoryResponse: Decodable { var `private`: Bool }
    private struct ContentResponse: Decodable {
        var sha: String
        var content: String?
    }
    private struct UploadResponse: Decodable {
        struct Content: Decodable { var sha: String }
        var content: Content
    }

    private let client: any CloudHTTPClient

    init(client: any CloudHTTPClient = URLSessionCloudHTTPClient()) {
        self.client = client
    }

    func download(configuration: CloudSyncConfiguration, token: String) async throws -> RemoteCloudSnapshot? {
        try await requirePrivateRepository(configuration: configuration, token: token)
        guard let metadata = try await metadata(configuration: configuration, token: token) else { return nil }
        var request = request(
            url: try contentsURL(configuration: configuration),
            token: token,
            accept: "application/vnd.github.raw+json"
        )
        request.httpMethod = "GET"
        let (data, response) = try await client.data(for: request)
        try client.requireSuccess(response, data: data)
        return RemoteCloudSnapshot(data: data, revision: metadata.sha, identifier: configuration.snapshotPath)
    }

    func upload(
        _ snapshot: Data,
        configuration: CloudSyncConfiguration,
        token: String,
        expectedRevision: String?
    ) async throws -> RemoteUploadResult {
        guard snapshot.count <= 100 * 1_024 * 1_024 else { throw CloudSyncError.snapshotTooLarge }
        try await requirePrivateRepository(configuration: configuration, token: token)
        let current = try await metadata(configuration: configuration, token: token)
        if let current {
            guard expectedRevision == current.sha else { throw CloudSyncError.remoteChanged }
        } else if expectedRevision != nil {
            throw CloudSyncError.remoteChanged
        }

        var payload: [String: Any] = [
            "message": "chore(sync): update InkEdit manuscript snapshot",
            "content": snapshot.base64EncodedString(),
            "branch": configuration.githubBranch,
        ]
        if let current { payload["sha"] = current.sha }
        var request = request(url: try contentsURL(configuration: configuration), token: token)
        request.httpMethod = "PUT"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await client.data(for: request)
        try client.requireSuccess(response, data: data)
        let result = try JSONDecoder().decode(UploadResponse.self, from: data)
        return RemoteUploadResult(revision: result.content.sha, identifier: configuration.snapshotPath)
    }

    private func requirePrivateRepository(
        configuration: CloudSyncConfiguration,
        token: String
    ) async throws {
        guard !configuration.githubOwner.isEmpty, !configuration.githubRepository.isEmpty else {
            throw CloudSyncError.invalidConfiguration("请填写 GitHub 仓库所有者和仓库名。")
        }
        let url = try apiURL(path: "/repos/\(configuration.githubOwner)/\(configuration.githubRepository)")
        let (data, response) = try await client.data(for: request(url: url, token: token))
        try client.requireSuccess(response, data: data)
        guard try JSONDecoder().decode(RepositoryResponse.self, from: data).private else {
            throw CloudSyncError.repositoryMustBePrivate
        }
    }

    private func metadata(
        configuration: CloudSyncConfiguration,
        token: String
    ) async throws -> ContentResponse? {
        let (data, response) = try await client.data(
            for: request(url: try contentsURL(configuration: configuration), token: token)
        )
        if response.statusCode == 404 { return nil }
        try client.requireSuccess(response, data: data)
        return try JSONDecoder().decode(ContentResponse.self, from: data)
    }

    private func contentsURL(configuration: CloudSyncConfiguration) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path =
            "/repos/\(configuration.githubOwner)/\(configuration.githubRepository)/contents/\(configuration.snapshotPath)"
        components.queryItems = [URLQueryItem(name: "ref", value: configuration.githubBranch)]
        guard let url = components.url else { throw CloudSyncError.invalidResponse }
        return url
    }

    private func apiURL(path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        guard let url = components.url else { throw CloudSyncError.invalidResponse }
        return url
    }

    private func request(
        url: URL,
        token: String,
        accept: String = "application/vnd.github+json"
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }
}
