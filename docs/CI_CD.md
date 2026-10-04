# CI 与内部交付

## 工作流

`.github/workflows/ci.yml` 在 PR、main 推送和手动触发时运行：

1. 固定 `macos-15` 与 `/Applications/Xcode_26.3.app`，打印工具链，严格检查格式。
2. 单元测试、完整 UI 测试在独立 runner 中执行；UI 禁止多个测试进程争抢桌面。
3. 无论测试成败，保留 `.xcresult`（含截图）、原始日志与 JSON 摘要 14 天。
4. 全部测试通过后构建 arm64/x86_64 Release 通用包，验证架构与 ad-hoc 签名，上传 ZIP、
   SHA-256 与内部使用说明。打包失败也保留日志。
5. `macos` 汇总检查只有在所有阶段成功时通过，保留原有分支保护的检查名。

Actions 固定到官方 Node 24 版本的提交，由 Dependabot 提议更新。令牌只有 `contents: read`，
不持久化 checkout 凭据；没有部署秘密、公开 Release、tag 创建或签名证书操作。
PR 新提交会取消旧的 PR 运行，main 不取消正在执行的运行。

Runner 软件清单：[GitHub macOS 15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)。
工具链版本不应自动回退；镜像移除固定 Xcode 后应显式更新并重新验证。

## 原失败原因与回归

- 原 runner 默认 Xcode 16.4，未满足文档的 Xcode 26 基线。
- 闲置保存测试的 70/80 ms `Task.sleep` 不是准确计时：并发负载下恢复可能已晚于 200 ms
  保存期限。现在通过可控单调时钟推进时间，生产仍保持 5 秒闲置保存。
- 导出主线程心跳次数取决于测试调度，不是正确性断言。现在在真实准备、构建、写入阶段
  检查执行线程，同时验证完整大书稿输出；这不是吞吐量基准测试。
- macOS 15 的无障碍树出现嵌套的“笔记与重点”和“返回书架”按钮；现在以专用 identifier
  定位首个匹配项。
- 系统文件选择器关闭“前往文件夹”后，隐藏的路径输入框仍可能存在于无障碍树中。
  封面导入测试等待“打开”按钮可操作，而不要求隐藏输入框从树中消失；仍验证实际导入与保存。

不跳过失败用例，不用 `continue-on-error` 或自动重跑掩盖失败。

## 本地等价命令

```sh
bash scripts/ci.sh lint
bash scripts/ci.sh unit
bash scripts/ci.sh ui
bash scripts/ci.sh package
```

本地使用当前选定的 Xcode；设置 `DEVELOPER_DIR` 可切换到 CI 同版工具链。报告与构建输出
默认放入被 Git 忽略的 `build/ci`。重复执行测试请设置新的 `CI_OUTPUT_DIR`，脚本不会删除旧报告。
本地通过不能替代 GitHub runner 的实际验证，定位失败应先查看对应运行的报告。

目前只做内部产物交付。正式 Developer ID/App Store 签名、公证以及公开发布须另行配置和授权。
