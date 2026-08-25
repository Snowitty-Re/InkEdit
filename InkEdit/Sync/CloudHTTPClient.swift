import Foundation

protocol CloudHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionCloudHTTPClient: CloudHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudSyncError.invalidResponse }
        return (data, response)
    }
}

struct RemoteCloudSnapshot: Sendable {
    var data: Data
    var revision: String
    var identifier: String
}

struct RemoteUploadResult: Sendable {
    var revision: String
    var identifier: String
}

enum CloudSyncError: LocalizedError, Equatable {
    case invalidResponse
    case unauthorized
    case requestFailed(Int, String)
    case repositoryMustBePrivate
    case remoteChanged
    case noRemoteSnapshot
    case missingCredential
    case invalidConfiguration(String)
    case snapshotTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "云端返回了无法识别的响应。"
        case .unauthorized: "云端凭据无效或已过期，请重新连接。"
        case .requestFailed(let status, let message): "云端请求失败（\(status)）：\(message)"
        case .repositoryMustBePrivate: "为保护书稿，InkEdit 只允许同步到 GitHub 私有仓库。"
        case .remoteChanged: "云端版本已变化，请先拉取并处理冲突后再上传。"
        case .noRemoteSnapshot: "云端还没有这本书的快照。"
        case .missingCredential: "请先填写并保存云端访问凭据。"
        case .invalidConfiguration(let message): message
        case .snapshotTooLarge: "项目快照超过 GitHub Contents API 的 100 MB 限制。"
        }
    }
}

extension CloudHTTPClient {
    func requireSuccess(_ response: HTTPURLResponse, data: Data, accepted: Range<Int> = 200..<300) throws {
        guard accepted.contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 { throw CloudSyncError.unauthorized }
            let body =
                String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw CloudSyncError.requestFailed(response.statusCode, String(body.prefix(400)))
        }
    }
}
