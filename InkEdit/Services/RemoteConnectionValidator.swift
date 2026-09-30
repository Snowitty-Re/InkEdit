import Foundation

/// Explicit, read-only probes. Never upload test files or treat saved credentials as verified.
struct RemoteConnectionValidator {
    let client: any CloudHTTPClient
    init(client: any CloudHTTPClient = URLSessionCloudHTTPClient()) { self.client = client }

    func validate(configuration: CloudSyncConfiguration, token: String) async throws -> String {
        let config = try configuration.normalized()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudSyncError.missingCredential
        }
        switch config.provider {
        case .github:
            struct Repository: Decodable { let `private`: Bool }
            let base = "https://api.github.com/repos/\(config.githubOwner)/\(config.githubRepository)"
            let repo: Repository = try await get(base, token: token)
            guard repo.private else { throw CloudSyncError.repositoryMustBePrivate }
            var components = URLComponents(string: base + "/branches")!
            components.path += "/" + config.githubBranch
            // A branch is one path parameter, including any slash in its name.
            components.percentEncodedPath =
                "/repos/\(config.githubOwner)/\(config.githubRepository)/branches/"
                + (config.githubBranch.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            struct Branch: Decodable { let name: String }
            let _: Branch = try await get(components.url!.absoluteString, token: token)
            return "私有仓库和分支可读取；未上传文件，实际写入权限将在上传时检查。"
        case .googleDrive:
            struct About: Decodable {
                struct User: Decodable { let displayName: String? }
                let user: User
            }
            let _: About = try await get(
                "https://www.googleapis.com/drive/v3/about?fields=user(displayName)", token: token)
            if let folder = config.googleDriveFolderID, folder != "root" {
                struct Folder: Decodable {
                    struct Capabilities: Decodable { let canAddChildren: Bool? }
                    let mimeType: String
                    let trashed: Bool?
                    let capabilities: Capabilities?
                }
                let result: Folder = try await get(
                    "https://www.googleapis.com/drive/v3/files/\(folder)?fields=mimeType,trashed,capabilities(canAddChildren)",
                    token: token)
                guard result.mimeType == "application/vnd.google-apps.folder", result.trashed != true,
                    result.capabilities?.canAddChildren == true
                else { throw CloudSyncError.invalidConfiguration("所选位置不是可写入的 Drive 文件夹。") }
            }
            return "Google Drive 可访问；未创建或上传任何文件。"
        }
    }

    private func get<T: Decodable>(_ address: String, token: String) async throws -> T {
        guard let url = URL(string: address) else { throw CloudSyncError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if url.host == "api.github.com" { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
        let (data, response) = try await client.data(for: request)
        // Do not echo arbitrary remote response bodies into credential forms.
        guard (200..<300).contains(response.statusCode) else {
            if [401, 403].contains(response.statusCode) { throw CloudSyncError.unauthorized }
            throw CloudSyncError.requestFailed(response.statusCode, "请检查目标位置、访问权限与网络连接。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
