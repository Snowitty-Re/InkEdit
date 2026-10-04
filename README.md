# InkEdit

InkEdit 是面向文学创作者的 macOS 原生 Markdown 写作与阅读应用。正文始终保存在用户选择的普通
Markdown 文件中，应用只负责书籍组织、编辑呈现、阅读批注、出版导出和可选云同步。

## 开发环境

- Xcode 26 或更新版本
- macOS 15 或更新版本
- Swift 6

```sh
xcodebuild \
  -project InkEdit.xcodeproj \
  -scheme InkEdit \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 工程原则

- `.md` 与项目内 `.inkedit` sidecar 是可移植数据，SwiftData 仅作为本机书架索引。
- 所有用户文件写入都必须是原子的，不允许静默覆盖冲突内容。
- OAuth token 只存储在 Keychain，凭据和签名材料不得进入仓库。
- 功能与测试在同一提交中交付，提交消息遵循 Conventional Commits。

更多约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## CI 与内部测试包

PR、main 推送会运行格式检查、单元/UI 测试，再生成可下载的 macOS 通用内部测试包。
测试报告与产物保留 14 天；不会自动公开发布。工作流、下载与签名限制见
[CI/CD 说明](docs/CI_CD.md) 和 [内部测试包说明](docs/INTERNAL_BUILD.md)。

## 云端同步

工作区支持 Google Drive 与 GitHub 私有仓库的手动上传/拉取，并通过基线哈希保留双端修改。
凭据仅存入 macOS Keychain。开发连接方式和冲突策略见 [云端同步说明](docs/CLOUD_SYNC.md)。

发布前请阅读 [隐私说明](PRIVACY.md) 和 [发布检查清单](docs/RELEASE_CHECKLIST.md)。
