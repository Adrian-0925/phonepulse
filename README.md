# PhonePulse（暂定名）

iPhone 设备状态监测 App：实时网速、充电功率（估算）、CPU、内存、存储、温度状态，一屏看完。

## 先说清楚：iOS 能做什么、不能做什么

iOS 沙盒很严格，安卓上理所当然的功能在 iPhone 上要么做不了，要么只能变通。产品设计和宣传都要以此为准，否则会被审核拒绝，或被用户差评。

### 数据可行性

| 指标 | 能否做到 | 实现方式 | 备注 |
|---|---|---|---|
| 实时网速（上/下行） | ✅ App 在前台时 | `getifaddrs` 读网卡累计字节，每秒求差 | 退到后台后系统会暂停 App，无法持续采样 |
| 主动测速 | ✅ | URLSession 下载/上传计时 | 需要自建测速节点 |
| 网络类型 | ✅ | `NWPathMonitor` | Wi-Fi / 蜂窝 / 有线 |
| CPU 占用 | ⚠️ 需真机验证 | `host_statistics(HOST_CPU_LOAD_INFO)` | 若被沙盒限制，自动退化为"仅本 App" |
| 内存 | ✅ | `host_statistics64` + `task_info` | |
| 电量 / 充电状态 / 低电量模式 | ✅ | `UIDevice` / `ProcessInfo` | |
| 充电功率 | ⚠️ 只能估算 | 电量变化速度 × 电池容量 × 3.85V | 没有公开的电流/电压 API；需采样几分钟；界面必须标"估算" |
| 电池健康 / 循环次数 | ❌ App 内做不到 | 只有私有 API | 可考虑做电脑端 USB 读取作为增值方案 |
| 存储空间 | ✅ | `URLResourceValues` | |
| 温度 | ⚠️ 只有档位 | `ProcessInfo.thermalState` | 正常/偏高/高/严重 4 档，没有摄氏度 |

### 显示位置

| 方式 | 实时性 | 状态 |
|---|---|---|
| App 内仪表盘 | 每秒刷新 | ✅ 已搭好 |
| 桌面 / 锁屏小组件 | 由系统调度，约 15 分钟以上一次 | ✅ 已搭好，显示上次打开 App 时的数据 |
| 灵动岛 / 实时活动 | App 在前台时可实时更新，后台基本不行 | Phase 2 |
| 画中画悬浮窗 | 可实时，最接近安卓的悬浮网速 | Phase 2，审核有风险，国区已有同类上架 |
| 修改系统状态栏 | ❌ | iOS 不允许 |

> 结论：App 内仪表盘 + 小组件是稳妥的基本盘；真正能对标"安卓状态栏网速"的是**画中画悬浮窗**，它是差异化卖点，也是审核风险点，Phase 2 先做原型验证。
> 国区 App Store 已有不少同类产品（搜"网速""悬浮窗""电池"），要靠体验和悬浮窗做出差异。

## 项目结构

```
project.yml              XcodeGen 工程描述（.xcodeproj 由它生成，不入库）
App/                     主 App
  PhonePulseApp.swift    入口：前台开始采样、后台停止
  Metrics/               各项指标采集 + 调度中心 MetricsEngine
  SpeedTest/             主动测速
  Views/                 SwiftUI 界面
  PrivacyInfo.xcprivacy  隐私清单
Shared/                  App 与小组件共用：数据模型、App Group 存储、格式化
Widget/                  桌面 / 锁屏小组件
.github/workflows/       云端 macOS 编译
```

数据流：`各 Monitor` → `MetricsEngine`（每秒采样，保留 60 秒曲线）→ 界面；同时每 30 秒和退到后台时把快照写进 App Group → 小组件读取。

## 怎么编译

iOS App 只能在 macOS + Xcode 上编译。在 Windows 上开发有三条路：

1. **GitHub Actions（免费，先用这个）**：把项目推到 GitHub，每次 push 会在云端 Mac 上自动编译，能确认代码没写错，但装不到手机上。
2. **云 Mac**（MacinCloud 等，按小时租）：编译后上传 TestFlight，再装到自己的 iPhone 上。
3. **买或借一台 Mac**（二手 M1 Mac mini 就够）：最顺手，可以直接连 iPhone 调试。

在 Mac 上：

```bash
brew install xcodegen
xcodegen generate
open PhonePulse.xcodeproj
```

然后在 Xcode 里选择你的 Team，连上 iPhone 运行。很多指标（电量、CPU、网卡流量）在模拟器上没有意义，必须用真机测。

装真机 / 上架需要 Apple Developer 账号（99 美元/年），小组件读主 App 数据用的 App Group 也需要它。

**改名**：全局替换 `PhonePulse`、`com.example.phonepulse`、`group.com.example.phonepulse`（`project.yml` 和 `Shared/SharedStore.swift`）。

## 上架注意事项

- 充电功率必须标注"估算"，不要宣传"精准测量充电瓦数"。
- 不要用后台音频、定位等模式"保活"来实现后台实时刷新，会被拒。
- 不要调用私有 API（例如用 IOKit 读电流电压），会被拒。
- 测速节点：`SpeedTestEndpoints.development` 用的是 Cloudflare 的公共地址，只能开发调试用，上线前换成自己的节点（国内用户用国内 CDN）。
- 隐私清单 `PrivacyInfo.xcprivacy` 已声明用到的"需说明原因的 API"（磁盘空间、系统启动时间、UserDefaults）。

## 路线图

- [x] **Phase 1 框架**：采集层、仪表盘、小组件、基础测速
- [ ] **真机验证**：CPU 整机数据能否读取；电量是 1% 还是 5% 步进；功率估算和 USB 电流表对比的误差
- [ ] **Phase 2 差异化**：画中画悬浮网速窗、灵动岛实时活动、每日/每月流量统计、充电曲线记录
- [ ] **Phase 3 变现**：StoreKit 2 内购（基础功能免费，悬浮窗 / 历史曲线 / 更多小组件样式付费）
- [ ] **上架准备**：App 图标、多语言、截图、隐私政策页面
