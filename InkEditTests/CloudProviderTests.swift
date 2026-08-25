import Foundation
import Testing

@testable import InkEdit

struct CloudProviderTests {
    @Test func githubRejectsPublicRepository() async throws {
        let client = StubCloudHTTPClient(responses: [response(status: 200, json: #"{"private":false}"#)])
        let store = GitHubSnapshotStore(client: client)
        let configuration = CloudSyncConfiguration(
            provider: .github,
            githubOwner: "author",
            githubRepository: "book",
            githubBranch: "main"
        )

        do {
            _ = try await store.download(configuration: configuration, token: "token")
            Issue.record("公开仓库应被拒绝")
        } catch {
            #expect(error as? CloudSyncError == .repositoryMustBePrivate)
        }
    }

    @Test func githubDownloadsPrivateSnapshotWithRevision() async throws {
        let archive = Data("snapshot".utf8)
        let client = StubCloudHTTPClient(
            responses: [
                response(status: 200, json: #"{"private":true}"#),
                response(status: 200, json: #"{"sha":"abc123"}"#),
                response(status: 200, data: archive),
            ]
        )
        let configuration = CloudSyncConfiguration(
            provider: .github,
            githubOwner: "author",
            githubRepository: "book",
            githubBranch: "main"
        )

        let remote = try #require(
            try await GitHubSnapshotStore(client: client).download(configuration: configuration, token: "token")
        )

        #expect(remote.data == archive)
        #expect(remote.revision == "abc123")
        #expect(
            (await client.requests()).last?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
    }

    @Test func googleDriveCreatesAppScopedSnapshot() async throws {
        let client = StubCloudHTTPClient(
            responses: [
                response(status: 200, json: #"{"files":[]}"#),
                response(status: 200, json: #"{"id":"drive-id","md5Checksum":"revision"}"#),
            ]
        )
        let result = try await GoogleDriveSnapshotStore(client: client).upload(
            Data("snapshot".utf8),
            configuration: CloudSyncConfiguration(provider: .googleDrive),
            projectID: UUID(uuidString: "42F62E6A-A1F7-4C94-BF89-6CA678679683")!,
            projectTitle: "长夜",
            token: "token",
            expectedRevision: nil
        )
        let requests = await client.requests()
        let uploadBody = try #require(requests.last?.httpBody)

        #expect(result.identifier == "drive-id")
        #expect(result.revision == "revision")
        #expect(String(decoding: uploadBody, as: UTF8.self).contains("inkeditProjectID"))
        #expect(requests.last?.httpMethod == "POST")
    }

    private func response(status: Int, json: String) -> StubCloudHTTPClient.StubResponse {
        response(status: status, data: Data(json.utf8))
    }

    private func response(status: Int, data: Data) -> StubCloudHTTPClient.StubResponse {
        StubCloudHTTPClient.StubResponse(status: status, data: data)
    }
}

private actor StubCloudHTTPClient: CloudHTTPClient {
    struct StubResponse: Sendable {
        var status: Int
        var data: Data
    }

    private var queued: [StubResponse]
    private var recorded: [URLRequest] = []

    init(responses: [StubResponse]) {
        queued = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.append(request)
        let stub = queued.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (stub.data, response)
    }

    func requests() -> [URLRequest] {
        recorded
    }
}
