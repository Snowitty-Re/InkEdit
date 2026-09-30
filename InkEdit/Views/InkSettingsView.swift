import SwiftUI

struct InkSettingsView: View {
    @AppStorage("inkedit.appearance") private var appearance = InkAppearance.system
    @AppStorage("inkedit.readerTheme", store: AppPreferences.defaults) private var readerTheme = ReaderTheme.sepia
    @State private var penName = ""
    @State private var profileSaved = false

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image("InkMark").resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("你的写作身份").font(InkTheme.editorial(26))
                        Text("让写作回归文字本身。").foregroundStyle(InkTheme.muted)
                    }
                }
                Form {
                    TextField("默认作者 / 笔名", text: $penName).accessibilityIdentifier("settings-pen-name")
                    Text("用于新建作品，可在创建时修改。不会覆盖已有作品的作者，也不会改写导入项目。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("界面外观", selection: $appearance) {
                        ForEach(InkAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("阅读配色", selection: $readerTheme) {
                        ForEach(ReaderTheme.allCases) { Text($0.title).tag($0) }
                    }
                }
                HStack {
                    if profileSaved { Label("个人资料已保存", systemImage: "checkmark.circle").foregroundStyle(InkTheme.sage) }
                    Spacer()
                    Button("保存个人资料") {
                        penName = penName.trimmingCharacters(in: .whitespacesAndNewlines)
                        AppPreferences.defaults.set(penName, forKey: AppPreferences.penNameKey)
                        profileSaved = true
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("settings-save-profile")
                }
                Spacer(minLength: 0)
            }
            .padding(28)
            .tabItem { Label("个人与外观", systemImage: "person.crop.circle") }

            RemoteSettingsView(provider: .googleDrive)
                .tabItem { Label("Google Drive", systemImage: "externaldrive.badge.icloud") }
            RemoteSettingsView(provider: .github)
                .tabItem { Label("GitHub", systemImage: "shippingbox") }
        }
        .frame(width: 640, height: 520).inkPanel()
        .preferredColorScheme(appearance.colorScheme)
        .onAppear { penName = AppPreferences.penName() }
        .onChange(of: penName) { _, value in
            if value != AppPreferences.penName() { profileSaved = false }
        }
    }
}

private struct RemoteSettingsView: View {
    let provider: CloudProvider
    @State private var configuration = CloudSyncConfiguration(provider: .github)
    @State private var token = ""
    @State private var hasCredential = false
    @State private var isWorking = false
    @State private var loaded = false
    @State private var message: String?
    @State private var error: String?
    @State private var confirmsRemoval = false
    @State private var validationTask: Task<Void, Never>?
    private let service = RemoteSettingsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(provider.title).font(InkTheme.editorial(26))
            Text("凭据由本机所有作品共用，安全保存在钥匙串。默认位置仅用于尚未配置的作品；已有作品需手动应用默认设置。")
                .font(.callout).foregroundStyle(InkTheme.muted)
            Form {
                CloudConnectionFields(configuration: $configuration, token: $token, hasSavedCredential: hasCredential)
            }.formStyle(.grouped)
            Label(hasCredential ? "钥匙串中已有凭据（不代表已验证连接）" : "尚未保存凭据", systemImage: "key")
                .font(.caption).foregroundStyle(InkTheme.muted)
            if let message { Text(message).font(.callout).foregroundStyle(InkTheme.sage) }
            HStack {
                Button("移除凭据", role: .destructive) { confirmsRemoval = true }
                    .disabled(!hasCredential).accessibilityIdentifier("settings-remove-credential")
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("测试连接") { testConnection() }.accessibilityIdentifier("settings-test-connection")
                Button("保存默认设置") { save() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("settings-save-remote")
            }
            .disabled(!loaded || isWorking)
        }
        .padding(28)
        .disabled(isWorking)
        .onAppear { load() }
        .onDisappear { validationTask?.cancel() }
        .onChange(of: configuration) { _, _ in message = nil }
        .onChange(of: token) { _, value in if !value.isEmpty { message = nil } }
        .confirmationDialog("移除 \(provider.title) 凭据？", isPresented: $confirmsRemoval) {
            Button("移除凭据", role: .destructive) {
                do {
                    try service.removeCredential(for: provider)
                    hasCredential = false
                    token = ""
                    message = "本机凭据已移除，远程书稿和仓库未被删除。"
                } catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("使用该服务的所有作品将无法同步，直到重新配置令牌。不会删除任何云端文件。")
        }
        .alert("远程设置", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func load() {
        do {
            configuration = try service.configuration(for: provider)
            hasCredential = try service.hasCredential(for: provider)
            loaded = true
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            try service.save(configuration, replacementToken: token)
            hasCredential = try service.hasCredential(for: provider)
            token = ""
            message = "默认配置已保存；未执行同步或连接测试。"
        } catch { self.error = error.localizedDescription }
    }

    private func testConnection() {
        do {
            let credential = try service.token(for: provider, replacement: token)
            let draft = try configuration.normalized()
            isWorking = true
            message = nil
            validationTask = Task {
                defer { isWorking = false }
                do {
                    let result = try await RemoteConnectionValidator().validate(configuration: draft, token: credential)
                    guard !Task.isCancelled else { return }
                    message = result
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}
