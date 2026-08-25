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
        #expect(inactiveMarkerFont?.pointSize == 0.1)
    }

    @Test func revealsMarkersOnActiveLine() {
        let storage = NSTextStorage(string: "普通段落\n\n**重点**")

        MarkdownSyntaxHighlighter().apply(to: storage, selectedRange: NSRange(location: 8, length: 0))

        let markerFont = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        #expect(markerFont?.pointSize == 14)
    }
}
