import SwiftUI

struct CloudSyncSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: BookProject
    let rootURL: URL
    let onPulled: () -> Void

    @State private var provider = CloudProvider.github
    @State private var configuration = CloudSyncConfiguration(provider: .github)
    @State private var token = ""
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let service = CloudSyncService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("云端同步")
                        .font(.title2.weight(.semibold))
                    Text("《\(project.title)》")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Picker("云存储", selection: $provider) {
                ForEach(CloudProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Form {
                if provider == .github {
                    TextField("仓库所有者", text: $configuration.githubOwner)
                    TextField("私有仓库名", text: $configuration.githubRepository)
                    TextField("分支", text: $configuration.githubBranch)
                    SecureField("Fine-grained personal access token", text: $token)
                    Text("令牌需授权所选私有仓库的 Contents 读写与 Metadata 读取权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SecureField("Google OAuth 访问令牌", text: $token)
                    Text("令牌需包含 drive.file 权限；令牌到期后可在此重新连接。书稿只保存到 InkEdit 创建的 Drive 文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let lastSyncedAt = configuration.lastSyncedAt {
                LabeledContent(
                    "最近同步",
                    value: lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Button("保存连接") { saveConnection() }
                Spacer()
                Button("从云端拉取") { synchronize(direction: .pull) }
                Button("上传当前版本") { synchronize(direction: .push) }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(isWorking)
        }
        .padding(24)
        .frame(width: 560)
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("正在同步…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear { loadConnection() }
        .onChange(of: provider) { _, _ in loadConnection() }
        .alert("同步失败", isPresented: errorBinding) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private enum Direction {
        case push
        case pull
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadConnection() {
        do {
            configuration = try service.configuration(for: provider, rootURL: rootURL)
            token = try service.token(for: provider)
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveConnection() {
        do {
            configuration.provider = provider
            try service.saveConnection(configuration: configuration, token: token, rootURL: rootURL)
            statusMessage = "连接信息已安全保存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func synchronize(direction: Direction) {
        configuration.provider = provider
        do {
            try service.saveConnection(configuration: configuration, token: token, rootURL: rootURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isWorking = true
        statusMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let updated: CloudSyncConfiguration
                let result: CloudSyncResult
                switch direction {
                case .push:
                    (updated, result) = try await service.push(
                        configuration: configuration,
                        project: project,
                        rootURL: rootURL
                    )
                    statusMessage = "已上传 \(result.changedFileCount) 个项目文件"
                case .pull:
                    (updated, result) = try await service.pull(
                        configuration: configuration,
                        project: project,
                        rootURL: rootURL
                    )
                    statusMessage =
                        result.conflictFileCount == 0
                        ? "已拉取 \(result.changedFileCount) 个更新"
                        : "已拉取更新，并保留 \(result.conflictFileCount) 个云端冲突副本"
                    onPulled()
                }
                configuration = updated
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
