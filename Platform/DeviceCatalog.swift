import Foundation

/// 机型静态规格（不是实时读数）
struct DeviceModel {
    let name: String
    /// 设计容量（mAh），出厂标称
    let batteryMAh: Int
    let chip: String
    let gpuCores: Int
    let hasDynamicIsland: Bool
}

/// 机型标识（如 "iPhone16,1"）→ 静态规格。
/// 电池容量来自公开的监管文件和拆解报告，芯片和 GPU 核心数来自 Apple 官方规格，上线前需逐条核对；新机型发布后要补充。
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

    private static func model(_ name: String, _ mAh: Int, _ chip: String, gpu: Int, island: Bool = false) -> DeviceModel {
        DeviceModel(name: name, batteryMAh: mAh, chip: chip, gpuCores: gpu, hasDynamicIsland: island)
    }

    private static let models: [String: DeviceModel] = [
        "iPhone12,1": model("iPhone 11", 3110, "A13 仿生", gpu: 4),
        "iPhone12,3": model("iPhone 11 Pro", 3046, "A13 仿生", gpu: 4),
        "iPhone12,5": model("iPhone 11 Pro Max", 3969, "A13 仿生", gpu: 4),
        "iPhone12,8": model("iPhone SE (第 2 代)", 1821, "A13 仿生", gpu: 4),
        "iPhone13,1": model("iPhone 12 mini", 2227, "A14 仿生", gpu: 4),
        "iPhone13,2": model("iPhone 12", 2815, "A14 仿生", gpu: 4),
        "iPhone13,3": model("iPhone 12 Pro", 2815, "A14 仿生", gpu: 4),
        "iPhone13,4": model("iPhone 12 Pro Max", 3687, "A14 仿生", gpu: 4),
        "iPhone14,4": model("iPhone 13 mini", 2406, "A15 仿生", gpu: 4),
        "iPhone14,5": model("iPhone 13", 3227, "A15 仿生", gpu: 4),
        "iPhone14,2": model("iPhone 13 Pro", 3095, "A15 仿生", gpu: 5),
        "iPhone14,3": model("iPhone 13 Pro Max", 4352, "A15 仿生", gpu: 5),
        "iPhone14,6": model("iPhone SE (第 3 代)", 2018, "A15 仿生", gpu: 4),
        "iPhone14,7": model("iPhone 14", 3279, "A15 仿生", gpu: 5),
        "iPhone14,8": model("iPhone 14 Plus", 4325, "A15 仿生", gpu: 5),
        "iPhone15,2": model("iPhone 14 Pro", 3200, "A16 仿生", gpu: 5, island: true),
        "iPhone15,3": model("iPhone 14 Pro Max", 4323, "A16 仿生", gpu: 5, island: true),
        "iPhone15,4": model("iPhone 15", 3349, "A16 仿生", gpu: 5, island: true),
        "iPhone15,5": model("iPhone 15 Plus", 4383, "A16 仿生", gpu: 5, island: true),
        "iPhone16,1": model("iPhone 15 Pro", 3274, "A17 Pro", gpu: 6, island: true),
        "iPhone16,2": model("iPhone 15 Pro Max", 4422, "A17 Pro", gpu: 6, island: true),
        "iPhone17,3": model("iPhone 16", 3561, "A18", gpu: 5, island: true),
        "iPhone17,4": model("iPhone 16 Plus", 4674, "A18", gpu: 5, island: true),
        "iPhone17,1": model("iPhone 16 Pro", 3582, "A18 Pro", gpu: 6, island: true),
        "iPhone17,2": model("iPhone 16 Pro Max", 4685, "A18 Pro", gpu: 6, island: true),
        "iPhone17,5": model("iPhone 16e", 4005, "A18", gpu: 4),
        // TODO: iPhone 17 系列（iPhone18,x）—— 不同地区 SIM 版本容量不同，需核对后补充
    ]
}
