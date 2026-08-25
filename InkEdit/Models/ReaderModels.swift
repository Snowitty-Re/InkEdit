import Foundation

enum ReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case light
    case sepia
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .light: String(localized: "明亮")
        case .sepia: String(localized: "纸张")
        case .dark: String(localized: "深色")
        }
    }
}

struct ReaderSelection: Equatable, Sendable {
    var selectedText: String
    var prefix: String
    var suffix: String
}
