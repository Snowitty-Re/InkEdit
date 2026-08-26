import AppKit
import Testing

@testable import InkEdit

@MainActor
struct MarkdownSyntaxHighlighterTests {
    @Test func preservesMarkdownSourceWhileStylingContent() {
        let source = "# 标题\n\n**重点**"
        let storage = NSTextStorage(string: source)

        MarkdownSyntaxHighlighter().apply(to: storage, selectedRange: NSRange(location: 2, length: 0))

        #expect(storage.string == source)
        let headingFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect((headingFont?.pointSize ?? 0) >= 30)
        let inactiveMarkerFont = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        let inactiveMarkerColor = storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        #expect(inactiveMarkerFont?.pointSize == 14)
        #expect(inactiveMarkerColor == .clear)
    }

    @Test func revealsMarkersOnActiveLine() {
        let storage = NSTextStorage(string: "普通段落\n\n**重点**")

        MarkdownSyntaxHighlighter().apply(to: storage, selectedRange: NSRange(location: 8, length: 0))

        let markerFont = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        let markerColor = storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        #expect(markerFont?.pointSize == 14)
        #expect(markerColor == .tertiaryLabelColor)
    }

    @Test func changingActiveLineDoesNotChangeDocumentLayout() {
        let storage = NSTextStorage(string: "**第一段**\n\n普通段落\n\n**第二段**")
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.apply(to: storage, selectedRange: NSRange(location: 3, length: 0))
        let before = storage.size()
        let firstMarkerFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        highlighter.updateMarkerVisibility(in: storage, selectedRange: NSRange(location: 17, length: 0))

        let after = storage.size()
        let hiddenMarkerFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(before == after)
        #expect(firstMarkerFont?.pointSize == hiddenMarkerFont?.pointSize)
    }
}
