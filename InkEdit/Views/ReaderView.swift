import SwiftUI

struct ReaderView: View {
    let markdown: String
    let chapterTitle: String
    let rootURL: URL
    let annotations: [BookAnnotation]
    let onSelection: (ReaderSelection) -> Void

    @Binding var theme: ReaderTheme

    private var html: String {
        MarkdownHTMLRenderer().render(
            markdown: markdown,
            title: chapterTitle,
            theme: theme,
            annotations: annotations
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ReaderWebView(html: html, baseURL: rootURL, onSelection: onSelection)
            Picker("阅读主题", selection: $theme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .padding(16)
        }
    }
}
