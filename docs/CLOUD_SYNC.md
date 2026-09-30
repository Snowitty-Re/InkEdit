# 云端同步

InkEdit 将一本书作为可移植项目快照同步。快照包含 Markdown、项目元数据、批注和项目内图片，
不包含 `.git`、Finder 元数据或 `.inkedit/cloud-sync.json`。访问凭据只保存在 macOS Keychain。

## GitHub 私有仓库

1. 创建或选择一个私有仓库。
2. 创建 fine-grained personal access token，只授权该仓库，并授予 Contents 读写和 Metadata 读取权限。
3. 在“偏好设置 → GitHub”填写默认所有者、私有仓库名、分支与令牌（不要填仓库网址）。
4. 可以先点“测试连接”：只读取仓库与分支，确认仓库为私有、分支存在；不会上传测试文件，也不证明 Contents 写入权限可用。
5. 点“保存默认设置”。未配置过云端的作品会使用此位置；已有作品可在“云端同步”中明确选择“应用偏好设置中的默认位置”，再保存连接。

新连接在仓库的 `.inkedit/books/<作品 UUID>.zip` 保存快照，避免多本书共用仓库时相互覆盖。
旧连接继续使用 `.inkedit/InkEdit-backup.zip`，不会静默迁移；明确应用新的默认位置会改用按作品隔离的路径。
应用在每次更新前比较 GitHub 文件 SHA。
仓库若为公开仓库，或远端 SHA 已变化，上传会被拒绝。

## Google Drive

在“偏好设置 → Google Drive”保存包含 `https://www.googleapis.com/auth/drive.file` scope 的 OAuth 访问令牌。
可选填文件夹 ID（不是完整链接）；该文件夹必须已授权给令牌所属应用。留空时新快照放在“我的云端硬盘”。
测试连接只查询用户信息及所选文件夹是否可写，不创建文件。
该 scope 只允许应用管理由它创建或用户明确授权的文件。当前没有浏览器登录或令牌自动刷新；
令牌到期后须手动更新。正式接入浏览器 OAuth 仍需配置桌面客户端与授权回调。

Drive 快照使用项目 UUID 写入 `appProperties`，应用只查询自己的项目文件。上传前会比较
`md5Checksum`，避免覆盖其他设备刚上传的版本。
指定文件夹时，创建快照会写入 `parents`，查找快照也会限定该文件夹。

## 凭据和个人设置

- 每个提供商目前共用一份本机凭据；只进入钥匙串，不写入 UserDefaults、作品目录或快照。
- 替换令牌输入框留空会保留已保存的凭据；不会回填旧令牌，避免其他设置窗口误覆盖新凭据。
- “移除凭据”需要确认，会影响本机使用该提供商的全部作品；不删除仓库或 Drive 文件。
- 保存默认位置不代表已测试连接，也不会自动同步；不会重写已有作品配置。
- 更换作品连接的仓库、分支、快照路径或 Drive 文件夹会清空旧同步基线，保留旧远程文件。
- “个人与外观”支持默认作者/笔名、界面外观、阅读配色。笔名只用于新建作品，可逐本修改，不覆盖已有或导入作品作者。

## API 参考

- [GitHub 仓库接口](https://docs.github.com/en/rest/repos/repos#get-a-repository) 与 [分支接口](https://docs.github.com/en/rest/branches/branches#get-a-branch)
- [Google Drive 用户信息](https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get)
- [Google Drive 文件夹与 parents](https://developers.google.com/workspace/drive/api/guides/folder)

## 本地验证

2026-09-30：72 项单元测试通过，偏好设置 → 新建作品笔名 → GitHub / Drive 默认连接的 UI 流程通过，
Release 编译与 Swift Format 严格检查通过。网络行为由模拟客户端验证，未使用真实账号做端到端同步，
也未上传书稿；真实凭据的权限和可用性需在设置中自行测试。

[个人设置截图](settings/profile.png) · [GitHub 设置截图（测试数据）](settings/github.png)

## 冲突策略

- 云端变更而本地未变更：原子更新本地文件。
- 本地和云端同时变更：保留本地版本，并在同一目录生成 `文件名 (云端冲突 日期).md`。
- 远端版本与上次同步修订不一致：阻止上传，要求先拉取。
- 拉取不会根据云端删除本地文件，避免误删尚未同步的手稿。
