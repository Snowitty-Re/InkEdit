import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum LibrarySection: String, CaseIterable, Identifiable {
        case all
        case recent
        case favorites

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .all: "全部书籍"
            case .recent: "最近打开"
            case .favorites: "收藏"
            }
        }

        var symbol: String {
            switch self {
            case .all: "books.vertical"
            case .recent: "clock"
            case .favorites: "star"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryBook.lastOpenedAt, order: .reverse) private var books: [LibraryBook]

    @State private var section: LibrarySection? = .all
    @State private var selectedBookID: UUID?
    @State private var searchText = ""
    @State private var showsNewBookSheet = false
    @State private var showsMarkdownImporter = false
    @State private var errorMessage: String?
    @State private var activeProject: OpenBookProject?
    @State private var activeAccess: ScopedBookAccess?

    private let repository = BookRepository()

    var body: some View {
        Group {
            if let activeProject {
                BookWorkspaceView(project: activeProject, onClose: closeWorkspace)
            } else {
                libraryView
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showsNewBookSheet) {
            NewBookSheet { title, author in
                createBook(title: title, author: author)
            }
        }
        .fileImporter(
            isPresented: $showsMarkdownImporter,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handleMarkdownImport
        )
        .alert("操作失败", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var libraryView: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("书架") {
                    ForEach(LibrarySection.allCases) { item in
                        Label(item.title, systemImage: item.symbol)
                            .tag(item)
                    }
                }

                Section("云端") {
                    Label("Google Drive", systemImage: "externaldrive.badge.icloud")
                    Label("GitHub", systemImage: "shippingbox")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("InkEdit")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } content: {
            libraryGrid
                .navigationTitle(section?.title ?? "书架")
                .searchable(text: $searchText, prompt: "搜索书名或作者")
                .toolbar { libraryToolbar }
        } detail: {
            detailView
        }
    }

    private var filteredBooks: [LibraryBook] {
        books.filter { book in
            let matchesSection =
                switch section ?? .all {
                case .all: true
                case .recent:
                    book.lastOpenedAt > Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
                case .favorites: book.isFavorite
                }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch =
                query.isEmpty || book.title.localizedCaseInsensitiveContains(query)
                || book.author.localizedCaseInsensitiveContains(query)
            return matchesSection && matchesSearch
        }
    }

    private var libraryGrid: some View {
        Group {
            if filteredBooks.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "开始你的第一本书" : "没有找到书籍", systemImage: "book.closed")
                } description: {
                    Text(searchText.isEmpty ? "创建一本新书，或导入已有 Markdown 项目。" : "尝试其他搜索关键词。")
                } actions: {
                    if searchText.isEmpty {
                        Button("创建书籍") { showsNewBookSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 22)],
                        alignment: .leading,
                        spacing: 24
                    ) {
                        ForEach(filteredBooks) { book in
                            BookCard(book: book, isSelected: selectedBookID == book.id)
                                .onTapGesture { selectedBookID = book.id }
                                .contextMenu {
                                    Button(book.isFavorite ? "取消收藏" : "收藏") {
                                        book.isFavorite.toggle()
                                    }
                                    Divider()
                                    Button("从书架移除", role: .destructive) {
                                        removeFromLibrary(book)
                                    }
                                }
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let book = selectedBook {
            VStack(alignment: .leading, spacing: 18) {
                Text(book.title)
                    .font(.largeTitle.weight(.semibold))
                Text(book.author.isEmpty ? "未设置作者" : book.author)
                    .foregroundStyle(.secondary)
                Divider()
                LabeledContent("项目位置", value: book.rootPath)
                LabeledContent("最近打开", value: book.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                HStack {
                    Button("在 Finder 中显示") { revealInFinder(book) }
                    Spacer()
                    Button("打开书籍") { openBook(book) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .navigationTitle(book.title)
        } else {
            ContentUnavailableView("选择一本书", systemImage: "book.pages", description: Text("查看书籍信息并进入写作。"))
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("导入 Markdown 文件…") { showsMarkdownImporter = true }
                Button("导入项目文件夹…") { importFolder() }
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }

            Button {
                showsNewBookSheet = true
            } label: {
                Label("创建书籍", systemImage: "plus")
            }
        }
    }

    private var selectedBook: LibraryBook? {
        books.first { $0.id == selectedBookID }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func createBook(title: String, author: String) {
        guard let parent = chooseDirectory(prompt: "选择保存书籍的位置") else { return }
        withScopedAccess(to: parent) {
            let project = try repository.createBook(title: title, author: author, in: parent)
            try addToLibrary(project)
        }
    }

    private func handleMarkdownImport(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            guard let parent = chooseDirectory(prompt: "选择导入后书籍的保存位置") else { return }
            let sourceAccess = source.startAccessingSecurityScopedResource()
            defer { if sourceAccess { source.stopAccessingSecurityScopedResource() } }
            withScopedAccess(to: parent) {
                let project = try repository.importMarkdown(source, into: parent)
                try addToLibrary(project)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFolder() {
        guard let rootURL = chooseDirectory(prompt: "选择包含 Markdown 章节的项目文件夹") else { return }
        withScopedAccess(to: rootURL) {
            let project = try repository.openOrImportFolder(rootURL)
            try addToLibrary(project)
        }
    }

    private func addToLibrary(_ project: OpenBookProject) throws {
        if let existing = books.first(where: { $0.projectID == project.metadata.id }) {
            selectedBookID = existing.id
            return
        }
        let bookmark = try BookAccessController.makeBookmark(for: project.rootURL)
        let book = LibraryBook(
            projectID: project.metadata.id,
            title: project.metadata.title,
            author: project.metadata.author,
            rootPath: project.rootURL.path,
            rootBookmark: bookmark,
            coverRelativePath: project.metadata.coverRelativePath
        )
        modelContext.insert(book)
        try modelContext.save()
        selectedBookID = book.id
    }

    private func openBook(_ book: LibraryBook) {
        do {
            let access = try BookAccessController.resolve(book.rootBookmark)
            let project = try repository.loadProject(at: access.url)
            book.title = project.title
            book.author = project.author
            book.lastOpenedAt = .now
            try modelContext.save()
            activeAccess?.stop()
            activeAccess = access
            activeProject = OpenBookProject(rootURL: access.url, metadata: project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func closeWorkspace() {
        activeProject = nil
        activeAccess?.stop()
        activeAccess = nil
    }

    private func revealInFinder(_ book: LibraryBook) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.rootPath)])
    }

    private func removeFromLibrary(_ book: LibraryBook) {
        if selectedBookID == book.id { selectedBookID = nil }
        modelContext.delete(book)
        try? modelContext.save()
    }

    private func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func withScopedAccess(to url: URL, operation: () throws -> Void) {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: LibraryBook.self, inMemory: true)
}
