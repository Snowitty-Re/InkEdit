import Foundation

struct WritingStatistics: Equatable, Sendable {
    let characterCount: Int
    let wordCount: Int
    let estimatedReadingMinutes: Int

    init(markdown: String) {
        let scalars = markdown.unicodeScalars
        characterCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count

        let latinWords = markdown.split { character in
            character.isWhitespace || character.isPunctuation || character.isSymbol
        }.filter { token in
            token.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
        }.count
        let cjkCharacters = scalars.filter(\.isCJKUnifiedIdeograph).count
        wordCount = latinWords + cjkCharacters
        estimatedReadingMinutes = max(1, Int(ceil(Double(max(characterCount, 1)) / 500.0)))
    }
}

extension Unicode.Scalar {
    fileprivate var isCJKUnifiedIdeograph: Bool {
        switch value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            true
        default:
            false
        }
    }
}
