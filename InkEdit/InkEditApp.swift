import SwiftData
import SwiftUI

@main
struct InkEditApp: App {
    private let exportTestProject: OpenBookProject? = {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-ui-testing"), arguments.contains("-ui-testing-export") else { return nil }
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                let repository = BookRepository()
                var project = try repository.createBook(title: "导出回归", author: "作者", in: parent)
                if let chapter = project.metadata.chapters.first {
                    try repository.writeChapter(
                        "# 第一章\n\n这是中文导出测试书稿。\n\n**重点**和普通正文。", chapter: chapter, in: project.rootURL)
                }
                if arguments.contains("-ui-testing-export-range") {
                    for title in ["第二章", "第三章"] {
                        project.metadata = try repository.addChapter(
                            title: title, to: project.metadata, in: project.rootURL)
                    }
                }
                return project
            } catch { fatalError("Could not create export test fixture: \(error)") }
        #else
            return nil
        #endif
    }()

    private let modelContainer: ModelContainer = {
        do {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: LibraryBook.self, configurations: configuration)
            }
            return try ModelContainer(for: LibraryBook.self)
        } catch {
            fatalError("Could not create the InkEdit library: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-export-panel"), let exportTestProject {
                    ExportPanelTestHost(project: exportTestProject)
                } else {
                    ContentView(initialProject: exportTestProject)
                }
            #else
                ContentView(initialProject: exportTestProject)
            #endif
        }
        .modelContainer(modelContainer)
    }
}

#if DEBUG
    /// Allows export panel tests to run independently of the editor's AppKit layout.
    private struct ExportPanelTestHost: View {
        let project: OpenBookProject
        @State private var showsExport = false

        var body: some View {
            Button("导出书籍") { showsExport = true }
                .accessibilityIdentifier("export-test-open")
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .frame(width: 900, height: 760)
                .sheet(isPresented: $showsExport) {
                    ExportSheet(
                        project: project.metadata, rootURL: project.rootURL,
                        currentChapterID: project.metadata.chapters.dropFirst().first?.id
                            ?? project.metadata.chapters.first?.id)
                }
        }
    }
#endif
