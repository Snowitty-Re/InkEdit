import Foundation
import Testing

@testable import InkEdit

struct RemoteConnectionValidatorTests {
    @Test func githubProbeIsReadOnlyAndEncodesBranchNames() async throws {
        let client = ConnectionStub([.init(200, #"{"private":true}"#), .init(200, #"{"name":"draft/next"}"#)])
        let config = CloudSyncConfiguration(
            provider: .github, githubOwner: "writer", githubRepository: "books", githubBranch: "draft/next")
        _ = try await RemoteConnectionValidator(client: client).validate(configuration: config, token: "test")
        let requests = await client.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        #expect(requests.last?.url?.absoluteString.contains("draft%2Fnext") == true)
    }

    @Test func publicRepositoriesAreRejected() async throws {
        let client = ConnectionStub([.init(200, #"{"private":false}"#)])
        let config = CloudSyncConfiguration(provider: .github, githubOwner: "writer", githubRepository: "books")
        await #expect(throws: CloudSyncError.repositoryMustBePrivate) {
            try await RemoteConnectionValidator(client: client).validate(configuration: config, token: "test")
        }
        #expect(await client.requests.count == 1)
    }

    @Test func failuresDoNotEchoRemoteBodiesOrCredentials() async throws {
        let client = ConnectionStub([.init(404, "secret-reflected-by-server")])
        do {
            _ = try await RemoteConnectionValidator(client: client).validate(
                configuration: .init(provider: .googleDrive), token: "test")
            Issue.record("Expected failure")
        } catch { #expect(!error.localizedDescription.contains("secret-reflected")) }
    }

    @Test func driveFolderProbeRequiresWritableFolder() async throws {
        var config = CloudSyncConfiguration(provider: .googleDrive)
        config.googleDriveFolderID = "folder_123"
        let client = ConnectionStub([
            .init(200, #"{"user":{"displayName":"Writer"}}"#),
            .init(
                200,
                #"{"mimeType":"application/vnd.google-apps.folder","trashed":false,"capabilities":{"canAddChildren":true}}"#
            ),
        ])
        _ = try await RemoteConnectionValidator(client: client).validate(configuration: config, token: "test")
        #expect(await client.requests.allSatisfy { $0.httpMethod == "GET" })
        let invalid = ConnectionStub([
            .init(200, #"{"user":{}}"#),
            .init(200, #"{"mimeType":"text/plain","capabilities":{"canAddChildren":false}}"#),
        ])
        await #expect(throws: CloudSyncError.self) {
            try await RemoteConnectionValidator(client: invalid).validate(configuration: config, token: "test")
        }
    }

    @Test func driveUploadUsesConfiguredParentAndSearchScope() async throws {
        let client = ConnectionStub([
            .init(200, #"{"files":[]}"#),
            .init(200, #"{"id":"backup","md5Checksum":"checksum"}"#),
        ])
        var config = CloudSyncConfiguration(provider: .googleDrive)
        config.googleDriveFolderID = "folder_123"
        _ = try await GoogleDriveSnapshotStore(client: client).upload(
            Data("manuscript".utf8), configuration: config, projectID: UUID(), projectTitle: "书稿", token: "test",
            expectedRevision: nil)
        let requests = await client.requests
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
            $0.name == "q"
        }?.value
        #expect(query?.contains("'folder_123' in parents") == true)
        let body = String(decoding: try #require(requests[1].httpBody), as: UTF8.self)
        #expect(body.contains(#""parents":["folder_123"]"#))
    }

    @Test func githubUsesPerBookPathWhileLegacyPathIsStillSupported() async throws {
        let client = ConnectionStub([.init(200, #"{"private":true}"#), .init(404, "")])
        let config = RemoteConnectionDefaults(githubOwner: "writer", githubRepository: "books")
            .configuration(for: .github, projectID: UUID())
        _ = try await GitHubSnapshotStore(client: client).download(configuration: config, token: "test")
        let requests = await client.requests
        #expect(requests.last?.url?.path.hasSuffix(config.snapshotPath) == true)
    }
}

private actor ConnectionStub: CloudHTTPClient {
    struct Response: Sendable {
        let status: Int
        let body: String
        init(_ status: Int, _ body: String) {
            self.status = status
            self.body = body
        }
    }
    private var queued: [Response]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [Response]) { queued = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !queued.isEmpty else { throw CloudSyncError.invalidResponse }
        let next = queued.removeFirst()
        return (
            Data(next.body.utf8),
            HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        )
    }
}
