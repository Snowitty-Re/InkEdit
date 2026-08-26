import AppKit
import SwiftUI
import Testing

@testable import InkEdit

@MainActor
struct MarkdownTextEditorTests {
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
