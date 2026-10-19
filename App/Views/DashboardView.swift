import SwiftUI

struct DashboardView: View {
    @Environment(MetricsEngine.self) private var engine
    @AppStorage("autoOpenChargingScreen") private var autoOpenChargingScreen = false
    @State private var showsChargingScreen = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot = engine.snapshot {
                    VStack(spacing: 12) {
                        if snapshot.battery.state.isPluggedIn {
                            ChargingCard(battery: snapshot.battery) {
                                showsChargingScreen = true
                            }
                        }
                        LiveActivityCard()
                        NetworkCard(
                            sample: snapshot.network,
                            download: engine.downloadHistory,
                            upload: engine.uploadHistory,
                            capacity: engine.historyLength)
                        FloatingWindowCard()
                        LazyVGrid(columns: columns, spacing: 12) {
                            CPUCard(sample: snapshot.cpu, history: engine.cpuHistory, capacity: engine.historyLength)
                            MemoryCard(sample: snapshot.memory)
                            NavigationLink {
                                BatteryDetailView()
                            } label: {
                                BatteryCard(sample: snapshot.battery)
                            }
                            .buttonStyle(.plain)
                            StorageCard(sample: snapshot.storage)
                        }
                        DeviceCard(snapshot: snapshot)
                    }
                    .padding()
                } else {
                    ProgressView()
                        .padding(.top, 120)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设备状态")
        }
        .fullScreenCover(isPresented: $showsChargingScreen) {
            ChargingScreenView()
                .environment(engine)
        }
        // 设置里打开了「插电时自动打开充电大屏」：App 开着时看到插电就进入
        .onChange(of: ChargeSessionStore.shared.current?.id) { _, newID in
            guard autoOpenChargingScreen, newID != nil, ChargeSessionStore.shared.current?.startObserved == true else { return }
            showsChargingScreen = true
        }
    }
}

// MARK: - 充电

