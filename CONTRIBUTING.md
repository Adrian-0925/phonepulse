# 参与贡献

感谢你愿意帮忙！提 Issue、改文档、修 Bug、加功能都欢迎。中文英文都可以。

## 报告问题

- 先搜一下有没有相同的 Issue。
- 写清楚机型、iOS 版本、安装方式（侧载 / Xcode），以及复现步骤。
- 最好附上真机诊断报告：App 里 设置 → 开发者 → 真机诊断 →「复制诊断报告」。报告里没有个人信息，但发之前可以自己看一眼。

## 开发环境

- **有 Mac**：`brew install xcodegen && xcodegen generate`，用 Xcode 打开 `PhonePulse.xcodeproj`。
- **没有 Mac**：可以在任何系统上改代码，推到你的 Fork 后由 GitHub Actions「iOS Build」在云端编译并跑单元测试；要装到手机上，手动运行「Sideload IPA」，步骤见 [README](README.md#免费真机安装不需要-mac也不需要付费账号)。

`.xcodeproj`、`Info.plist` 和 `.entitlements` 都由 `project.yml` 生成，不要提交它们；改工程配置请改 `project.yml`。

## 代码约定

- **只用公开 API**。不调用私有 API（例如用 IOKit 读电流电压），不用后台音频、定位等方式"保活"。这些会让 App 无法上架，PR 不会被合并。
- **如实标注数据来源**。估算值前面带「≈」，读不到的数据不要用假数据或猜测值代替；手动填写的数据要标「手动」。
- **不联网、不收集数据**。所有记录只保存在手机本地。
- **分层**：
  - `Core/`：纯计算逻辑，不碰系统 API，必须有单元测试（`Tests/`）。
  - `Shared/`：App、小组件、测试共用的数据模型和格式化。
  - `Platform/`：App 和小组件共用、需要系统框架的代码；只在 App 进程运行的部分用 `#if !WIDGET_EXTENSION` 包起来。
  - `App/`、`Widget/`：界面和各自进程的逻辑。
- 新的计算逻辑尽量放进 `Core/` 并补测试；界面上的用词和现有页面保持一致（例如功率测定状态统一用 `Shared/PowerReadout.swift` 里的说法）。
- 代码风格跟周围代码一致：注释用中文，解释"为什么"而不是"做了什么"。
- 改了 App 图标或封面图，改源文件 `docs/icon.html` / `docs/cover.html` 再导出，不要直接改 PNG。

## 提交 Pull Request

1. Fork 后从 `main` 新建分支。
2. 一个 PR 只做一件事，说明改了什么、为什么改。
3. 确认「iOS Build」通过（编译 + 单元测试）。
4. 涉及真机行为的改动（悬浮窗、灵动岛、小组件、电池读数），写一下你在什么机型和系统上测过；没法真机测也没关系，说明一下即可。
5. 改了功能的话，同步更新 README 或 [开发笔记](docs/DEVELOPMENT.md)。

## 贡献的授权

本项目以 [GPL-3.0](LICENSE) 开源。提交 PR 即表示：

- 你有权提交这些代码（是你自己写的，或来源的许可证允许这样做）；
- 你的贡献以 GPL-3.0 授权给所有人；
- 同时你允许项目作者在 App Store 等渠道发布包含你贡献的版本（App Store 的分发条款和 GPL 存在冲突，没有这项许可，作者就无法上架包含社区贡献的版本）。
