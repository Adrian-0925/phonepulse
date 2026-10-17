import Charts
import SwiftUI

/// 充电曲线。App 没运行的空档断开画，不连成直线，免得看起来像真实数据。
struct ChargeCurveChart: View {
    let samples: [ChargeSample]
    var tint: Color = Theme.charging
    var showsAxes = true

    private struct CurvePoint: Identifiable {
        let id: Int
        let time: Date
        let percent: Double
        let segment: Int
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("电量", 80))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.gray.opacity(0.5))
            ForEach(points) { point in
                LineMark(
                    x: .value("时间", point.time),
                    y: .value("电量", point.percent),
                    series: .value("段", point.segment))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .chartLegend(.hidden)
    }

    private var points: [CurvePoint] {
        var result: [CurvePoint] = []
        var segment = 0
        for index in samples.indices {
            if index > 0, samples[index].time.timeIntervalSince(samples[index - 1].time) > ChargeSessionRecorder.continuityLimit {
                segment += 1
            }
            result.append(CurvePoint(id: index, time: samples[index].time, percent: samples[index].level * 100, segment: segment))
        }
        return result
    }

    /// 上下留一点空，至少显示 10 个百分点的范围
    private var yDomain: ClosedRange<Double> {
        let percents = samples.map { $0.level * 100 }
        var low = max((percents.min() ?? 0) - 5, 0)
        var high = min((percents.max() ?? 100) + 5, 100)
        if high - low < 10 {
            high = min(low + 10, 100)
            low = max(high - 10, 0)
        }
        return low...high
    }
}
