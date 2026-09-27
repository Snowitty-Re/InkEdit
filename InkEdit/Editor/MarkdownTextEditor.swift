import AppKit
import SwiftUI

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onActivity: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onActivity: onActivity)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ActivityTextView(frame: .zero)
        textView.onActivity = { [weak coordinator = context.coordinator] isBusy in
            coordinator?.onActivity(isBusy)
        }
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
        textView.backgroundColor = InkTheme.paperColor
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.highlight()

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = InkTheme.paperColor
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onActivity = onActivity
        context.coordinator.synchronize(text: $text)
    }

    /// Native input methods and mouse tracking may run without publishing any text changes.
    /// Keep autosave suspended until the entire interaction (including composition) ends.
    @MainActor
    final class ActivityTextView: NSTextView {
        var onActivity: (Bool) -> Void = { _ in }
        private var interactionDepth = 0

        func reportActivity() {
            onActivity(interactionDepth > 0 || hasMarkedText())
        }

        private func beginInteraction() {
            interactionDepth += 1
            reportActivity()
        }

        private func endInteraction() {
            interactionDepth -= 1
            reportActivity()
        }

        override func keyDown(with event: NSEvent) {
            beginInteraction()
            defer { endInteraction() }
            super.keyDown(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            beginInteraction()
            defer { endInteraction() }
            super.mouseDown(with: event)
        }

        override func scrollWheel(with event: NSEvent) {
            beginInteraction()
            defer { endInteraction() }
            super.scrollWheel(with: event)
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            beginInteraction()
            defer { endInteraction() }
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }

        override func insertText(_ string: Any, replacementRange: NSRange) {
            beginInteraction()
            defer { endInteraction() }
            super.insertText(string, replacementRange: replacementRange)
        }

        override func unmarkText() {
            beginInteraction()
            defer { endInteraction() }
            super.unmarkText()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        var onActivity: (Bool) -> Void
        private let highlighter = MarkdownSyntaxHighlighter()
        private var isApplyingHighlight = false
        private var isApplyingModelText = false
        private var activeLineLocation: Int?

        init(text: Binding<String>, onActivity: @escaping (Bool) -> Void = { _ in }) {
            _text = text
            self.onActivity = onActivity
        }

        func synchronize(text: Binding<String>) {
            _text = text
            // SwiftUI also updates this view when the autosave status changes. The input
            // method owns marked text until it commits; assigning string here discards it.
            guard let textView, !textView.hasMarkedText(), textView.string != text.wrappedValue else { return }
            isApplyingModelText = true
            defer { isApplyingModelText = false }
            let selection = textView.selectedRange()
            textView.string = text.wrappedValue
            let textLength = (textView.string as NSString).length
            let location = min(selection.location, textLength)
            let length = min(selection.length, textLength - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            highlight()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingHighlight, !isApplyingModelText else { return }
            reportActivity()
            guard !textView.hasMarkedText() else { return }
            text = textView.string
            highlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, let storage = textView.textStorage, !isApplyingHighlight, !isApplyingModelText
            else { return }
            reportActivity()
            guard !textView.hasMarkedText() else { return }
            let selection = textView.selectedRange()
            let lineLocation = activeLine(for: selection, in: storage.string).location
            guard lineLocation != activeLineLocation else { return }

            isApplyingHighlight = true
            highlighter.updateMarkerVisibility(in: storage, selectedRange: selection)
            activeLineLocation = lineLocation
            isApplyingHighlight = false
        }

        private func reportActivity() {
            if let textView = textView as? ActivityTextView {
                textView.reportActivity()
            } else if let textView {
                onActivity(textView.hasMarkedText())
            }
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
