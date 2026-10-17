import Foundation
import Observation

/// 保存充电记录。App 每次采样时喂给记录器，拔电时生成一条完整记录。
/// 数据只存在 App 自己的目录里（Application Support/ChargeSessions.json），不上传。
///
/// 限制：App 只在运行时能看到电量。免费账号没有 App Group，读不到小组件记录的电量点，
/// 所以 App 关闭期间的充电过程补不上，报告里用「数据完整度」如实标出。
@MainActor
@Observable
final class ChargeSessionStore {
    static let shared = ChargeSessionStore()

    /// 正在进行的充电
    private(set) var current: ChargeSession?
    /// 已结束的充电，最新的在前
    private(set) var sessions: [ChargeSession] = []

    @ObservationIgnored private var recorder = ChargeSessionRecorder()
    @ObservationIgnored private var lastSave: Date = .distantPast
    private let maxSessions = 200

    private struct Stored: Codable {
        var recorder: ChargeSessionRecorder
        var sessions: [ChargeSession]
    }

    private init() {
        load()
    }

    /// App 每次采样后调用
    func record(_ snapshot: MetricsSnapshot) {
        let battery = snapshot.battery
        if let finished = recorder.record(level: battery.level, state: battery.state, at: snapshot.timestamp, capacityMAh: battery.capacityMAh) {
            keep(finished)
            save()
        }
        if recorder.current != current {
            if current == nil, let started = recorder.current {
                EventLog.shared.add(started.startObserved ? "开始记录充电（看到了插电）" : "开始记录充电（App 打开时已在充电）")
            }
            current = recorder.current
        }
        if Date.now.timeIntervalSince(lastSave) >= 60 {
            save()
        }
    }

    func delete(_ session: ChargeSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    func save() {
        lastSave = .now
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(Stored(recorder: recorder, sessions: sessions)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func keep(_ session: ChargeSession) {
        // 插上马上又拔掉的不算一次充电
        let span = (session.samples.last?.time ?? session.startDate).timeIntervalSince(session.startDate)
        let gained = (session.samples.last?.level ?? 0) - (session.samples.first?.level ?? 0)
        guard span >= 2 * 60 || gained >= 0.01 else { return }
        sessions.insert(session, at: 0)
        if sessions.count > maxSessions {
            sessions.removeLast(sessions.count - maxSessions)
        }
        EventLog.shared.add("充电记录已保存：\(Format.percent(session.samples.first?.level ?? 0)) → \(Format.percent(session.samples.last?.level ?? 0))")
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        recorder = stored.recorder
        sessions = stored.sessions
        current = stored.recorder.current
    }

    private static let fileURL: URL? = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ChargeSessions.json")
    }()
}
