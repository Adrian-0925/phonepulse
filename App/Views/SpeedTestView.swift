import SwiftUI

struct SpeedTestView: View {
    @State private var service = SpeedTestService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Text(phaseText)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await service.run() }
                        } label: {
                            Text(service.isRunning ? "测速中…" : "开始测速")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(service.isRunning)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    LabeledContent("延迟", value: service.latencyMs.map { String(format: "%.0f ms", $0) } ?? "--")
                    LabeledContent("下载", value: service.downloadMbps.map(Format.mbps) ?? "--")
                    LabeledContent("上传", value: service.uploadMbps.map(Format.mbps) ?? "--")
                } header: {
                    Text("结果")
                } footer: {
                    Text("一次测速约消耗 35 MB 流量，使用蜂窝网络时请注意。")
                }
            }
            .navigationTitle("测速")
        }
    }

    private var phaseText: String {
        switch service.phase {
        case .idle: "点击下方按钮开始"
        case .latency: "正在测量延迟…"
        case .download: "正在测试下载…"
        case .upload: "正在测试上传…"
        case .finished: "测速完成"
        case .failed(let message): "测速失败：\(message)"
        }
    }
}
