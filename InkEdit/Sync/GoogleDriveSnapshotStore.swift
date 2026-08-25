import Foundation

struct GoogleDriveSnapshotStore {
    private struct DriveFile: Decodable {
        var id: String
        var name: String?
        var md5Checksum: String?
    }
    private struct FileList: Decodable { var files: [DriveFile] }

    private let client: any CloudHTTPClient

    init(client: any CloudHTTPClient = URLSessionCloudHTTPClient()) {
        self.client = client
    }

    func download(
        configuration: CloudSyncConfiguration,
        projectID: UUID,
        token: String
    ) async throws -> RemoteCloudSnapshot? {
        guard let file = try await locateFile(configuration: configuration, projectID: projectID, token: token) else {
            return nil
        }
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(file.id)")
        components?.queryItems = [URLQueryItem(name: "alt", value: "media")]
        guard let url = components?.url else { throw CloudSyncError.invalidResponse }
        let (data, response) = try await client.data(for: authorizedRequest(url: url, token: token))
        try client.requireSuccess(response, data: data)
        guard let revision = file.md5Checksum else { throw CloudSyncError.invalidResponse }
        return RemoteCloudSnapshot(data: data, revision: revision, identifier: file.id)
    }

    func upload(
        _ snapshot: Data,
        configuration: CloudSyncConfiguration,
        projectID: UUID,
        projectTitle: String,
        token: String,
        expectedRevision: String?
    ) async throws -> RemoteUploadResult {
        let current = try await locateFile(configuration: configuration, projectID: projectID, token: token)
        if let current {
            guard expectedRevision == current.md5Checksum else { throw CloudSyncError.remoteChanged }
            return try await update(snapshot, fileID: current.id, token: token)
        }
        guard expectedRevision == nil else { throw CloudSyncError.remoteChanged }
        return try await create(
            snapshot,
            projectID: projectID,
            projectTitle: projectTitle,
            token: token
        )
    }

    private func locateFile(
        configuration: CloudSyncConfiguration,
        projectID: UUID,
        token: String
    ) async throws -> DriveFile? {
        if let identifier = configuration.remoteIdentifier {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(identifier)")
            components?.queryItems = [URLQueryItem(name: "fields", value: "id,name,md5Checksum")]
            guard let url = components?.url else { throw CloudSyncError.invalidResponse }
            let (data, response) = try await client.data(for: authorizedRequest(url: url, token: token))
            if response.statusCode == 404 { return nil }
            try client.requireSuccess(response, data: data)
            return try JSONDecoder().decode(DriveFile.self, from: data)
        }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")
        components?.queryItems = [
            URLQueryItem(
                name: "q",
                value:
                    "appProperties has { key='inkeditProjectID' and value='\(projectID.uuidString)' } and trashed=false"
            ),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name,md5Checksum)"),
        ]
        guard let url = components?.url else { throw CloudSyncError.invalidResponse }
        let (data, response) = try await client.data(for: authorizedRequest(url: url, token: token))
        try client.requireSuccess(response, data: data)
        return try JSONDecoder().decode(FileList.self, from: data).files.first
    }

    private func create(
        _ snapshot: Data,
        projectID: UUID,
        projectTitle: String,
        token: String
    ) async throws -> RemoteUploadResult {
        var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files")
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id,md5Checksum"),
        ]
        guard let url = components?.url else { throw CloudSyncError.invalidResponse }
        let boundary = "InkEdit-\(UUID().uuidString)"
        let metadata: [String: Any] = [
            "name": "\(safeName(projectTitle)).inkedit.zip",
            "mimeType": "application/zip",
            "appProperties": ["inkeditProjectID": projectID.uuidString],
        ]
        var body = Data()
        body.appendUTF8("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.appendUTF8("\r\n--\(boundary)\r\nContent-Type: application/zip\r\n\r\n")
        body.append(snapshot)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try await performUpload(request)
    }

    private func update(_ snapshot: Data, fileID: String, token: String) async throws -> RemoteUploadResult {
        var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)")
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "media"),
            URLQueryItem(name: "fields", value: "id,md5Checksum"),
        ]
        guard let url = components?.url else { throw CloudSyncError.invalidResponse }
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "PATCH"
        request.httpBody = snapshot
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        return try await performUpload(request)
    }

    private func performUpload(_ request: URLRequest) async throws -> RemoteUploadResult {
        let (data, response) = try await client.data(for: request)
        try client.requireSuccess(response, data: data)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        guard let revision = file.md5Checksum else { throw CloudSyncError.invalidResponse }
        return RemoteUploadResult(revision: revision, identifier: file.id)
    }

    private func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func safeName(_ source: String) -> String {
        let name = source.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return name.isEmpty ? "InkEdit 书稿" : name
    }
}

extension Data {
    fileprivate mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
