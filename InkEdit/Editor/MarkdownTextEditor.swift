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
        let textLength = (textView.string as NSString).length
        let location = min(selection.location, textLength)
        let length = min(selection.length, max(0, textLength - location))
        textView.setSelectedRange(NSRange(location: location, length: length))
        context.coordinator.highlight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        private let highlighter = MarkdownSyntaxHighlighter()
        private var isApplyingHighlight = false
        private var activeLineLocation: Int?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingHighlight else { return }
            text = textView.string
            highlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, let storage = textView.textStorage, !textView.hasMarkedText(), !isApplyingHighlight
            else { return }
            let selection = textView.selectedRange()
            let lineLocation = activeLine(for: selection, in: storage.string).location
            guard lineLocation != activeLineLocation else { return }

            isApplyingHighlight = true
            highlighter.updateMarkerVisibility(in: storage, selectedRange: selection)
            activeLineLocation = lineLocation
            isApplyingHighlight = false
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage, !textView.hasMarkedText(), !isApplyingHighlight
            else {
                return
            }
            isApplyingHighlight = true
            let selection = textView.selectedRange()
            highlighter.apply(to: storage, selectedRange: selection)
            activeLineLocation = activeLine(for: selection, in: storage.string).location
            isApplyingHighlight = false
        }

        private func activeLine(for selection: NSRange, in source: String) -> NSRange {
            let string = source as NSString
            guard string.length > 0 else { return NSRange(location: 0, length: 0) }
            let location = min(selection.location, string.length - 1)
            return string.lineRange(for: NSRange(location: location, length: 0))
        }
    }
}
