# PhonePulse

[![iOS Build](https://github.com/Adrian-0925/phonepulse/actions/workflows/ios-build.yml/badge.svg)](https://github.com/Adrian-0925/phonepulse/actions/workflows/ios-build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/iOS-17%2B-black.svg)
![Swift](https://img.shields.io/badge/SwiftUI-Swift%205-orange.svg)

![PhonePulse：iPhone 的网速、充电功率、CPU 一眼看清，切到其他 App 网速还能悬浮显示](docs/cover.png)

把 iPhone 不直接告诉你的状态摆出来：**实时网速**（切到其他 App 也能用画中画悬浮显示）、**充电功率估算**和充电记录、**CPU / 内存 / 存储 / 温控**。看一眼主屏幕小组件、灵动岛或控制中心就知道手机现在怎么样。

原生 SwiftUI，iOS 17+，**只用公开 API**，不联网、不收集任何数据，所有记录只保存在手机本地。

> **English**: PhonePulse is an open-source iOS app (SwiftUI, iOS 17+) that shows live network speed in a Picture-in-Picture floating window, estimated charging power with per-charge reports, and CPU / memory / thermal state in Home Screen widgets, Live Activities and Control Center — using public APIs only, fully offline. The UI and docs are in Chinese for now; issues and PRs in English are welcome.

## 功能

- **悬浮网速窗**：用画中画把上传 / 下载速度悬浮在其他 App 上面，每秒刷新。可以选两行各显示什么（下载 / 上传 / 电量 / CPU）和配色。
- **主屏幕 / 锁屏小组件**：小 / 中 / 大和锁屏三种尺寸，概览、电池、充电、性能、网络等预设，也能自选指标；小组件上有一键刷新，大尺寸带 24 小时电量曲线；适配待机显示。
- **灵动岛 / 锁屏实时活动**：电量、≈功率、充满倒计时、网速、CPU，按插电自动切换重点；展开后有「刷新」「切换」按钮。
- **充电页**：本次充电曲线和估算功率、上次充电报告、「和平时比」快慢、充电习惯、近 7 天汇总和电池保养提醒；横屏充电大屏；充电器 / 线材对比。
- **插电自动记录**：配合快捷指令的「充电器已连接 / 已断开」自动化，App 没开也能记下每次充电的起止时间和电量，并自动开关灵动岛。
- **控制中心按钮**（iOS 18 起）：开关灵动岛、刷新、切换显示内容。
- **真机诊断页**：查看各项读数的原始数据和事件时间线，一键复制诊断报告。

## iOS 能读到什么、读不到什么

iOS 沙盒很严格，安卓上理所当然的功能在 iPhone 上要么做不了，要么只能变通。本项目的原则是：**读不到的不假装读到，估算的一律标「≈」**。

来源说明：**实测** = 实时读取的整机数据；**估算** = 根据实测数据推算；**规格** = 机型静态参数（内置表）；**手动** = 用户从系统设置抄过来；**计算** = 由其他数值算出；**仅本 App** = 只代表 PhonePulse 自己，不是整机。

| 类别 | 参数 | 来源 | 实现方式 / 说明 |
|---|---|---|---|
| 电池 | 剩余电量 % | 实测 | `UIDevice.batteryLevel` |
| | 充电状态、低电量模式 | 实测 | `UIDevice.batteryState`、`ProcessInfo` |
| | 设计容量 mAh | 规格 | 内置机型表 |
| | 最大容量 %（电池健康） | 手动 | ❌ App 读不到，用户从「设置 → 电池 → 电池健康与充电」填写 |
| | 当前满电容量 mAh | 计算 | 设计容量 × 最大容量 % |
| | 剩余电量 mAh | 估算 | 当前满电容量 × 电量 % |
| | 循环次数 | 手动 | ❌ App 读不到，iPhone 15 及以后在「设置 → 通用 → 关于本机」可看到 |
| | 电池温度 | ❌ | 没有公开 API |
| 充电 | 充电 / 耗电速度（%/h） | 估算 | 根据电量变化推算，分「正在采集 → 初步估算 → 较稳定」三步，快充约 1 分钟出初步结果 |
| | 充电功率 W | 估算 | 速度 × 满电容量 × 3.85V，是电池净充入功率，不等于充电头功率 |
| | 预计充满时间 | 估算 | 按当前速度推算；优化充电会在 80% 左右放慢 |
| | 电压、电流、充电协议 | ❌ | 只有私有 API（IOKit），用了会被 App Store 拒绝 |
| CPU | 整机使用率 | 实测 | `host_statistics`；读不到时退回「仅本 App」 |
| | 核心数 | 实测 | `activeProcessorCount` |
| | 频率 | ❌ | 没有公开 API |
| GPU | 使用率 | ❌ | 没有任何公开 API |
| | 芯片型号、GPU 核心数 | 规格 | 内置机型表 |
| 内存 | 总量、已用、可用（整机） | 实测 | `physicalMemory`、`host_statistics64` |
| | App 自身占用 | 仅本 App | `task_info` |
| 存储 | 总容量、可用空间 | 实测 | `URLResourceValues` |
| 网络 | 连接类型 | 实测 | `NWPathMonitor` |
| | 上传 / 下载速度 | 实测 | 网卡流量计数差值；App 打开时每秒，小组件只在刷新时测 1 秒 |
| | 信号强度、运营商名称 | ❌ | 不开放；运营商名称 iOS 16 起返回空 |
| 发热 | 温控状态 | 实测 | `thermalState` 4 档：正常 / 偏高 / 高 / 严重 |
| | 温度数值 | ❌ | 没有公开 API |

**显示位置与刷新**：

| 方式 | 实时性 |
|---|---|
| App 内页面、画中画悬浮窗 | 每秒刷新；悬浮窗开着时 App 在后台继续采集 |
| 灵动岛 / 锁屏实时活动 | App 在前台或悬浮窗开着时跟随每秒采样；App 被挂起后显示最后的数据并标「已暂停」，充满倒计时由系统自己走动 |
| 主屏幕 / 锁屏小组件 | 系统按刷新额度调度，通常 15–60 分钟一次，每次自己读取当下数据；点小组件上的 ⟳ 立即刷新 |
| 修改系统状态栏 | ❌ iOS 不允许 |

iOS 不允许普通 App 在后台一直运行，所以小组件和灵动岛做不到安卓那样的"永远实时"。详细原因和变通办法见 [开发笔记 · 后台运行与刷新](docs/DEVELOPMENT.md#后台运行与刷新)。

## 安装

目前还没有上架 App Store。想自己装到 iPhone 上有两种方式。

### 免费真机安装（不需要 Mac，也不需要付费账号）

用 GitHub Actions 在云端 Mac 上打出未签名的安装包，再在电脑上用 [Sideloadly](https://sideloadly.io) 配合免费 Apple ID 签名安装。适合自己使用和真机测试。

**准备（只做一次）**
1. **Fork 本仓库**，在你的 Fork 里打开 Actions 页面并启用工作流（只有仓库所有者能手动运行工作流）。
2. **专门注册一个新的 Apple ID 用来侧载，不要用主账号**：Sideloadly 是第三方闭源工具，需要输入账号密码。
3. Windows 上从 Apple 官网下载安装 iTunes 和 iCloud（Sideloadly 要求官网版本，不要用 Microsoft Store 版）。
4. 只从 sideloadly.io 官网下载安装 Sideloadly。
5. iPhone 用数据线连电脑，手机上点「信任此电脑」。

**每次安装**
1. 在你的 Fork 里打开 Actions → 左侧选「Sideload IPA」→「Run workflow」。几分钟后在这次运行页面底部下载安装包（下载的是 zip，解压后得到 `PhonePulse-unsigned.ipa`）。
2. 打开 Sideloadly，选择这个 ipa，填入专用 Apple ID，点 Start，按提示输入密码和验证码。
3. 第一次安装后，在 iPhone 上：设置 → 通用 → VPN 与设备管理 → 信任这个 Apple ID；再打开 设置 → 隐私与安全性 → 开发者模式（需要重启）。

**限制**
- 7 天后 App 会无法打开，需要用 Sideloadly 重新安装一次。
- 免费账号最多同时装 3 个侧载 App，每 7 天最多注册 10 个 App ID（本 App 加小组件占 2 个）。
- 免费账号不支持 App Group，小组件读不到 App 里手动填写的电池健康，功率按设计容量估算；App 也读不到小组件记录的电量点。悬浮窗、网速、CPU、电池等主要功能不受影响。
- 如果提示 bundle ID 不可用，在 Sideloadly 高级选项里勾选修改 bundle ID。

### 用 Mac + Xcode 编译

项目用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 描述工程，`.xcodeproj` 不入库：

```bash
brew install xcodegen
xcodegen generate
open PhonePulse.xcodeproj
```

然后在 Xcode 里选择你的 Team（或在 `project.yml` 的 `DEVELOPMENT_TEAM` 填写），连上 iPhone 运行。电量、CPU、网卡流量、画中画在模拟器上没有意义，必须用真机测。

### 改名 / 发布你自己的版本

请换一个名字和 Bundle ID，避免和本项目混淆：全局替换 `PhonePulse`、`io.github.adrian-0925.phonepulse`、`group.io.github.adrian-0925.phonepulse`（`project.yml` 和 `Shared/SharedStore.swift`）。封面图 `docs/cover.html` 里的名字也要改，再按文件开头注释里的命令重新导出 `docs/cover.png`。

## 项目结构

```
project.yml              XcodeGen 工程描述（.xcodeproj 由它生成，不入库）
App/                     主 App
  PhonePulseApp.swift    入口：前台开始采样、后台停止；三个标签页（状态 / 充电 / 设置）和充电大屏的弹出
  Metrics/               各项指标采集 + 调度中心 MetricsEngine
  FloatingWindow/        画中画悬浮网速窗
  Charging/              「充电」标签页、充电记录、横屏充电大屏、单次充电报告、配件对比、屏幕方向控制
  Diagnostics/           真机诊断页 + 事件日志
  Views/                 SwiftUI 界面（首页仪表盘、电池详情、首次引导、设置、各种设置指引）
  Assets.xcassets/       App 图标（由 docs/icon.html 导出，不要直接改 PNG）
  PrivacyInfo.xcprivacy  隐私清单
Core/                    纯计算逻辑（网速增量、CPU 占用、功率估算、电量历史、容量、充电记录与结论），不碰系统 API，有单元测试
Shared/                  App、小组件、测试共用：数据模型、App Group 存储、格式化
Platform/                App 和小组件共用、需要系统框架的部分：系统读数、机型规格、视觉风格、
                         指标展示规则、灵动岛数据与开关、快捷指令 / 按钮意图
                         （只在 App 进程运行的代码用 #if !WIDGET_EXTENSION 排除出小组件）
Widget/                  主屏幕 / 锁屏小组件、灵动岛界面、控制中心按钮（iOS 18）
Tests/                   Core 和 Shared 的单元测试
.github/workflows/       云端编译 + 测试（iOS Build），手动打未签名安装包（Sideload IPA）
docs/                    开发笔记、封面图和图标的源文件
```

**数据流**：
- App 打开时：`各 Monitor` → `MetricsEngine`（每秒采样，唯一数据源）→ 界面、悬浮窗、灵动岛（`LiveActivityService` 按节奏推送）、充电记录（`ChargeSessionStore`）。
- 小组件刷新时：`WidgetSampler` 自己读取电量、存储、内存、温控，CPU 和网速测 1 秒，电量历史存在小组件自己的存储里。

**悬浮窗原理**：iOS 不允许 App 在别的 App 上面画东西，但允许画中画播放视频。`SpeedFrameRenderer` 每秒把网速画成一帧图像，送进 `AVSampleBufferDisplayLayer`，再由 `AVPictureInPictureController` 显示。画中画开着时系统让 App 在后台继续运行。

## 测试与验证

| 层次 | 能证明什么 | 怎么做 |
|---|---|---|
| 云端编译 | 代码能编译，App 和小组件都打包出来了，Info.plist、隐私清单、图标生效 | 每次 push / PR 自动运行 GitHub Actions「iOS Build」 |
| 单元测试 | `Core` 和 `Shared` 的计算正确（网速增量含回绕、CPU 占用、功率估算、充电记录与结论、格式化等） | 同上，在模拟器上运行 |
| 真机验证 | 实际功能是否正常 | 装到 iPhone 上，按 [开发笔记](docs/DEVELOPMENT.md) 里各功能的验收清单操作；设置 → 开发者 → 真机诊断 可复制诊断报告 |

## 文档

- [开发笔记](docs/DEVELOPMENT.md)：每个功能的设计说明、取舍原因、真机验收清单、App Store 注意事项和路线图
- [参与贡献](CONTRIBUTING.md)

## 参与贡献

欢迎提 Issue 和 Pull Request。报告问题时最好附上真机诊断报告（设置 → 开发者 → 真机诊断 → 复制诊断报告）。开发约定和提交前的检查见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[GPL-3.0](LICENSE) © 2026 Adrian

你可以自由使用、修改和再分发本项目，但分发修改后的版本时必须同样以 GPL-3.0 开源并提供源代码。
