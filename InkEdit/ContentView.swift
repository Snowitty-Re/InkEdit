import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private struct DetailsPresentation: Identifiable {
        let project: OpenBookProject
        var id: UUID { project.metadata.id }
    }
    private enum LibrarySection: String, CaseIterable, Identifiable {
        case all
        case recent
        case favorites

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .all: "全部作品"
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
    @State private var detailsProject: DetailsPresentation?
    @State private var detailsAccess: ScopedBookAccess?
    @State private var launchAction = WorkspaceLaunchAction.write
    @State private var previewRevision = 0
    @AppStorage("inkedit.library.listLayout") private var listLayout = false
    @AppStorage("inkedit.appearance") private var appearance = InkAppearance.system

    private let repository = BookRepository()

    init(initialProject: OpenBookProject? = nil) {
        _activeProject = State(initialValue: initialProject)
    }

    var body: some View {
        Group {
            if let activeProject {
                BookWorkspaceView(
                    project: activeProject, launchAction: launchAction, onClose: closeWorkspace,
                    onProjectUpdated: updateLibraryDetails)
            } else {
                libraryView
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .inkPanel()
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showsNewBookSheet) {
            NewBookSheet { title, author in
                createBook(title: title, author: author)
            }
        }
        .sheet(
            item: $detailsProject,
            onDismiss: {
                detailsProject = nil
                detailsAccess?.stop()
                detailsAccess = nil
            }
        ) { presentation in
            BookDetailsSheet(project: presentation.project.metadata, rootURL: presentation.project.rootURL) { updated in
                updateLibraryDetails(updated)
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
        HStack(spacing: 0) {
            librarySidebar.frame(width: 174)
            Rectangle().fill(InkTheme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                libraryHeader
                libraryGrid
                HStack {
                    Text("共 \(filteredBooks.count) 部作品")
                    Spacer()
                    Text("故事，从这里开始。")
                }
                .font(.caption).foregroundStyle(InkTheme.muted)
                .padding(.horizontal, 32).padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(InkTheme.canvas)
            Rectangle().fill(InkTheme.line).frame(width: 1)
            detailView.frame(width: 260)
        }
        .navigationTitle("InkEdit")
        .onAppear { if selectedBookID == nil { selectedBookID = filteredBooks.first?.id } }
        .onChange(of: searchText) { _, _ in reconcileSelection() }
        .onChange(of: section) { _, _ in reconcileSelection() }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("InkMark").resizable().frame(width: 40, height: 40)
                Text("InkEdit").font(.system(size: 21, weight: .medium, design: .serif))
            }.padding(.top, 26).padding(.bottom, 38)
            Text("我的书房").font(.caption).foregroundStyle(InkTheme.muted).padding(.leading, 12).padding(.bottom, 12)
            ForEach(LibrarySection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 10) {
                        Label(item.title, systemImage: item.symbol)
                        Spacer()
                        if item == .all { Text("\(books.count)").font(.caption) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .background(
                        section == item ? InkTheme.sage.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.bottom, 4)
                .accessibilityIdentifier("library-section-\(item.rawValue)")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("让每一个故事，\n有自己的位置。")
                    .font(InkTheme.editorial(15)).lineSpacing(7).foregroundStyle(InkTheme.muted)
                Rectangle().fill(InkTheme.line).frame(height: 1).padding(.vertical, 8)
                SettingsLink { Label("偏好设置", systemImage: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(InkTheme.muted)
            }.padding(12).padding(.bottom, 12)
        }
        .padding(.horizontal, 12).frame(maxHeight: .infinity)
        .background(InkTheme.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-sidebar")
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section == .all ? "我的作品" : (section == .favorites ? "珍藏的故事" : "最近打开"))
                        .font(InkTheme.editorial(32))
                    Text("落笔成章，珍藏每一份灵感。").font(.callout).foregroundStyle(InkTheme.muted)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("导入 Markdown 文件…") { showsMarkdownImporter = true }
                    Button("导入项目文件夹…") { importFolder() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton).fixedSize().help("导入作品")
                .accessibilityLabel("导入作品").accessibilityIdentifier("import-book-menu")
                Button {
                    showsNewBookSheet = true
                } label: {
                    Label("新建作品", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("create-book-button")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(InkTheme.muted)
                TextField("搜索书名或作者", text: $searchText).textFieldStyle(.plain)
                    .accessibilityIdentifier("library-search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(InkTheme.muted).help("清除搜索")
                }
                Spacer(minLength: 4)
                Picker("作品布局", selection: $listLayout) {
                    Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel("橱窗")
                    Image(systemName: "list.bullet").tag(true).accessibilityLabel("列表")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 76)
                .accessibilityIdentifier("library-layout-picker")
            }
            .padding(10).background(InkTheme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(InkTheme.line, lineWidth: 1))
        }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 16)
    }

    private func reconcileSelection() {
        if !filteredBooks.contains(where: { $0.id == selectedBookID }) {
            selectedBookID = filteredBooks.first?.id
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
                    Label(books.isEmpty ? "开始你的第一本书" : "这里还没有作品", systemImage: "book.closed")
                } description: {
                    Text(books.isEmpty ? "创建一本新书，或导入已有 Markdown 项目。" : "试试其他筛选条件，或搜索书名与作者。")
                } actions: {
                    if books.isEmpty {
                        Button("创建书籍") { showsNewBookSheet = true }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ScrollView {
                    if listLayout {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredBooks) { book in
                                bookButton(book) {
                                    HStack(spacing: 20) {
                                        LibraryBookCover(book: book).frame(width: 48)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(book.title).font(InkTheme.editorial(21)).lineLimit(1)
                                            Text(book.author.isEmpty ? "未设置作者" : book.author)
                                                .font(.caption).foregroundStyle(InkTheme.muted)
                                        }
                                        Spacer()
                                        if book.isFavorite {
                                            Image(systemName: "star.fill").foregroundStyle(InkTheme.sage)
                                        }
                                        Image(systemName: "chevron.right").foregroundStyle(InkTheme.muted)
                                    }
                                    .padding(14)
                                    .background(
                                        selectedBookID == book.id ? InkTheme.sage.opacity(0.10) : InkTheme.paper,
                                        in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }.padding(.horizontal, 32).padding(.vertical, 6)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 185, maximum: 235), spacing: 24)],
                            alignment: .leading, spacing: 24
                        ) {
                            ForEach(filteredBooks) { book in
                                bookButton(book) { BookCard(book: book, isSelected: selectedBookID == book.id) }
                            }
                        }.padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 16)
                    }
                }
            }
        }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookButton<Label: View>(_ book: LibraryBook, @ViewBuilder label: () -> Label) -> some View {
        Button {
            selectedBookID = book.id
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-book-\(book.title)")
        .accessibilityLabel("\(book.title)，\(book.author)")
        .contextMenu {
            Button("进入写作") { openBook(book) }
            Button("作品信息…") { editBookDetails(book) }
            Button(book.isFavorite ? "取消收藏" : "收藏") { toggleFavorite(book) }
            Divider()
            Button("从书架移除", role: .destructive) { removeFromLibrary(book) }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let book = selectedBook {
            LibraryDetailView(
                book: book, previewRevision: previewRevision,
                onOpen: { openBook(book, action: $0) },
                onDetails: { editBookDetails(book) },
                onReveal: { revealInFinder(book) },
                onFavorite: { toggleFavorite(book) })
        } else {
            VStack(spacing: 16) {
                Image(systemName: "book.pages").font(.system(size: 32, weight: .ultraLight))
                Text("静候一个故事").font(InkTheme.editorial(22))
                Text("选择作品，开始写作或阅读。").font(.caption)
            }
            .foregroundStyle(InkTheme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(InkTheme.paper)
        }
    }

    private func toggleFavorite(_ book: LibraryBook) {
        book.isFavorite.toggle()
        do { try modelContext.save() } catch { errorMessage = error.localizedDescription }
        reconcileSelection()
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

    private func openBook(_ book: LibraryBook, action: WorkspaceLaunchAction = .write) {
        do {
            let access = try BookAccessController.resolve(book.rootBookmark)
            var transferred = false
            defer { if !transferred { access.stop() } }
            let project = try repository.loadProject(at: access.url)
            book.title = project.title
            book.author = project.author
            book.coverRelativePath = project.coverRelativePath
            book.lastOpenedAt = .now
            try modelContext.save()
            activeAccess?.stop()
            activeAccess = access
            transferred = true
            launchAction = action
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

    private func updateLibraryDetails(_ project: BookProject) {
        previewRevision += 1
        guard let book = books.first(where: { $0.projectID == project.id }) else { return }
        book.title = project.title
        book.author = project.author
        book.coverRelativePath = project.coverRelativePath
        do { try modelContext.save() } catch { errorMessage = error.localizedDescription }
    }

    private func editBookDetails(_ book: LibraryBook) {
        do {
            let access = try BookAccessController.resolve(book.rootBookmark)
            do {
                let project = try repository.loadProject(at: access.url)
                detailsAccess = access
                detailsProject = DetailsPresentation(project: OpenBookProject(rootURL: access.url, metadata: project))
            } catch {
                access.stop()
                throw error
            }
        } catch { errorMessage = error.localizedDescription }
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
