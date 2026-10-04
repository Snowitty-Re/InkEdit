import AppKit
import Testing

@testable import InkEdit

@MainActor
struct WorkspaceSaveRegistryTests {
    @Test func failedChapterSaveVetoesWindowCloseUntilRetrySucceeds() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repository = BookRepository()
        let project = try repository.createBook(title: "关闭保护", author: "", in: parent)
        let model = BookWorkspaceModel(project: project)
        model.start()
        let chapter = try #require(model.selectedChapter)
        let file = try repository.safeURL(for: try #require(chapter.relativePath), in: project.rootURL)
        let backup = file.appendingPathExtension("test-backup")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        model.updateText("关闭窗口也不能丢失")
        let window = NSWindow()
        let coordinator = WorkspaceCloseGuard.Coordinator(model: model)
        coordinator.attach(to: window)
        defer { coordinator.attach(to: nil) }

        #expect(!coordinator.windowShouldClose(window))
        #expect(model.chapterText == "关闭窗口也不能丢失")
        #expect(model.errorMessage != nil)

        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: backup, to: file)
        #expect(coordinator.windowShouldClose(window))
        #expect(try repository.readChapter(chapter, in: project.rootURL) == "关闭窗口也不能丢失")
    }

    @Test func failedSaveVetoesQuitAndEveryWindowIsAttempted() {
        let registry = WorkspaceSaveRegistry()
        var attempts = 0
        let failed = registry.register {
            attempts += 1
            return false
        }
        _ = registry.register {
            attempts += 1
            return true
        }
        #expect(!registry.prepareForTermination())
        #expect(attempts == 2)
        registry.unregister(failed)
        #expect(registry.prepareForTermination())
        #expect(attempts == 3)
    }

    @Test func windowDelegateIsForwardedAndRestored() {
        let project = OpenBookProject(
            rootURL: FileManager.default.temporaryDirectory,
            metadata: BookProject(title: "窗口测试", outline: []))
        let model = BookWorkspaceModel(project: project)
        let coordinator = WorkspaceCloseGuard.Coordinator(model: model)
        let window = NSWindow()
        let original = CloseVetoDelegate()
        window.delegate = original
        coordinator.attach(to: window)
        #expect(window.delegate === coordinator)
        #expect(!coordinator.windowShouldClose(window))
        #expect(original.closeAttempts == 1)
        #expect(coordinator.responds(to: #selector(NSWindowDelegate.windowWillClose(_:))))
        #expect(
            coordinator.forwardingTarget(for: #selector(NSWindowDelegate.windowWillClose(_:))) as? CloseVetoDelegate
                === original)
        coordinator.attach(to: nil)
        #expect(window.delegate === original)
    }
}

@MainActor
private final class CloseVetoDelegate: NSObject, NSWindowDelegate {
    var closeAttempts = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeAttempts += 1
        return false
    }
    func windowWillClose(_ notification: Notification) {}
}
