# 发布检查清单

## 构建与质量

- [ ] `xcrun swift-format lint --recursive InkEdit InkEditTests InkEditUITests`
- [ ] Debug 与 Release 配置无编译警告。
- [ ] 完整单元测试与关键 UI 测试通过。
- [ ] 新建、文件/文件夹导入、自动保存、阅读批注均通过中文路径手工验证。
- [ ] HTML、PDF、EPUB、DOCX 在至少两种阅读/办公应用中打开验证。

## 数据安全

- [ ] 沙盒只包含用户选择文件、书签、Keychain 和客户端网络权限。
- [ ] 仓库中不存在 token、OAuth client secret、签名证书或测试书稿。
- [ ] 云端双改会生成冲突副本，远端修订变化会阻止覆盖上传。
- [ ] 升级旧版 `.inkedit` schema 前保留可恢复备份。

## 云端与发布

- [ ] Google 桌面 OAuth 客户端、同意屏幕、`drive.file` scope 和令牌刷新完成发布配置。
- [ ] GitHub fine-grained token 权限文案与私有仓库校验通过真实账户验证。
- [ ] 更新版本号、隐私说明、支持链接和 App Store 元数据。
- [ ] 使用 Developer ID/App Store Distribution 签名，并完成 notarization 或 App Store 上传检查。
