import AppKit

@MainActor
final class MarkdownSyntaxHighlighter {
    private let headingExpression = try! NSRegularExpression(
        pattern: "^(#{1,6})[ \\t]+(.+)$", options: [.anchorsMatchLines])
    private let quoteExpression = try! NSRegularExpression(
        pattern: "^[ \\t]*(>+)[ \\t]?", options: [.anchorsMatchLines])
    private let listExpression = try! NSRegularExpression(
        pattern: "^[ \\t]*(?:[-+*]|[0-9]+[.)])[ \\t]+",
        options: [.anchorsMatchLines]
    )
    private let boldExpression = try! NSRegularExpression(pattern: "(?:\\*\\*|__)(.+?)(?:\\*\\*|__)")
    private let italicExpression = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)")
    private let codeExpression = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private let linkExpression = try! NSRegularExpression(pattern: "!?\\[([^]\\n]+)\\]\\(([^)\\n]+)\\)")

    func apply(to storage: NSTextStorage, selectedRange: NSRange) {
        let source = storage.string as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let activeLine = source.lineRange(for: clampedSelection(selectedRange, length: source.length))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 7
        paragraphStyle.paragraphSpacing = 9

        storage.beginEditing()
        storage.setAttributes(
            [
                .font: bodyFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ],
            range: fullRange
        )

        applyHeadings(to: storage, source: source, fullRange: fullRange, activeLine: activeLine)
        applyQuotes(to: storage, source: source, fullRange: fullRange, activeLine: activeLine)
        applyLists(to: storage, source: source, fullRange: fullRange, activeLine: activeLine)
        applyBold(to: storage, fullRange: fullRange, activeLine: activeLine)
        applyItalic(to: storage, fullRange: fullRange, activeLine: activeLine)
        applyInlineCode(to: storage, fullRange: fullRange, activeLine: activeLine)
        applyLinks(to: storage, fullRange: fullRange, activeLine: activeLine)
        storage.endEditing()
    }

    private var bodyFont: NSFont {
        NSFont(name: "Songti SC", size: 18) ?? .systemFont(ofSize: 18)
    }

    private func applyHeadings(
        to storage: NSTextStorage,
        source: NSString,
        fullRange: NSRange,
        activeLine: NSRange
    ) {
        headingExpression.enumerateMatches(in: source as String, range: fullRange) { result, _, _ in
            guard let result else { return }
            let level = max(1, min(result.range(at: 1).length, 6))
            let size: CGFloat = [30, 26, 23, 21, 19, 18][level - 1]
            let font = NSFont(name: "Songti SC Bold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
            storage.addAttribute(.font, value: font, range: result.range)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: result.range)
            styleMarker(result.range(at: 1), in: storage, activeLine: activeLine)
        }
    }

    private func applyQuotes(
        to storage: NSTextStorage,
        source: NSString,
        fullRange: NSRange,
        activeLine: NSRange
    ) {
        quoteExpression.enumerateMatches(in: source as String, range: fullRange) { result, _, _ in
            guard let result else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: result.range)
            styleMarker(result.range(at: 1), in: storage, activeLine: activeLine)
        }
    }

    private func applyLists(
        to storage: NSTextStorage,
        source: NSString,
        fullRange: NSRange,
        activeLine: NSRange
    ) {
        listExpression.enumerateMatches(in: source as String, range: fullRange) { result, _, _ in
            guard let result else { return }
            styleMarker(result.range, in: storage, activeLine: activeLine)
        }
    }

    private func applyBold(to storage: NSTextStorage, fullRange: NSRange, activeLine: NSRange) {
        boldExpression.enumerateMatches(in: storage.string, range: fullRange) { result, _, _ in
            guard let result, result.range.length >= 4 else { return }
            let contentRange = result.range(at: 1)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask),
                range: contentRange
            )
            stylePairedMarkers(matchRange: result.range, markerLength: 2, in: storage, activeLine: activeLine)
        }
    }

    private func applyItalic(to storage: NSTextStorage, fullRange: NSRange, activeLine: NSRange) {
        italicExpression.enumerateMatches(in: storage.string, range: fullRange) { result, _, _ in
            guard let result, result.range.length >= 2 else { return }
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask),
                range: result.range(at: 1)
            )
            stylePairedMarkers(matchRange: result.range, markerLength: 1, in: storage, activeLine: activeLine)
        }
    }

    private func applyInlineCode(to storage: NSTextStorage, fullRange: NSRange, activeLine: NSRange) {
        codeExpression.enumerateMatches(in: storage.string, range: fullRange) { result, _, _ in
            guard let result else { return }
            storage.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.14),
                ],
                range: result.range(at: 1)
            )
            stylePairedMarkers(matchRange: result.range, markerLength: 1, in: storage, activeLine: activeLine)
        }
    }

    private func applyLinks(to storage: NSTextStorage, fullRange: NSRange, activeLine: NSRange) {
        linkExpression.enumerateMatches(in: storage.string, range: fullRange) { result, _, _ in
            guard let result else { return }
            let labelRange = result.range(at: 1)
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: labelRange
            )
            guard NSIntersectionRange(result.range, activeLine).length == 0 else {
                let leadingLength = labelRange.location - result.range.location
                styleMarker(
                    NSRange(location: result.range.location, length: leadingLength),
                    in: storage,
                    activeLine: activeLine
                )
                let trailingLocation = NSMaxRange(labelRange)
                styleMarker(
                    NSRange(location: trailingLocation, length: NSMaxRange(result.range) - trailingLocation),
                    in: storage,
                    activeLine: activeLine
                )
                return
            }
        }
    }

    private func stylePairedMarkers(
        matchRange: NSRange,
        markerLength: Int,
        in storage: NSTextStorage,
        activeLine: NSRange
    ) {
        styleMarker(NSRange(location: matchRange.location, length: markerLength), in: storage, activeLine: activeLine)
        styleMarker(
            NSRange(location: NSMaxRange(matchRange) - markerLength, length: markerLength),
            in: storage,
            activeLine: activeLine
        )
    }

    private func styleMarker(_ range: NSRange, in storage: NSTextStorage, activeLine: NSRange) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        if NSIntersectionRange(range, activeLine).length == 0 {
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1),
                ],
                range: range
            )
        } else {
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                ],
                range: range
            )
        }
    }

    private func clampedSelection(_ range: NSRange, length: Int) -> NSRange {
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        return NSRange(location: min(range.location, length - 1), length: 0)
    }
}
