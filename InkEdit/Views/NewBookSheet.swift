import SwiftUI

struct NewBookSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""

    let onCreate: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("创建书籍")
                    .font(InkTheme.editorial(27))
                Text("正文会保存在你接下来选择的文件夹中。")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("书名", text: $title)
                    .accessibilityIdentifier("book-title-field")
                TextField("作者", text: $author)
                    .accessibilityIdentifier("book-author-field")
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("选择位置并创建") {
                    onCreate(title, author)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("confirm-create-book-button")
            }
        }
        .padding(24)
        .frame(width: 440)
        .inkPanel()
    }
}
