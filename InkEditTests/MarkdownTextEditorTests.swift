import AppKit
import SwiftUI
import Testing

@testable import InkEdit

@MainActor
struct MarkdownTextEditorTests {
    @Test func autosaveDuringCompositionPreservesMarkedTextAndSavesOnlyCommittedText() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = BookRepository()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let project = try repository.createBook(title: "输入法回归", author: "", in: parent)
        let model = BookWorkspaceModel(project: project)
        model.start()
        let binding = Binding(get: { model.chapterText }, set: { model.updateText($0) })
        let coordinator = MarkdownTextEditor.Coordinator(text: binding)
        let textView = NSTextView()
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.string = "已经确认"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.setMarkedText(
            "zhongwen", selectedRange: NSRange(location: 8, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        let selection = textView.selectedRange()

        // The save scheduled before composition completes and refreshes SwiftUI.
        try await waitForAutosave(model)
        coordinator.synchronize(text: binding)

        #expect(textView.hasMarkedText())
        #expect(textView.string == "已经确认zhongwen")
        #expect(textView.selectedRange() == selection)
        #expect(model.chapterText == "已经确认")
        let chapter = try #require(project.metadata.chapters.first)
        #expect(try repository.readChapter(chapter, in: project.rootURL) == "已经确认")

        textView.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!textView.hasMarkedText())
        #expect(model.chapterText == "已经确认中文")
        try await waitForAutosave(model)
        #expect(try repository.readChapter(chapter, in: project.rootURL) == "已经确认中文")
    }

    @Test func endingCompositionPublishesTheCommittedText() {
        var source = "正文"
        let binding = Binding(get: { source }, set: { source = $0 })
        let coordinator = MarkdownTextEditor.Coordinator(text: binding)
        let textView = NSTextView()
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.string = source
        textView.setMarkedText(
            "拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 2, length: 0))
        #expect(source == "正文")
        textView.unmarkText()
        #expect(source == "正文拼音")
    }

    private func waitForAutosave(_ model: BookWorkspaceModel) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if case .saved = model.saveState { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Autosave did not complete: \(model.saveState)")
    }

    @Test func changingSelectionPreservesRangeAndDocumentLayout() {
        var source = "**第一段**\n\n普通段落\n\n**第二段**"
        let binding = Binding(
            get: { source },
            set: { source = $0 }
        )
        let coordinator = MarkdownTextEditor.Coordinator(text: binding)
        let textView = NSTextView()
        textView.string = source
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.highlight()

        let expectedSelection = NSRange(location: 17, length: 3)
        let before = textView.attributedString().size()
        textView.setSelectedRange(expectedSelection)
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )

        #expect(textView.selectedRange() == expectedSelection)
        #expect(textView.attributedString().size() == before)
    }
}
