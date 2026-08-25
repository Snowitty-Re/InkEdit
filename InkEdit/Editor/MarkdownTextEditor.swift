import AppKit
import SwiftUI

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 56, height: 42)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.highlight()

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
        context.coordinator.highlight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        private let highlighter = MarkdownSyntaxHighlighter()
        private var isApplyingHighlight = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingHighlight else { return }
            text = textView.string
            highlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            highlight()
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage, !textView.hasMarkedText(), !isApplyingHighlight
            else {
                return
            }
            isApplyingHighlight = true
            let selection = textView.selectedRange()
            highlighter.apply(to: storage, selectedRange: selection)
            textView.setSelectedRange(selection)
            isApplyingHighlight = false
        }
    }
}
