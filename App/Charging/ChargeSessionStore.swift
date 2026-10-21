import Foundation
import Observation

/// 保存充电记录和配件组合。App 每次采样时喂给记录器，拔电时生成一条完整记录。
/// 数据只存在 App 自己的目录里（Application Support/ChargeSessions.json），不上传。
///
/// 限制：App 只在运行时能看到电量。免费账号没有 App Group，读不到小组件记录的电量点，
/// 所以 App 关闭期间的充电过程补不上，报告里用「数据完整度」如实标出。
@MainActor
@Observable
final class ChargeSessionStore {
    static let shared = ChargeSessionStore()
    /// 设置项：新的一次充电自动沿用上次的配件组合
    nonisolated static let autoAssignKey = "autoAssignLastAccessory"
    /// 快捷指令自动化（插电 / 拔电）最近一次运行的时间
    nonisolated static let automationRunKey = "lastChargerAutomationRun"

    /// 正在进行的充电
    private(set) var current: ChargeSession?
    /// 已结束的充电，最新的在前
    private(set) var sessions: [ChargeSession] = []
    /// 配件组合
    private(set) var book = AccessoryBook()
    /// 快捷指令自动化最近一次运行的时间；nil 表示还没设置过（充电页据此显示设置提示）
    private(set) var lastAutomationRun: Date?

    @ObservationIgnored private var recorder = ChargeSessionRecorder()
    @ObservationIgnored private var lastSave: Date = .distantPast
    private let maxSessions = 200

    private struct Stored: Codable {
        var recorder: ChargeSessionRecorder
        var sessions: [ChargeSession]
        /// 旧版本没有这一项
        var book: AccessoryBook?
    }

    private init() {
        lastAutomationRun = UserDefaults.standard.object(forKey: Self.automationRunKey) as? Date
        load()
    }

    // MARK: - 快捷指令自动化

    /// 「充电器已连接」自动化：记下插电的确切时间和电量。App 只是被系统短暂唤醒，所以马上保存
    func chargerConnected(level: Double?, capacityMAh: Int?, thermal: ThermalLevel) {
        let previousID = recorder.current?.id
        if let finished = recorder.recordPlugIn(level: level, at: .now, capacityMAh: capacityMAh, thermal: thermal) {
            keep(finished)
        }
        if let started = recorder.current, started.id != previousID {
            EventLog.shared.add("快捷指令：插电，开始记录充电")
            carryLastAccessory()
        } else {
            EventLog.shared.add("快捷指令：插电（这次充电已在记录）")
        }
        current = recorder.current
        markAutomationRun()
        save()
    }

    /// 「充电器已断开」自动化：以这一刻结束正在进行的充电
    func chargerDisconnected(level: Double?) {
        if let finished = recorder.recordUnplug(level: level, at: .now) {
            keep(finished)
            EventLog.shared.add("快捷指令：拔电，充电记录已结束")
        } else {
            EventLog.shared.add("快捷指令：拔电（没有正在记录的充电）")
        }
        current = recorder.current
        markAutomationRun()
        save()
    }

    private func markAutomationRun() {
        let now = Date.now
        lastAutomationRun = now
        UserDefaults.standard.set(now, forKey: Self.automationRunKey)
    }

    /// App 每次采样后调用
    func record(_ snapshot: MetricsSnapshot) {
        let battery = snapshot.battery
        if let finished = recorder.record(level: battery.level, state: battery.state, at: snapshot.timestamp,
                                          capacityMAh: battery.capacityMAh, thermal: snapshot.thermal) {
            keep(finished)
            save()
        }
        if recorder.current != current {
            if current == nil, let started = recorder.current {
                EventLog.shared.add(started.startObserved ? "开始记录充电（看到了插电）" : "开始记录充电（App 打开时已在充电）")
                carryLastAccessory()
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

    func session(_ id: UUID) -> ChargeSession? {
        if let current, current.id == id { return current }
        return sessions.first { $0.id == id }
    }

    // MARK: - 配件组合

    func accessory(_ id: UUID?) -> AccessoryProfile? {
        id.flatMap(book.profile)
    }

    /// 某个组合的记录（已结束的）
    func sessions(for accessoryID: UUID) -> [ChargeSession] {
        sessions.filter { $0.accessoryID == accessoryID }
    }

    /// 把一条记录（正在充电的也可以）关联到配件组合；nil 表示取消关联
    func assign(_ accessoryID: UUID?, to sessionID: UUID) {
        if recorder.current?.id == sessionID {
            recorder.assignAccessory(accessoryID)
            current = recorder.current
        } else if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].accessoryID = accessoryID
        } else {
            return
        }
        if let accessoryID {
            book.markUsed(accessoryID)
            EventLog.shared.add("充电记录关联配件：\(book.profile(accessoryID)?.name ?? "")")
        }
        save()
    }

    /// 新建组合；传了 sessionID 就顺便关联上
    @discardableResult
    func createAccessory(named name: String, assigningTo sessionID: UUID? = nil) -> AccessoryProfile? {
        guard let profile = book.add(name: name, at: .now) else { return nil }
        if let sessionID {
            assign(profile.id, to: sessionID)
        } else {
            save()
        }
        return profile
    }

    @discardableResult
    func renameAccessory(_ id: UUID, to name: String) -> Bool {
        guard book.rename(id, to: name) else { return false }
        save()
        return true
    }

    /// 删除组合：记录保留，改回「未指定」
    func deleteAccessory(_ id: UUID) {
        book.remove(id)
        sessions = sessions.unlinking(accessory: id)
        if recorder.current?.accessoryID == id {
            recorder.assignAccessory(nil)
            current = recorder.current
        }
        save()
    }

    // MARK: - 存储

    func save() {
        lastSave = .now
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(Stored(recorder: recorder, sessions: sessions, book: book)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 设置里打开了「自动沿用上次的配件」时，新的一次充电直接关联上次用的组合
    private func carryLastAccessory() {
        guard UserDefaults.standard.bool(forKey: Self.autoAssignKey), let last = book.lastUsed else { return }
        recorder.assignAccessory(last.id)
        EventLog.shared.add("自动沿用配件：\(last.name)")
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
        EventLog.shared.add("充电记录已保存：\(Format.batteryPercent(session.samples.first?.level ?? 0)) → \(Format.batteryPercent(session.samples.last?.level ?? 0))")
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        recorder = stored.recorder
        sessions = stored.sessions
        book = stored.book ?? AccessoryBook()
        current = stored.recorder.current
    }

    private static let fileURL: URL? = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ChargeSessions.json")
    }()
}
