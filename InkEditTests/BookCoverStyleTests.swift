import AppKit
import Foundation
import Testing

@testable import InkEdit

struct BookCoverStyleTests {
    @Test func defaultCoverIsStableAndUsesAllArtworks() throws {
        var assets: Set<String> = []
        for index in 0..<6 {
            let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
            let style = BookCoverStyle(projectID: id)
            #expect(style == BookCoverStyle(projectID: id))
            assets.insert(style.asset)
        }
        #expect(assets == ["CoverMoon", "CoverCoast", "CoverBlossom"])
    }

    @Test @MainActor func bundledArtworkAndIconAreAvailable() {
        for name in ["InkMark", "CoverMoon", "CoverCoast", "CoverBlossom"] {
            #expect(NSImage(named: name) != nil)
        }
    }
}
