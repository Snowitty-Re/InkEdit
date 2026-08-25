# 贡献规范

## 分支与提交

提交消息采用 `type(scope): summary` 格式。常用类型为 `feat`、`fix`、`refactor`、`test`、`docs`、
`chore`。每个提交只包含一个可验证的功能小节，并保持工程可构建、测试可运行。

## Swift 代码

- 使用 Swift 6 并处理并发隔离，不通过关闭检查规避告警。
- UI 状态留在 MainActor；文件、解析、导出和网络工作使用明确的异步边界。
- 优先使用值类型和协议隔离外部系统；用户可见错误必须可恢复。
- 新增行为同时补充 Swift Testing 单元测试；主要用户流程补充 UI 测试。

提交前运行：

```sh
xcrun swift-format lint --recursive InkEdit InkEditTests InkEditUITests
xcodebuild test \
  -project InkEdit.xcodeproj \
  -scheme InkEdit \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

