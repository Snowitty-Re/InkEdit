import Foundation

enum BookAccessError: LocalizedError {
    case bookmarkUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .bookmarkUnavailable:
            String(localized: "无法恢复书籍位置，请重新选择项目文件夹。")
        case .permissionDenied:
            String(localized: "InkEdit 没有访问这个项目文件夹的权限。")
        }
    }
}

struct ScopedBookAccess {
    let url: URL
    private let shouldStopAccessing: Bool

    init(url: URL, shouldStopAccessing: Bool) {
        self.url = url
        self.shouldStopAccessing = shouldStopAccessing
    }

    func stop() {
        if shouldStopAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum BookAccessController {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
    }

    static func resolve(_ bookmark: Data) throws -> ScopedBookAccess {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else {
            throw BookAccessError.bookmarkUnavailable
        }
        let started = url.startAccessingSecurityScopedResource()
        guard started else {
            throw BookAccessError.permissionDenied
        }
        return ScopedBookAccess(url: url, shouldStopAccessing: true)
    }
}
