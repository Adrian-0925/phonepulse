import Foundation

struct DeviceModel {
    let name: String
    /// 设计容量（mAh），用于估算充电功率
    let batteryMAh: Int
}

/// 机型标识（如 "iPhone16,1"）→ 机型名称与电池设计容量。
/// 容量数据来自公开的监管文件和拆解报告，上线前需逐条核对；新机型发布后要补充。
enum DeviceCatalog {
    static let identifier: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
    }()

    static var current: DeviceModel? { models[identifier] }

    static var displayName: String { current?.name ?? identifier }

    private static let models: [String: DeviceModel] = [
        "iPhone12,1": DeviceModel(name: "iPhone 11", batteryMAh: 3110),
        "iPhone12,3": DeviceModel(name: "iPhone 11 Pro", batteryMAh: 3046),
        "iPhone12,5": DeviceModel(name: "iPhone 11 Pro Max", batteryMAh: 3969),
        "iPhone12,8": DeviceModel(name: "iPhone SE (第 2 代)", batteryMAh: 1821),
        "iPhone13,1": DeviceModel(name: "iPhone 12 mini", batteryMAh: 2227),
        "iPhone13,2": DeviceModel(name: "iPhone 12", batteryMAh: 2815),
        "iPhone13,3": DeviceModel(name: "iPhone 12 Pro", batteryMAh: 2815),
        "iPhone13,4": DeviceModel(name: "iPhone 12 Pro Max", batteryMAh: 3687),
        "iPhone14,4": DeviceModel(name: "iPhone 13 mini", batteryMAh: 2406),
        "iPhone14,5": DeviceModel(name: "iPhone 13", batteryMAh: 3227),
        "iPhone14,2": DeviceModel(name: "iPhone 13 Pro", batteryMAh: 3095),
        "iPhone14,3": DeviceModel(name: "iPhone 13 Pro Max", batteryMAh: 4352),
        "iPhone14,6": DeviceModel(name: "iPhone SE (第 3 代)", batteryMAh: 2018),
        "iPhone14,7": DeviceModel(name: "iPhone 14", batteryMAh: 3279),
        "iPhone14,8": DeviceModel(name: "iPhone 14 Plus", batteryMAh: 4325),
        "iPhone15,2": DeviceModel(name: "iPhone 14 Pro", batteryMAh: 3200),
        "iPhone15,3": DeviceModel(name: "iPhone 14 Pro Max", batteryMAh: 4323),
        "iPhone15,4": DeviceModel(name: "iPhone 15", batteryMAh: 3349),
        "iPhone15,5": DeviceModel(name: "iPhone 15 Plus", batteryMAh: 4383),
        "iPhone16,1": DeviceModel(name: "iPhone 15 Pro", batteryMAh: 3274),
        "iPhone16,2": DeviceModel(name: "iPhone 15 Pro Max", batteryMAh: 4422),
        "iPhone17,3": DeviceModel(name: "iPhone 16", batteryMAh: 3561),
        "iPhone17,4": DeviceModel(name: "iPhone 16 Plus", batteryMAh: 4674),
        "iPhone17,1": DeviceModel(name: "iPhone 16 Pro", batteryMAh: 3582),
        "iPhone17,2": DeviceModel(name: "iPhone 16 Pro Max", batteryMAh: 4685),
        "iPhone17,5": DeviceModel(name: "iPhone 16e", batteryMAh: 4005),
        // TODO: iPhone 17 系列（iPhone18,x）—— 不同地区 SIM 版本容量不同，需核对后补充
    ]
}
