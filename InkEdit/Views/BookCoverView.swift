import AppKit
import SwiftUI

enum BookCoverStyle: Int, CaseIterable {
    case moon, coast, blossom
    init(projectID: UUID) {
        let sum = projectID.uuidString.utf8.reduce(0) { $0 + Int($1) }
        self = Self.allCases[sum % Self.allCases.count]
    }
    var asset: String {
        switch self {
        case .moon: "CoverMoon"
        case .coast: "CoverCoast"
        case .blossom: "CoverBlossom"
        }
    }
    var lettering: Color {
        self == .moon ? Color(red: 0.96, green: 0.95, blue: 0.87) : Color(red: 0.23, green: 0.31, blue: 0.27)
    }
}

/// Default art is presentation only, never persisted to a project or exported as its cover.
struct BookCoverView: View {
    let title: String
    let author: String
    let projectID: UUID
    var customImage: NSImage?

    private var style: BookCoverStyle { BookCoverStyle(projectID: projectID) }
    private var isVerticalTitle: Bool {
        !title.isEmpty && title.count <= 12
            && title.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
    }

    var body: some View {
        Color.clear.aspectRatio(0.70, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .topTrailing) {
                        if let customImage {
                            Image(nsImage: customImage).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        } else {
                            Image(style.asset).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            VStack(alignment: .trailing, spacing: geometry.size.width * 0.07) {
                                Text(isVerticalTitle ? title.map(String.init).joined(separator: "\n") : title)
                                    .font(InkTheme.editorial(geometry.size.width * (isVerticalTitle ? 0.135 : 0.15)))
                                    .lineSpacing(2)
                                    .multilineTextAlignment(isVerticalTitle ? .center : .trailing)
                                    .lineLimit(isVerticalTitle ? 12 : 5)
                                    .minimumScaleFactor(0.6)
                                if !author.isEmpty {
                                    Text(author).font(.system(size: max(9, geometry.size.width * 0.055)))
                                        .lineLimit(2)
                                }
                            }
                            .foregroundStyle(style.lettering)
                            .shadow(color: style == .moon ? .black.opacity(0.65) : .clear, radius: 1, y: 1)
                            .padding(geometry.size.width * 0.13)
                        }
                    }
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [.black.opacity(0.16), .white.opacity(0.18), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.07)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 9, x: 4, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(author.isEmpty ? "未设置作者" : author)")
    }
}

struct LibraryBookCover: View {
    let book: LibraryBook
    @State private var image: NSImage?
    var body: some View {
        BookCoverView(title: book.title, author: book.author, projectID: book.projectID, customImage: image)
            .task(id: "\(book.id)-\(book.coverRelativePath ?? "")") {
                image = nil
                guard let path = book.coverRelativePath else { return }
                let data = try? await BookDetailsService().libraryCover(bookmark: book.rootBookmark, relativePath: path)
                guard !Task.isCancelled else { return }
                image = data.flatMap(NSImage.init(data:))
            }
    }
}