private struct ChargingCard: View {
    let battery: BatterySample
    let onOpenScreen: () -> Void

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        let readout = PowerReadout(battery: battery, now: .now, context: .charging)
        MetricCard(title: battery.state == .full ? "已充满" : "正在充电", systemImage: "bolt.fill", tint: Theme.charging) {
            HStack(alignment: .firstTextBaseline) {
                MetricValue(text: battery.level.map(Format.batteryPercent) ?? "--")
                Spacer()
                if battery.state != .full {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(readout.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(readout.value)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }
            }
            if battery.state != .full {
                HStack(spacing: 6) {
                    PowerStatusBadge(readout: readout)
                    Text(readout.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if let session = store.current, session.samples.count >= 2 {
                ChargeCurveChart(samples: session.samples, tint: Theme.storage, showsAxes: false)
                    .frame(height: 56)
            }
            if let session = store.current {
                HStack(spacing: 8) {
                    AccessoryPicker(sessionID: session.id, compact: true)
                    Spacer(minLength: 0)
                    LastAccessorySuggestion(sessionID: session.id)
                }
            }
            HStack(spacing: 10) {
                Button(action: onOpenScreen) {
                    Label("充电大屏", systemImage: "rectangle.landscape.rotate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.charging)
                .foregroundStyle(.black)
                NavigationLink {
                    ChargeHistoryView()
                } label: {
                    Label("充电记录", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - 网络

private struct NetworkCard: View {
    let sample: NetworkSample
    let download: [Double]
    let upload: [Double]
    let capacity: Int

    var body: some View {
        MetricCard(title: "网络 · \(sample.connection.label)", systemImage: "arrow.up.arrow.down", tint: .blue) {
            HStack(spacing: 32) {
                speed("下载", value: sample.downloadBytesPerSecond, color: .blue, systemImage: "arrow.down")
                speed("上传", value: sample.uploadBytesPerSecond, color: .orange, systemImage: "arrow.up")
            }
            Sparkline(series: [
                SparklineSeries(id: "download", values: download, color: .blue),
                SparklineSeries(id: "upload", values: upload, color: .orange),
            ], capacity: capacity)
            .frame(height: 60)
            Text("本次统计  Wi-Fi \(Format.bytes(sample.sessionWifiBytes))  ·  蜂窝 \(Format.bytes(sample.sessionCellularBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func speed(_ title: String, value: Double, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            MetricValue(text: Format.speed(value))
        }
    }
}

// MARK: - 灵动岛

private struct LiveActivityCard: View {
    @State private var errorMessage: String?

    private var service: LiveActivityService { .shared }

    var body: some View {
        MetricCard(title: "灵动岛", systemImage: "capsule.fill", tint: Theme.charging) {
            Picker("重点显示", selection: Binding(get: { service.focus }, set: { service.setFocus($0) })) {
                ForEach(LiveActivityFocus.allCases, id: \.self) { focus in
                    Text(focus.label).tag(focus)
                }
            }
            .pickerStyle(.segmented)
            Button {
                Task {
                    do {
                        try await service.toggle()
                        errorMessage = nil
                    } catch {
                        errorMessage = "无法开启：\(error.localizedDescription)"
                    }
                }
            } label: {
                Label(service.isRunning ? "关闭灵动岛" : "开启灵动岛", systemImage: service.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(service.isRunning ? .gray : Theme.charging)
            .foregroundStyle(service.isRunning ? .white : .black)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ControlCenterTip()
        }
    }

    private var caption: String {
        if let errorMessage { return errorMessage }
        if !service.areActivitiesEnabled { return "实时活动已被关闭：请到 设置 → PhonePulse → 实时活动 打开" }
        if DeviceCatalog.current?.hasDynamicIsland == false { return "你的机型没有灵动岛，会显示在锁屏上" }
        return "自动：插电时显示电量和充电，否则显示网速。App 在前台或悬浮窗开着时实时刷新，其他时候显示最后一次的数据。"
    }
}

// MARK: - 悬浮窗

private struct FloatingWindowCard: View {
    @Environment(FloatingSpeedController.self) private var floating

    var body: some View {
        MetricCard(title: "悬浮网速窗", systemImage: "pip", tint: .indigo) {
            // 这就是画中画的视频源，必须显示在界面上才能开启悬浮窗
            SampleBufferPreview(view: floating.sourceView)
                .aspectRatio(SpeedFrameRenderer.size.width / SpeedFrameRenderer.size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                floating.toggle()
            } label: {
                Label(floating.isActive ? "关闭悬浮窗" : "开启悬浮窗", systemImage: floating.isActive ? "pip.exit" : "pip.enter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(!floating.isSupported || (!floating.isActive && !floating.isPossible))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle(isOn: Binding(get: { floating.showsOutsideApp }, set: { floating.setShowsOutsideApp($0) })) {
                Text("离开 App 时显示悬浮窗")
                    .font(.subheadline)
            }
            .tint(.indigo)
            Text(floating.showsOutsideApp
                 ? "回到桌面或切到其他 App 时继续显示。App 因此能在后台运行，灵动岛也会保持实时。不想挡住画面，可以把悬浮窗拖到屏幕边缘收起。"
                 : "离开 App 时悬浮窗会收起。App 随后会被系统暂停，灵动岛停在最后一次的数据（显示「已暂停」，充满倒计时仍会走）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { floating.prepare() }
    }

    private var caption: String {
        if let error = floating.errorMessage { return error }
        if !floating.isSupported { return "此设备不支持画中画" }
        if floating.isActive { return "悬浮窗已开启，切到其他 App 也能看到网速" }
        return floating.isPossible ? "开启后切到其他 App，网速会一直悬浮显示（原型）" : "正在准备画中画…"
    }
}

// MARK: - CPU / 内存 / 电池 / 存储

private struct CPUCard: View {
    let sample: CPUSample?
    let history: [Double]
    let capacity: Int

    var body: some View {
        MetricCard(title: "CPU", systemImage: "cpu", tint: .purple) {
            MetricValue(text: sample.map { Format.percent($0.usage) } ?? "--")
            Sparkline(series: [SparklineSeries(id: "cpu", values: history, color: .purple)], capacity: capacity, yMax: 1)
                .frame(height: 32)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        guard let sample else { return "采样中…" }
        return sample.isSystemWide ? "\(sample.coreCount) 核 · 整机" : "仅本 App"
    }
}

private struct MemoryCard: View {
    let sample: MemorySample?

    var body: some View {
        MetricCard(title: "内存", systemImage: "memorychip", tint: .green) {
            if let sample {
                MetricValue(text: Format.percent(sample.usedFraction))
                ProgressView(value: sample.usedFraction)
                    .tint(.green)
                Text("\(Format.bytes(sample.usedBytes)) / \(Format.bytes(sample.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                MetricValue(text: "--")
            }
        }
    }
}

private struct BatteryCard: View {
    let sample: BatterySample

    var body: some View {
        MetricCard(title: "电池", systemImage: icon, tint: sample.state == .charging ? .green : .yellow) {
            MetricValue(text: sample.level.map(Format.batteryPercent) ?? "--")
            Text(sample.isLowPowerMode ? "\(sample.state.label) · 低电量模式" : sample.state.label)
                .font(.subheadline)
            Text(powerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        sample.state == .charging ? "battery.100percent.bolt" : "battery.75percent"
    }

    private var powerText: String {
        let readout = PowerReadout(battery: sample, now: .now)
        switch readout.status {
        case .noData: return "当前设备不支持"
        case .full: return "已充满"
        case .collecting: return "\(readout.title) · 正在采集"
        case .preliminary, .stable, .slowed, .disconnected:
            let suffix = sample.capacityMAh == nil ? "（未收录容量）" : ""
            return "\(readout.title) \(readout.value) · \(readout.label)\(suffix)"
        }
    }
}

private struct StorageCard: View {
    let sample: StorageSample?

    var body: some View {
        MetricCard(title: "存储", systemImage: "internaldrive", tint: .teal) {
            if let sample {
                MetricValue(text: Format.bytes(sample.availableBytes))
                ProgressView(value: sample.usedFraction)
                    .tint(.teal)
                Text("可用 / 共 \(Format.bytes(sample.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                MetricValue(text: "--")
            }
        }
    }
}

// MARK: - 设备

private struct DeviceCard: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        MetricCard(title: "设备", systemImage: "iphone", tint: .gray) {
            LabeledContent("机型", value: DeviceCatalog.displayName)
            if let model = DeviceCatalog.current {
                LabeledContent("芯片", value: "\(model.chip) · \(model.gpuCores) 核 GPU")
            }
            LabeledContent("系统", value: "iOS \(UIDevice.current.systemVersion)")
            LabeledContent("温度状态", value: snapshot.thermal.label)
            if let footprint = snapshot.memory?.appFootprintBytes {
                LabeledContent("本 App 内存", value: Format.bytes(footprint))
            }
        }
        .font(.subheadline)
    }
}
