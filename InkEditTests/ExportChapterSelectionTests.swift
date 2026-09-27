import Foundation
import Testing

@testable import InkEdit

struct ExportChapterSelectionTests {
    private let chapters = (1...24).map {
        BookOutlineNode.chapter(title: "第\($0)章", relativePath: "第\($0)章.md")
    }

    @Test func partialDefaultsThroughCurrentChapterInclusively() {
        var selection = ExportChapterSelection(chapters: chapters, currentChapterID: chapters[19].id)
        #expect(selection.selectedChapters(in: chapters) == chapters)
        selection.scope = .partial
        #expect(selection.selectedChapters(in: chapters) == Array(chapters.prefix(20)))
    }

    @Test func customRangeAndExclusionsPreserveOutlineOrder() {
        var selection = ExportChapterSelection(chapters: chapters, currentChapterID: chapters[19].id)
        selection.scope = .partial
        selection.startChapterID = chapters[3].id
        selection.endChapterID = chapters[7].id
        selection.excludedChapterIDs = [chapters[4].id, chapters[6].id, chapters[23].id]
        #expect(selection.selectedChapters(in: chapters) == [chapters[3], chapters[5], chapters[7]])
        selection.scope = .all
        #expect(selection.selectedChapters(in: chapters) == chapters)
        selection.scope = .partial
        #expect(selection.selectedChapters(in: chapters) == [chapters[3], chapters[5], chapters[7]])
    }

    @Test func emptyReversedAndFullyExcludedRangesStayEmpty() {
        var empty = ExportChapterSelection(chapters: [], currentChapterID: nil)
        empty.scope = .partial
        #expect(empty.selectedChapters(in: []).isEmpty)
        var selection = ExportChapterSelection(chapters: chapters, currentChapterID: chapters[0].id)
        selection.scope = .partial
        #expect(selection.selectedChapters(in: chapters) == [chapters[0]])
        selection.excludedChapterIDs.insert(chapters[0].id)
        #expect(selection.selectedChapters(in: chapters).isEmpty)
        selection.startChapterID = chapters[5].id
        #expect(selection.selectedChapters(in: chapters).isEmpty)
        selection.startChapterID = UUID()
        #expect(selection.selectedChapters(in: chapters).isEmpty)
    }

    @Test func missingCurrentChapterFallsBackToWholeRange() {
        var selection = ExportChapterSelection(chapters: chapters, currentChapterID: UUID())
        selection.scope = .partial
        #expect(selection.selectedChapters(in: chapters) == chapters)
    }

    @Test func nestedPartsAndDuplicateTitlesUseChapterIdentity() {
        let duplicate = BookOutlineNode.chapter(title: chapters[0].title, relativePath: "下卷/第一章.md")
        let project = BookProject(
            title: "分卷",
            outline: [
                .part(title: "上卷", children: [chapters[0], chapters[1]]),
                .part(title: "下卷", children: [duplicate, chapters[2]]),
            ])
        var selection = ExportChapterSelection(chapters: project.chapters, currentChapterID: duplicate.id)
        selection.scope = .partial
        selection.excludedChapterIDs = [chapters[0].id]
        #expect(selection.selectedChapters(in: project.chapters) == [chapters[1], duplicate])
    }
}
