import SwiftUI

struct CloudConnectionFields: View {
    @Binding var configuration: CloudSyncConfiguration
    @Binding var token: String
    var hasSavedCredential = false

    var body: some View {
        if configuration.provider == .github {
            TextField("仓库所有者", text: $configuration.githubOwner).accessibilityIdentifier("remote-github-owner")
            TextField("私有仓库名", text: $configuration.githubRepository).accessibilityIdentifier(
                "remote-github-repository")
            TextField("分支", text: $configuration.githubBranch).accessibilityIdentifier("remote-github-branch")
            SecureField(hasSavedCredential ? "新令牌（留空保留已存凭据）" : "Fine-grained personal access token", text: $token)
                .accessibilityIdentifier("remote-token")
            Text("仅支持私有仓库。令牌需授权此仓库的 Contents 读写与 Metadata 读取权限。")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            TextField(
                "文件夹 ID（可选，留空为我的云端硬盘）",
                text: Binding(
                    get: { configuration.googleDriveFolderID == "root" ? "" : configuration.googleDriveFolderID ?? "" },
                    set: { configuration.googleDriveFolderID = $0.isEmpty ? nil : $0 }
                )
            ).accessibilityIdentifier("remote-drive-folder")
            SecureField(hasSavedCredential ? "新访问令牌（留空保留已存凭据）" : "Google OAuth 访问令牌", text: $token)
                .accessibilityIdentifier("remote-token")
            Text("使用含 drive.file 权限的 OAuth 访问令牌；目标文件夹须已授权给该应用。令牌过期需手动更新，暂不支持浏览器登录或自动续期。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
