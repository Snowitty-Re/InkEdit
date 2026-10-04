# InkEdit 内部测试包

这是通过 CI 测试后生成的 Release 配置通用应用，包含 Apple Silicon（arm64）与 Intel（x86_64）。
它采用 ad-hoc 本地签名，没有 Developer ID 签名、Apple 公证或 App Store 审核，不是正式发布版。

1. 从对应 GitHub Actions 运行的 Artifacts 下载测试包，确认提交号符合预期。
2. 在 ZIP 与 `.sha256` 所在目录运行 `shasum -a 256 -c *.sha256` 校验完整性。
3. 解压后，仅使用备份过的测试书稿验证。macOS 可能因未公证而阻止打开；请按系统的
   “隐私与安全性”提示处理，不要关闭 Gatekeeper 或全局移除安全限制。

本包不含开发者账号、证书、云端令牌或正式书稿。已有 Google Drive 并发覆盖风险尚待修复，
测试时请勿从多台设备同时向同一 Drive 快照上传。

正式交付仍须完成 `docs/RELEASE_CHECKLIST.md` 中的签名、公证与人工验收。
