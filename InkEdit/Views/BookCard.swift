import SwiftUI

struct BookCard: View {
    let book: LibraryBook
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryBookCover(book: book)
                .frame(width: 138)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 8)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? InkTheme.sage.opacity(0.07) : .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(isSelected ? InkTheme.sage.opacity(0.5) : .clear, lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(InkTheme.line)
                        .frame(height: 3).padding(.horizontal, 3).offset(y: 5)
                        .shadow(color: .black.opacity(0.09), radius: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(book.title).font(InkTheme.editorial(19)).lineLimit(1)
                    if book.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(InkTheme.sage)
                    }
                }
                Text(book.author.isEmpty ? "未设置作者" : book.author)
                    .font(.caption).foregroundStyle(InkTheme.muted).lineLimit(1)
            }.padding(.horizontal, 18)
        }
        .foregroundStyle(InkTheme.ink).contentShape(Rectangle())
    }
}
