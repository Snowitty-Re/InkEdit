import SwiftUI

struct LibraryDetailView: View {
    let book: LibraryBook
    let previewRevision: Int
    let onOpen: (WorkspaceLaunchAction) -> Void
    let onDetails: () -> Void
    let onReveal: () -> Void
    let onFavorite: () -> Void
    @State private var preview: LibraryPreview?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("作品一览").font(.caption).foregroundStyle(InkTheme.muted)
                    Spacer()
                    Button(action: onFavorite) {
                        Image(systemName: book.isFavorite ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain).foregroundStyle(InkTheme.sage)
                    .help(book.isFavorite ? "取消收藏" : "收藏作品")
                    .accessibilityIdentifier("library-favorite-button")
                }
                LibraryBookCover(book: book).frame(width: 142).frame(maxWidth: .infinity).padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 7) {
                    Text(book.title).font(InkTheme.editorial(25)).fixedSize(horizontal: false, vertical: true)
                    Text(book.author.isEmpty ? "未设置作者" : book.author)
                        .font(.callout).foregroundStyle(InkTheme.muted)
                }
                if let preview {
                    Text(preview.summary.isEmpty ? "为故事写一段简介，让灵感有迹可循。" : preview.summary)
                        .font(.callout).lineSpacing(5).foregroundStyle(InkTheme.muted).lineLimit(5)
                    HStack(spacing: 0) {
                        statistic("\(preview.chapterCount)", label: "章节")
                        Divider().frame(height: 30)
                        statistic(preview.wordCount.formatted(), label: "字词")
                    }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(InkTheme.muted)
                } else {
                    ProgressView("读取作品信息…").controlSize(.small)
                }
                Button {
                    onOpen(.write)
                } label: {
                    Label("进入写作", systemImage: "square.and.pencil").frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("library-open-book")
                VStack(spacing: 0) {
                    action("阅读作品", icon: "book.pages", id: "library-read-book") { onOpen(.read) }
                    action("作品信息", icon: "slider.horizontal.3", id: "library-book-details", action: onDetails)
                    action("导出作品", icon: "square.and.arrow.up", id: "library-export-book") { onOpen(.export) }
                    action("云端同步", icon: "arrow.triangle.2.circlepath.icloud", id: "library-sync-book") {
                        onOpen(.cloud)
                    }
                }
                Rectangle().fill(InkTheme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近打开").font(.caption2)
                    Text(book.lastOpenedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Button("在 Finder 中显示", action: onReveal).buttonStyle(.link).font(.caption)
                }.foregroundStyle(InkTheme.muted)
            }.padding(20)
        }
        .scrollIndicators(.hidden)
        .background(InkTheme.paper)
        .task(id: "\(book.id)-\(previewRevision)") {
            preview = nil
            error = nil
            do {
                let result = try await LibraryPreviewService().load(bookmark: book.rootBookmark)
                guard !Task.isCancelled else { return }
                preview = result
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func statistic(_ value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 20, design: .serif)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(InkTheme.muted)
        }.frame(maxWidth: .infinity)
    }

    private func action(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(InkTheme.muted)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
