import AppKit
import SwiftUI

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: BookProject
    let rootURL: URL

    @State private var format = ExportFormat.epub
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var exportTask: Task<Void, Never>?
    @State private var chapterSelection: ExportChapterSelection

    init(project: BookProject, rootURL: URL, currentChapterID: UUID? = nil) {
        self.project = project
        self.rootURL = rootURL
        _chapterSelection = State(
            initialValue: ExportChapterSelection(chapters: project.chapters, currentChapterID: currentChapterID))
    }

    private var selectedChapters: [BookOutlineNode] {
        chapterSelection.selectedChapters(in: project.chapters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导出《\(project.title)》")
                    .font(.title2.weight(.semibold))
                Text("所选章节将按书籍目录顺序合并，原始 Markdown 不会被修改。")
                    .foregroundStyle(.secondary)
            }

            chapterOptions
                .disabled(exportTask != nil)

            Picker("文件格式", selection: $format) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(exportTask != nil)

            GroupBox {
                Text(formatDescription)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("取消") {
                    exportTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("选择位置并导出") { chooseDestinationAndExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(exportTask != nil || selectedChapters.isEmpty)
                    .accessibilityIdentifier("choose-export-destination")
            }
        }
        .padding(24)
        .frame(width: 560)
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("正在生成 \(format.title)…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .allowsHitTesting(false)
            }
        }
        .onDisappear { exportTask?.cancel() }
        .alert("导出失败", isPresented: errorBinding) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var chapterOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("导出范围", selection: $chapterSelection.scope) {
                ForEach(ExportChapterSelection.Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("export-scope")

            if chapterSelection.scope == .partial {
                HStack {
                    chapterPicker("从", selection: $chapterSelection.startChapterID)
                        .accessibilityIdentifier("export-start-chapter")
                    chapterPicker("至", selection: $chapterSelection.endChapterID)
                        .accessibilityIdentifier("export-end-chapter")
                }
                Text("默认从首章到当前章节（含）；取消勾选可排除章节。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let chaptersInRange = chapterSelection.chaptersInRange(in: project.chapters)
                if chaptersInRange.isEmpty {
                    Text("请选择有效范围，起始章节不能晚于截止章节。")
                        .foregroundStyle(.orange)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(chaptersInRange) { chapter in
                                Toggle(isOn: inclusionBinding(for: chapter.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                        Text(chapter.relativePath ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier("export-include-\(chapter.title)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(height: 140)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Text("已选择 \(selectedChapters.count) / \(project.chapters.count) 章")
                .font(.callout)
                .foregroundStyle(selectedChapters.isEmpty ? .orange : .secondary)
                .accessibilityIdentifier("export-chapter-count")
            if selectedChapters.isEmpty {
                Text("请至少选择一个章节后再导出。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func chapterPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(project.chapters.enumerated()), id: \.element.id) { index, chapter in
                Text("\(index + 1). \(chapter.title)").tag(Optional(chapter.id))
            }
        }
    }

    private func inclusionBinding(for chapterID: UUID) -> Binding<Bool> {
        Binding(
            get: { !chapterSelection.excludedChapterIDs.contains(chapterID) },
            set: { included in
                if included {
                    chapterSelection.excludedChapterIDs.remove(chapterID)
                } else {
                    chapterSelection.excludedChapterIDs.insert(chapterID)
                }
            })
    }

    private var formatDescription: String {
        switch format {
        case .html: "生成可离线阅读的单文件网页，本地插图会以内嵌资源保存。"
        case .pdf: "按 A4 页面排版，适合审稿、打印与固定版式分享。"
        case .epub: "生成带章节目录和书籍元数据的标准电子书，并打包本地插图。"
        case .docx: "生成带标题层级和中文正文样式的 Word 文稿，适合交稿与继续排版。"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func chooseDestinationAndExport() {
        let chapterIDs = Set(selectedChapters.map(\.id))
        guard !chapterIDs.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "导出《\(project.title)》"
        panel.nameFieldStringValue = "\(safeFilename(project.title)).\(format.filenameExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.directoryURL = rootURL
        let selectedFormat = format
        exportTask = Task { @MainActor in
            defer {
                isExporting = false
                exportTask = nil
            }
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = await panel.begin()
            }
            guard response == .OK, let destinationURL = panel.url, !Task.isCancelled else { return }
            isExporting = true
            do {
                try await BookExportService().export(
                    selectedFormat,
                    project: project,
                    rootURL: rootURL,
                    destinationURL: destinationURL,
                    chapterIDs: chapterIDs
                )
                try Task.checkCancellation()
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func safeFilename(_ source: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = source.components(separatedBy: invalid)
        let filename = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? "未命名书籍" : filename
    }
}
