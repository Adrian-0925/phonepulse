import Observation
import SwiftUI
import UIKit

/// 运行事件日志（只保存在内存里），真机诊断时用来还原"什么时候切了后台、悬浮窗什么时候开关"。
@MainActor
@Observable
final class EventLog {
    static let shared = EventLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let limit = 200

    func add(_ message: String) {
        entries.append(Entry(date: .now, message: message))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }
}

extension UIApplication.State {
    var label: String {
        switch self {
        case .active: "前台"
        case .inactive: "非活跃"
        case .background: "后台"
        @unknown default: "未知"
        }
    }
}

extension ScenePhase {
    var label: String {
        switch self {
        case .active: "前台"
        case .inactive: "非活跃"
        case .background: "后台"
        @unknown default: "未知"
        }
    }
}
