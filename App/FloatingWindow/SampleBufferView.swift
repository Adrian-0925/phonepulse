import AVFoundation
import SwiftUI
import UIKit

/// 底层是 AVSampleBufferDisplayLayer 的 UIView，作为画中画的视频源
final class SampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 把同一个 SampleBufferView 放进 SwiftUI。视图由 FloatingSpeedController 持有，保证画中画绑定的图层不变。
struct SampleBufferPreview: UIViewRepresentable {
    let view: SampleBufferView

    func makeUIView(context: Context) -> SampleBufferView { view }

    func updateUIView(_ uiView: SampleBufferView, context: Context) {}
}
