import Foundation
import Testing

@testable import InkEdit

struct ProjectSnapshotTests {
    @Test(arguments: [false, true])
    func preservesLocalEditsOrDeletionWhenRemoteIsUnchanged(deleted: Bool) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = ProjectSnapshotEntry(path: "第一章.md", data: Data("旧稿".utf8))
        let file = root.appendingPathComponent(base.path)
        if !deleted { try Data("尚未上传的本地新稿".utf8).write(to: file) }

        let result = try ProjectSnapshotStore().merge(
            remote: ProjectSnapshot(entries: [base]), into: root, baseHashes: [base.path: base.digest])

        #expect(result.changedFileCount == 0)
        #expect(result.conflictFileCount == 0)
        if deleted {
            #expect(!FileManager.default.fileExists(atPath: file.path))
        } else {
            #expect(try String(contentsOf: file, encoding: .utf8) == "尚未上传的本地新稿")
        }
    }

    @Test func preservesLocalDeletionAsConflictWhenRemoteChanged() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = ProjectSnapshotEntry(path: "第一章.md", data: Data("旧稿".utf8))
        let remote = ProjectSnapshotEntry(path: base.path, data: Data("云端新稿".utf8))

        let result = try ProjectSnapshotStore().merge(
            remote: ProjectSnapshot(entries: [remote]), into: root, baseHashes: [base.path: base.digest])

        #expect(result.changedFileCount == 0)
        #expect(result.conflictFileCount == 1)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(base.path).path))
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let conflict = try #require(files.first { $0.lastPathComponent.contains("云端冲突") })
        #expect(try Data(contentsOf: conflict) == remote.data)
    }

    @Test func identicalChangesDoNotCreateConflicts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = ProjectSnapshotEntry(path: "第一章.md", data: Data("同一份新稿".utf8))
        try entry.data.write(to: root.appendingPathComponent(entry.path))
        let result = try ProjectSnapshotStore().merge(
            remote: ProjectSnapshot(entries: [entry]), into: root, baseHashes: [entry.path: "old"])
        #expect(result.changedFileCount == 0)
        #expect(result.conflictFileCount == 0)
    }

    @Test func capturesPortableProjectFilesButExcludesLocalSyncState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".inkedit"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try Data("正文".utf8).write(to: root.appendingPathComponent("第一章.md"))
        try Data("{}".utf8).write(to: root.appendingPathComponent(".inkedit/project.json"))
        try Data("local".utf8).write(to: root.appendingPathComponent(ProjectSnapshotStore.syncStateRelativePath))
        try Data("git".utf8).write(to: root.appendingPathComponent(".git/config"))

        let snapshot = try ProjectSnapshotStore().capture(rootURL: root)

        #expect(snapshot.entries.map(\.path) == [".inkedit/project.json", "第一章.md"])
    }

    @Test func appliesRemoteChangeWhenLocalFileMatchesBase() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("第一章.md")
        let base = ProjectSnapshotEntry(path: "第一章.md", data: Data("旧稿".utf8))
        try base.data.write(to: file)
        let remote = ProjectSnapshot(entries: [ProjectSnapshotEntry(path: "第一章.md", data: Data("云端新稿".utf8))])

        let result = try ProjectSnapshotStore().merge(
            remote: remote,
            into: root,
            baseHashes: [base.path: base.digest]
        )

        #expect(try String(contentsOf: file, encoding: .utf8) == "云端新稿")
        #expect(result.changedFileCount == 1)
        #expect(result.conflictFileCount == 0)
    }

    @Test func preservesBothVersionsWhenLocalAndRemoteChanged() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("第一章.md")
        let base = ProjectSnapshotEntry(path: "第一章.md", data: Data("旧稿".utf8))
        try Data("本地新稿".utf8).write(to: file)
        let remote = ProjectSnapshot(entries: [ProjectSnapshotEntry(path: "第一章.md", data: Data("云端新稿".utf8))])

        let result = try ProjectSnapshotStore().merge(
            remote: remote,
            into: root,
            baseHashes: [base.path: base.digest],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let conflict = try #require(files.first { $0.lastPathComponent.contains("云端冲突") })

        #expect(try String(contentsOf: file, encoding: .utf8) == "本地新稿")
        #expect(try String(contentsOf: conflict, encoding: .utf8) == "云端新稿")
        #expect(result.changedFileCount == 0)
        #expect(result.conflictFileCount == 1)
    }

    @Test func refusesSnapshotEntriesForGitAndLocalCredentials() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = ProjectSnapshot(entries: [
            ProjectSnapshotEntry(path: ".git/config", data: Data("malicious".utf8)),
            ProjectSnapshotEntry(path: ProjectSnapshotStore.syncStateRelativePath, data: Data("token".utf8)),
            ProjectSnapshotEntry(path: "新章节.md", data: Data("正文".utf8)),
        ])

        let result = try ProjectSnapshotStore().merge(remote: remote, into: root, baseHashes: [:])

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/config").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(ProjectSnapshotStore.syncStateRelativePath).path))
        #expect(try String(contentsOf: root.appendingPathComponent("新章节.md"), encoding: .utf8) == "正文")
        #expect(result.changedFileCount == 1)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
