import AppKit
import SwiftUI

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: BookProject
    let rootURL: URL

    @State private var format = ExportFormat.epub
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导出《\(project.title)》")
                    .font(.title2.weight(.semibold))
                Text("所有章节将按书籍目录顺序合并，原始 Markdown 不会被修改。")
                    .foregroundStyle(.secondary)
            }

            Picker("文件格式", selection: $format) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.radioGroup)

            GroupBox {
                Text(formatDescription)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("选择位置并导出") { chooseDestinationAndExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting)
            }
        }
        .padding(24)
        .frame(width: 480)
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("正在生成 \(format.title)…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("导出失败", isPresented: errorBinding) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
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
        let panel = NSSavePanel()
        panel.title = "导出《\(project.title)》"
        panel.nameFieldStringValue = "\(safeFilename(project.title)).\(format.filenameExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                try await BookExportService().export(
                    format,
                    project: project,
                    rootURL: rootURL,
                    destinationURL: destinationURL
                )
                dismiss()
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
