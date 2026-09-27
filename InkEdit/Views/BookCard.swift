import SwiftUI

struct BookCard: View {
    let book: LibraryBook
    let isSelected: Bool
    @State private var coverImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.82), Color.accentColor.opacity(0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(0.72, contentMode: .fit)
                    .shadow(color: .black.opacity(0.13), radius: 8, y: 4)

                if let coverImage {
                    GeometryReader { geometry in
                        Image(nsImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(book.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .padding(14)
                }
            }

            Text(book.title)
                .font(.headline)
                .lineLimit(1)
            Text(book.author.isEmpty ? "未设置作者" : book.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，\(book.author.isEmpty ? "未设置作者" : book.author)")
        .task(id: book.coverRelativePath) {
            coverImage = nil
            if let data = try? await BookDetailsService().libraryCover(
                bookmark: book.rootBookmark, relativePath: book.coverRelativePath), !Task.isCancelled
            {
                coverImage = NSImage(data: data)
            }
        }
    }
}
