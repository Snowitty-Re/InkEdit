# InkEdit 隐私说明

InkEdit 采用本地优先设计。书稿、项目元数据和批注默认只保存在用户选择的文件夹中，书架索引保存在
本机应用容器。应用不包含分析 SDK、广告 SDK，也不会把书稿发送给 InkEdit 开发者。

只有用户主动点击云端上传或拉取时，应用才会访问网络：

- GitHub：访问用户指定的私有仓库，读取仓库隐私状态并读写项目快照。
- Google Drive：使用 `drive.file` 权限读写由 InkEdit 创建或用户明确授权的项目快照。

GitHub token 与 Google OAuth token 存储在 macOS Keychain，不写入书稿、项目 sidecar、日志或 Git
仓库。`.inkedit/cloud-sync.json` 只保存远端文件标识、修订号和文件哈希。

用户可以在 macOS 系统设置中撤销应用文件权限，在 GitHub 或 Google 账户设置中撤销云端授权。
从书架移除书籍只删除本机索引，不删除原始书稿或云端快照。
