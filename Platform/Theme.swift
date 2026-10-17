import SwiftUI

/// 视觉风格：深色霓虹。每类指标一个固定的强调色，App、小组件、灵动岛统一使用。
enum Theme {
    static let battery = Color(red: 0.62, green: 0.95, blue: 0.30)   // 青柠绿
    static let charging = Color(red: 1.00, green: 0.84, blue: 0.04)  // 电光黄
    static let cpu = Color(red: 0.66, green: 0.55, blue: 0.98)       // 紫
    static let memory = Color(red: 0.96, green: 0.45, blue: 0.71)    // 粉
    static let storage = Color(red: 0.98, green: 0.57, blue: 0.24)   // 橙
    static let network = Color(red: 0.13, green: 0.83, blue: 0.93)   // 青
    static let upload = Color(red: 0.98, green: 0.57, blue: 0.24)    // 上传用橙色，和下载区分
    static let caution = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let warning = Color(red: 1.00, green: 0.42, blue: 0.35)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let track = Color.white.opacity(0.12)

    /// 小组件和灵动岛展开区的背景：深色渐变，浅色模式下稍亮一点
    static func background(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.05, green: 0.06, blue: 0.11), Color(red: 0.11, green: 0.07, blue: 0.19)]
            : [Color(red: 0.11, green: 0.12, blue: 0.20), Color(red: 0.21, green: 0.13, blue: 0.31)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func batteryColor(level: Double?, state: BatteryState) -> Color {
        if state.isPluggedIn { return charging }
        guard let level else { return battery }
        if level <= 0.2 { return warning }
        if level <= 0.4 { return caution }
        return battery
    }

    static func thermalColor(_ level: ThermalLevel) -> Color {
        switch level {
        case .nominal: battery
        case .fair: caution
        case .serious: storage
        case .critical: warning
        }
    }

    /// 数字统一用圆体 + 等宽数字，跳动时不会左右晃
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// 环形进度
struct RingGauge<Content: View>: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat
    let content: Content

    init(progress: Double, tint: Color, lineWidth: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [tint.opacity(0.55), tint]), center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
    }
}

/// 细长进度条
struct BarGauge: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geometry.size.width * min(max(progress, 0), 1), height))
            }
        }
        .frame(height: height)
    }
}
