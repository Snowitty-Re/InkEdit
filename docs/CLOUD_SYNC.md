# 云端同步

InkEdit 将一本书作为可移植项目快照同步。快照包含 Markdown、项目元数据、批注和项目内图片，
不包含 `.git`、Finder 元数据或 `.inkedit/cloud-sync.json`。访问凭据只保存在 macOS Keychain。

## GitHub 私有仓库

1. 创建或选择一个私有仓库。
2. 创建 fine-grained personal access token，只授权该仓库，并授予 Contents 读写和 Metadata 读取权限。
3. 在书籍工作区打开“云端同步”，填写所有者、仓库、分支和令牌。

应用会在仓库的 `.inkedit/InkEdit-backup.zip` 保存快照，并在每次更新前比较 GitHub 文件 SHA。
仓库若为公开仓库，或远端 SHA 已变化，上传会被拒绝。

## Google Drive

当前开发版本接受包含 `https://www.googleapis.com/auth/drive.file` scope 的 OAuth 访问令牌。
该 scope 只允许应用管理由它创建或用户明确授权的文件。令牌到期后需在同步面板中重新连接；发布版本
应接入已审核的桌面 OAuth 客户端，通过系统浏览器获取并刷新令牌。

Drive 快照使用项目 UUID 写入 `appProperties`，应用只查询自己的项目文件。上传前会比较
`md5Checksum`，避免覆盖其他设备刚上传的版本。

## 冲突策略

- 云端变更而本地未变更：原子更新本地文件。
- 本地和云端同时变更：保留本地版本，并在同一目录生成 `文件名 (云端冲突 日期).md`。
- 远端版本与上次同步修订不一致：阻止上传，要求先拉取。
- 拉取不会根据云端删除本地文件，避免误删尚未同步的手稿。
