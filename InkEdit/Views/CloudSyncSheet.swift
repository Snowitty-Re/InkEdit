import SwiftUI

struct CloudSyncSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: BookProject
    let rootURL: URL
    let onPulled: () -> Void

    @State private var provider = CloudProvider.github
    @State private var configuration = CloudSyncConfiguration(provider: .github)
    @State private var token = ""
    @State private var hasSavedCredential = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var confirmsDefaults = false

    private let service = CloudSyncService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("云端同步")
                        .font(InkTheme.editorial(27))
                    Text("《\(project.title)》")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
            }

            Picker("云存储", selection: $provider) {
                ForEach(CloudProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isWorking)

            Form {
                CloudConnectionFields(
                    configuration: $configuration, token: $token, hasSavedCredential: hasSavedCredential)
            }
            .formStyle(.grouped)
            .disabled(isWorking)

            HStack {
                Button("应用偏好设置中的默认位置…") { confirmsDefaults = true }
                    .disabled(isWorking).accessibilityIdentifier("sync-apply-defaults")
                Spacer()
                SettingsLink { Text("管理远程设置") }
            }
            Text("位置按作品保存；令牌由本机所有作品共用。切换远程位置将重置同步基线，不会删除旧位置的书稿。")
                .font(.caption).foregroundStyle(.secondary)

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
        .inkPanel()
        .interactiveDismissDisabled(isWorking)
        .confirmationDialog("应用默认远程位置？", isPresented: $confirmsDefaults) {
            Button("应用默认位置") {
                do {
                    let old = configuration
                    var updated = try service.defaultConfiguration(for: provider, projectID: project.id)
                    // Keep the baseline when the destination did not actually change.
                    updated.remoteIdentifier = old.remoteIdentifier
                    updated.remoteRevision = old.remoteRevision
                    updated.baseHashes = old.baseHashes
                    updated.lastSyncedAt = old.lastSyncedAt
                    updated.resetSyncStateIfDestinationChanged(from: old)
                    configuration = updated
                    statusMessage = "默认位置已填入，点击保存连接后生效。"
                } catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("仅替换当前作品的连接草稿；不会自动上传、拉取或删除远程文件。")
        }
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
        token = ""
        hasSavedCredential = false
        configuration = CloudSyncConfiguration(provider: provider)
        do {
            configuration = try service.configuration(for: provider, rootURL: rootURL)
            hasSavedCredential = try !service.token(for: provider).isEmpty
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveConnection() {
        do {
            configuration.provider = provider
            configuration = try service.saveConnection(configuration: configuration, token: token, rootURL: rootURL)
            token = ""
            hasSavedCredential = true
            statusMessage = "连接信息已安全保存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func synchronize(direction: Direction) {
        configuration.provider = provider
        do {
            configuration = try service.saveConnection(configuration: configuration, token: token, rootURL: rootURL)
            token = ""
            hasSavedCredential = true
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
