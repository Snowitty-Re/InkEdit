import Foundation
import SwiftData

@Model
final class LibraryBook {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var title: String
    var author: String
    var rootPath: String
    var rootBookmark: Data
    var coverRelativePath: String?
    var createdAt: Date
    var lastOpenedAt: Date
    var isFavorite: Bool
    var cloudProviderRawValue: String?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        author: String,
        rootPath: String,
        rootBookmark: Data,
        coverRelativePath: String? = nil,
        createdAt: Date = .now,
        lastOpenedAt: Date = .now,
        isFavorite: Bool = false,
        cloudProviderRawValue: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.author = author
        self.rootPath = rootPath
        self.rootBookmark = rootBookmark
        self.coverRelativePath = coverRelativePath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.isFavorite = isFavorite
        self.cloudProviderRawValue = cloudProviderRawValue
    }
}
