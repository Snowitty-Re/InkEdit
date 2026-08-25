import SwiftUI

struct NotesInspectorView: View {
    @Bindable var model: BookWorkspaceModel

    var body: some View {
        Group {
            if model.currentChapterAnnotations.isEmpty {
                ContentUnavailableView(
                    "还没有批注",
                    systemImage: "highlighter",
                    description: Text("在阅读模式中选择文字即可划重点。")
                )
            } else {
                List {
                    ForEach(model.currentChapterAnnotations) { annotation in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(annotation.selectedText)
                                .font(.body)
                                .lineLimit(4)
                                .padding(.leading, 8)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(.yellow.opacity(0.72))
                                        .frame(width: 3)
                                }

                            TextField(
                                "添加笔记…",
                                text: Binding(
                                    get: { annotation.note },
                                    set: { model.updateNote(id: annotation.id, note: $0) }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.plain)

                            HStack {
                                Text(annotation.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("删除", role: .destructive) {
                                    model.deleteAnnotation(id: annotation.id)
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("笔记与重点")
        .frame(minWidth: 260, idealWidth: 320)
    }
}
