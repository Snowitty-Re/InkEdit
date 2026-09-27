import Foundation

struct MarkdownHTMLRenderer {
    func render(
        markdown: String,
        title: String,
        theme: ReaderTheme,
        annotations: [BookAnnotation],
        interactive: Bool = true
    ) -> String {
        let body = renderBody(markdown)
        let annotationJSON = encodedAnnotations(annotations)
        let readerScript = interactive ? script(annotationJSON: annotationJSON) : ""
        return """
            <!doctype html>
            <html lang="zh-Hans">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>\(escape(title))</title>
              <style>\(styleSheet(for: theme))</style>
            </head>
            <body>
              <main id="manuscript" aria-label="\(escapeAttribute(title))">\(body)</main>
              \(readerScript)
            </body>
            </html>
            """
    }

    func renderBody(_ markdown: String) -> String {
        renderBlocks(markdown)
    }

    private func script(annotationJSON: String) -> String {
        """
        <script>
            const annotations = \(annotationJSON);
            function textNodes(root) {
              const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
              const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode); return nodes;
            }
            function applyHighlight(annotation) {
              if (!annotation.selectedText) return;
              for (const node of textNodes(document.getElementById('manuscript'))) {
                const index = node.nodeValue.indexOf(annotation.selectedText);
                if (index < 0 || node.parentElement.closest('mark')) continue;
                const range = document.createRange();
                range.setStart(node, index); range.setEnd(node, index + annotation.selectedText.length);
                const mark = document.createElement('mark'); mark.dataset.annotationId = annotation.id;
                range.surroundContents(mark); return;
              }
            }
            annotations.forEach(applyHighlight);
            document.addEventListener('mouseup', () => {
              const selection = window.getSelection(); const selectedText = selection.toString().trim();
              if (!selectedText || !selection.rangeCount) return;
              const allText = document.getElementById('manuscript').innerText;
              const index = allText.indexOf(selectedText);
              window.webkit.messageHandlers.selection.postMessage({
                selectedText,
                prefix: index >= 0 ? allText.slice(Math.max(0, index - 32), index) : '',
                suffix: index >= 0 ? allText.slice(index + selectedText.length, index + selectedText.length + 32) : ''
              });
            });
        </script>
        """
    }

    private func renderBlocks(_ markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var codeLines: [String] = []
        var isInCodeFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            html.append("<ul>\(listItems.map { "<li>\($0)</li>" }.joined())</ul>")
            listItems.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushParagraph()
                flushList()
                if isInCodeFence {
                    html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                }
                isInCodeFence.toggle()
                continue
            }
            if isInCodeFence {
                codeLines.append(rawLine)
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushList()
            } else if let heading = heading(from: line) {
                flushParagraph()
                flushList()
                html.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
            } else if line.hasPrefix(">") {
                flushParagraph()
                flushList()
                html.append(
                    "<blockquote>\(inline(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))</blockquote>")
            } else if let listText = unorderedListText(from: line) {
                flushParagraph()
                listItems.append(inline(listText))
            } else if line == "---" || line == "***" {
                flushParagraph()
                flushList()
                html.append("<hr />")
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushList()
        if isInCodeFence, !codeLines.isEmpty {
            html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
        }
        return html.joined(separator: "\n")
    }

    private func inline(_ source: String) -> String {
        var value = escape(source)
        value = replacing(#"`([^`]+)`"#, in: value, template: "<code>$1</code>")
        value = replacing(#"\*\*([^*]+)\*\*"#, in: value, template: "<strong>$1</strong>")
        value = replacing(#"__([^_]+)__"#, in: value, template: "<strong>$1</strong>")
        value = replacing(#"\*([^*]+)\*"#, in: value, template: "<em>$1</em>")
        value = replacing(#"!\[([^]]*)\]\(([^)]+)\)"#, in: value, template: #"<img src="$2" alt="$1" />"#)
        value = replacing(#"(?<!!)\[([^]]+)\]\(([^)]+)\)"#, in: value, template: #"<a href="$2">$1</a>"#)
        return value
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, String(line.dropFirst(hashes.count + 1)))
    }

    private func unorderedListText(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private func replacing(_ pattern: String, in source: String, template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private func encodedAnnotations(_ annotations: [BookAnnotation]) -> String {
        let payload = annotations.map { annotation in
            ["id": annotation.id.uuidString, "selectedText": annotation.selectedText]
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    private func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeAttribute(_ source: String) -> String {
        escape(source).replacingOccurrences(of: "\"", with: "&quot;")
    }

    func styleSheet(for theme: ReaderTheme) -> String {
        let colors =
            switch theme {
            case .light: (background: "#fbfbfa", foreground: "#20201f", secondary: "#686866", mark: "#ffe58a")
            case .sepia: (background: "#f8f5ef", foreground: "#343b34", secondary: "#71796d", mark: "#e4d99b")
            case .dark: (background: "#171716", foreground: "#e8e5df", secondary: "#aaa59c", mark: "#6f5d19")
            }
        return """
            :root { color-scheme: light dark; }
            * { box-sizing: border-box; }
            body { margin: 0; background: \(colors.background); color: \(colors.foreground); }
            main { max-width: 720px; margin: 0 auto; padding: 72px 56px 120px;
              font-family: "Songti SC", "STSong", serif; font-size: 20px; line-height: 1.95; }
            p { margin: 0 0 1.35em; text-align: justify; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.35; margin: 1.8em 0 .8em; }
            h1 { font-size: 2em; } h2 { font-size: 1.6em; } h3 { font-size: 1.3em; }
            blockquote { color: \(colors.secondary); border-left: 3px solid \(colors.secondary);
              margin: 1.5em 0; padding-left: 1.2em; }
            pre { overflow-x: auto; padding: 1em; border-radius: 8px; background: rgba(127,127,127,.12); }
            code { font-family: ui-monospace, monospace; font-size: .88em; }
            img { display: block; max-width: 100%; height: auto; margin: 1.5em auto; }
            a { color: inherit; text-decoration-thickness: 1px; }
            mark { background: \(colors.mark); color: inherit; border-radius: 2px; padding: 0 .05em; }
            """
    }
}
