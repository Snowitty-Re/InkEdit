import SwiftData
import SwiftUI

@main
struct InkEditApp: App {
    @NSApplicationDelegateAdaptor(InkEditApplicationDelegate.self) private var applicationDelegate

    private var defaultWindowSize: CGSize {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-compact") {
                return CGSize(width: 960, height: 640)
            }
        #endif
        return CGSize(width: 1280, height: 820)
    }

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
                if let index = arguments.firstIndex(of: "-ui-testing-cover-data"), index + 1 < arguments.count,
                    let source = Data(base64Encoded: arguments[index + 1])
                {
                    let path = "assets/test-cover.png"
                    try AtomicFileWriter.write(
                        try CoverImageProcessor.pngData(from: source), to: project.rootURL.appendingPathComponent(path))
                    project.metadata.coverRelativePath = path
                    try repository.saveProject(project.metadata, at: project.rootURL)
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
                let container = try ModelContainer(for: LibraryBook.self, configurations: configuration)
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-ui-testing-showcase") {
                        try ShowcaseFixtures.populate(container.mainContext)
                    }
                #endif
                return container
            }
            return try ModelContainer(for: LibraryBook.self)
        } catch {
            fatalError("Could not create the InkEdit library: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-details-panel"), let exportTestProject {
                    BookDetailsTestHost(project: exportTestProject)
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-export-panel"), let exportTestProject
                {
                    ExportPanelTestHost(project: exportTestProject)
                } else {
                    ContentView(initialProject: exportTestProject)
                }
            #else
                ContentView(initialProject: exportTestProject)
            #endif
        }
        .modelContainer(modelContainer)
        .defaultSize(width: defaultWindowSize.width, height: defaultWindowSize.height)

        Settings { InkSettingsView() }
    }
}

#if DEBUG
    private struct BookDetailsTestHost: View {
        @State var project: OpenBookProject
        @State private var showsDetails = false

        var body: some View {
            Button("作品信息") { showsDetails = true }
                .accessibilityIdentifier("details-test-open")
                .frame(width: 900, height: 760)
                .sheet(isPresented: $showsDetails) {
                    BookDetailsSheet(project: project.metadata, rootURL: project.rootURL) {
                        project.metadata = $0
                    }
                }
        }
    }

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
