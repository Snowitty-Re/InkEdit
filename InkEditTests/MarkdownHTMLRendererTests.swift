import Testing

@testable import InkEdit

struct MarkdownHTMLRendererTests {
    @Test func rendersReadableChineseMarkdownAndEscapesRawHTML() {
        let html = MarkdownHTMLRenderer().render(
            markdown: "# 第一章\n\n这是 **重要** 的故事。\n\n<script>alert('x')</script>",
            title: "长夜",
            theme: .sepia,
            annotations: []
        )

        #expect(html.contains("<h1>第一章</h1>"))
        #expect(html.contains("<strong>重要</strong>"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>alert"))
    }

    @Test func distinguishesImagesFromLinks() {
        let html = MarkdownHTMLRenderer().render(
            markdown: "![封面](images/cover.png) [资料](https://example.com)",
            title: "测试",
            theme: .light,
            annotations: []
        )

        #expect(html.contains(#"<img src="images/cover.png" alt="封面" />"#))
        #expect(html.contains(#"<a href="https://example.com">资料</a>"#))
        #expect(!html.contains("!<a"))
    }

    @Test func escapesQuotesInsideGeneratedAttributes() {
        let html = MarkdownHTMLRenderer().render(
            markdown: #"[危险](" onclick="alert(1))"#,
            title: #"书名"测试"#,
            theme: .dark,
            annotations: []
        )

        #expect(html.contains("&quot;"))
        #expect(!html.contains(#"onclick="alert"#))
    }
}
