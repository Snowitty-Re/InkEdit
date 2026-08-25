import Testing

@testable import InkEdit

struct WritingStatisticsTests {
    @Test func countsChineseCharactersAndLatinWords() {
        let statistics = WritingStatistics(markdown: "# 第一章\n\n长夜将尽。 Hello world!")

        #expect(statistics.characterCount == 17)
        #expect(statistics.wordCount == 9)
        #expect(statistics.estimatedReadingMinutes == 1)
    }

    @Test func ignoresMarkdownPunctuationInCharacterCount() {
        let statistics = WritingStatistics(markdown: "**星河** — `夜色`")

        #expect(statistics.characterCount == 4)
        #expect(statistics.wordCount == 4)
    }
}
