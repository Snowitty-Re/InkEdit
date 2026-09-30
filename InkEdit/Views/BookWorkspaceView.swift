import SwiftUI

enum WorkspaceLaunchAction { case write, read, export, cloud }

struct BookWorkspaceView: View {
    private enum WorkspaceMode: String, CaseIterable, Identifiable {
        case write
        case read

        var id: Self { self }

        var title: String {
            switch self {
            case .write: "写作"
            case .read: "阅读"
            }
        }
    }

    @State private var model: BookWorkspaceModel
    @State private var showsNewChapter = false
    @State private var newChapterTitle = ""
    @State private var mode = WorkspaceMode.write
    @AppStorage("inkedit.readerTheme", store: AppPreferences.defaults) private var readerTheme = ReaderTheme.sepia
    @State private var showsInspector = false
    @State private var showsExport = false
    @State private var showsCloudSync = false
    @State private var showsBookDetails = false

    let onClose: () -> Void
    let onProjectUpdated: (BookProject) -> Void

    init(
        project: OpenBookProject, launchAction: WorkspaceLaunchAction = .write, onClose: @escaping () -> Void,
        onProjectUpdated: @escaping (BookProject) -> Void = { _ in }
    ) {
        _model = State(initialValue: BookWorkspaceModel(project: project))
        _mode = State(initialValue: launchAction == .read ? .read : .write)
        _showsExport = State(initialValue: launchAction == .export)
        _showsCloudSync = State(initialValue: launchAction == .cloud)
        self.onClose = onClose
        self.onProjectUpdated = onProjectUpdated
    }

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Image("InkMark").resizable().frame(width: 38, height: 38)
                    Text(model.project.title).font(InkTheme.editorial(24)).lineLimit(2)
                    Text(model.project.author.isEmpty ? "我的手稿" : model.project.author)
                        .font(.caption).foregroundStyle(InkTheme.muted)
                }.padding(22)
                Rectangle().fill(InkTheme.line).frame(height: 1).padding(.horizontal, 20)
                List(selection: selectedChapterBinding) {
                    Section("章节") {
                        ForEach(model.chapters) { chapter in
                            Label(chapter.title, systemImage: "doc.text")
                                .tag(chapter.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("chapter-sidebar")
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(InkTheme.sidebar)
            .navigationTitle(model.project.title)
            .toolbar {
                ToolbarItem {
                    Button {
                        showsBookDetails = true
                    } label: {
                        Label("作品信息", systemImage: "info.circle")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .help("设置书名、作者、简介与封面")
                    .accessibilityIdentifier("book-details-button")
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.flushCurrentChapter()
                        onClose()
                    } label: {
                        Label("返回书架", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("workspace-back-button")
                }
                ToolbarItem {
                    Button {
                        newChapterTitle = ""
                        showsNewChapter = true
                    } label: {
                        Label("新建章节", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .accessibilityIdentifier("new-chapter-button")
                }
                ToolbarItem(placement: .principal) {
                    Picker("工作模式", selection: modeBinding) {
                        ForEach(WorkspaceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    .accessibilityIdentifier("workspace-mode-picker")
                }
                ToolbarItem {
                    Button {
                        showsInspector.toggle()
                    } label: {
                        Label("笔记与重点", systemImage: "note.text")
                    }
                    .help("显示笔记与重点")
                }
                ToolbarItem {
                    Button {
                        model.flushCurrentChapter()
                        showsExport = true
                    } label: {
                        Label("导出书籍", systemImage: "square.and.arrow.up")
                    }
                    .help("导出书籍")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .accessibilityIdentifier("export-book-button")
                }
                ToolbarItem {
                    Button {
                        model.flushCurrentChapter()
                        showsCloudSync = true
                    } label: {
                        Label("云端同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    .help("Google Drive 或 GitHub 私有仓库同步")
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .accessibilityIdentifier("cloud-sync-button")
                }
            }
            Rectangle().fill(InkTheme.line).frame(width: 1)
            Group {
                if let chapter = model.selectedChapter {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chapter.title)
                                    .font(InkTheme.editorial(24))
                                Text(chapter.relativePath ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            saveStatus
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)

                        Divider()

                        switch mode {
                        case .write:
                            MarkdownTextEditor(text: chapterTextBinding) { isBusy in
                                model.recordEditorActivity(isBusy: isBusy, chapterID: chapter.id)
                            }
                            .id(chapter.id)
                            .frame(maxWidth: 920, maxHeight: .infinity)
                            .background(InkTheme.paper)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(InkTheme.canvas)
                        case .read:
                            ReaderView(
                                markdown: model.chapterText,
                                chapterTitle: chapter.title,
                                rootURL: model.rootURL,
                                annotations: model.currentChapterAnnotations,
                                onSelection: { selection in
                                    model.addHighlight(selection)
                                    showsInspector = true
                                },
                                theme: $readerTheme
                            )
                        }

                        Divider()

                        HStack(spacing: 18) {
                            Text("\(model.statistics.characterCount) 字符")
                            Text("\(model.statistics.wordCount) 字词")
                            Text("约 \(model.statistics.estimatedReadingMinutes) 分钟阅读")
                            Spacer()
                            Text(mode == .write ? "Markdown" : "阅读模式")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(chapter.title)
                } else {
                    ContentUnavailableView("没有章节", systemImage: "doc.badge.plus", description: Text("创建章节后开始写作。"))
                }
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .inkPanel()
        .inspector(isPresented: $showsInspector) {
            NotesInspectorView(model: model)
        }
        .sheet(isPresented: $showsExport) {
            ExportSheet(project: model.project, rootURL: model.rootURL, currentChapterID: model.selectedChapterID)
        }
        .sheet(isPresented: $showsBookDetails) {
            BookDetailsSheet(project: model.project, rootURL: model.rootURL) { updated in
                model.applyProjectDetails(updated)
                onProjectUpdated(updated)
            }
        }
        .sheet(isPresented: $showsCloudSync) {
            CloudSyncSheet(
                project: model.project,
                rootURL: model.rootURL,
                onPulled: model.reloadAfterExternalChange
            )
        }
        .onAppear { model.start() }
        .onDisappear { model.flushCurrentChapter() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.flushCurrentChapter()
        }
        .alert("新建章节", isPresented: $showsNewChapter) {
            TextField("章节标题", text: $newChapterTitle)
            Button("取消", role: .cancel) {}
            Button("创建") { model.addChapter(title: newChapterTitle) }
                .disabled(newChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("章节将以独立 Markdown 文件保存在书籍目录。")
        }
        .alert("保存失败", isPresented: errorBinding) {
            Button("好", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private var selectedChapterBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedChapterID },
            set: { if let id = $0 { model.selectChapter(id: id) } }
        )
    }

    private var chapterTextBinding: Binding<String> {
        Binding(
            get: { model.chapterText },
            set: { model.updateText($0) }
        )
    }

    private var modeBinding: Binding<WorkspaceMode> {
        Binding(
            get: { mode },
            set: { newMode in
                if newMode == .read {
                    model.flushCurrentChapter()
                }
                mode = newMode
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch model.saveState {
        case .saved(let date):
            Label("已保存 \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .saving:
            Label("正在保存", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .unsaved:
            Label("未保存", systemImage: "circle.fill")
                .foregroundStyle(.orange)
        case .failed:
            Label("保存失败", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
