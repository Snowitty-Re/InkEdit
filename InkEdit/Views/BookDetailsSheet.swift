import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BookDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: BookProject
    let rootURL: URL
    let onSaved: (BookProject) -> Void

    @State private var draft: BookDetailsDraft
    @State private var coverData: Data?
    @State private var showsImporter = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    private let service = BookDetailsService()

    init(project: BookProject, rootURL: URL, onSaved: @escaping (BookProject) -> Void) {
        self.project = project
        self.rootURL = rootURL
        self.onSaved = onSaved
        _draft = State(initialValue: BookDetailsDraft(project: project))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("作品信息").font(.title2.bold())
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                        if let coverData, let image = NSImage(data: coverData) {
                            Image(nsImage: image).resizable().scaledToFit()
                        } else {
                            Label("未设置封面", systemImage: "book.closed")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 160, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("book-cover-preview")
                    Button("选择封面…") { showsImporter = true }
                        .accessibilityIdentifier("choose-book-cover")
                    Button("移除封面") {
                        draft.cover = .remove
                        coverData = nil
                    }
                    .disabled(!hasCover)
                    .accessibilityIdentifier("remove-book-cover")
                    Text("PNG / JPEG / HEIC，最大 20 MB")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    TextField("书名", text: $draft.title)
                        .accessibilityIdentifier("details-title")
                    TextField("作者 / 笔名", text: $draft.author)
                        .accessibilityIdentifier("details-author")
                    Text("简介").font(.headline)
                    TextEditor(text: $draft.summary)
                        .frame(height: 160)
                        .border(.quaternary)
                        .accessibilityIdentifier("details-summary")
                    Text("修改书名不会重命名项目文件夹；封面会保存在作品内。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)
            }
            .disabled(isWorking)
            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-book-details")
            }
        }
        .padding(24)
        .frame(width: 620)
        .interactiveDismissDisabled(isWorking)
        .task {
            isWorking = true
            defer { isWorking = false }
            do {
                coverData = try await service.coverData(relativePath: project.coverRelativePath, rootURL: rootURL)
            } catch { errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.png, .jpeg, .heic]) { result in
            do {
                let url = try result.get()
                isWorking = true
                Task {
                    defer { isWorking = false }
                    do {
                        let data = try await service.importCover(from: url)
                        draft.cover = .replace(data)
                        coverData = data
                    } catch { errorMessage = error.localizedDescription }
                }
            } catch { errorMessage = error.localizedDescription }
        }
        .alert(
            "作品信息操作失败",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var hasCover: Bool {
        switch draft.cover {
        case .unchanged: project.coverRelativePath != nil
        case .remove: false
        case .replace: true
        }
    }

    private func save() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let updated = try await service.save(draft, projectID: project.id, rootURL: rootURL)
                onSaved(updated)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
