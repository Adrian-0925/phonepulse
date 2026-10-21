import AVFoundation
import UIKit

/// 把实时数据画成一帧"视频"（CMSampleBuffer），交给画中画显示。画什么由 FloatingStyle 决定。
enum SpeedFrameRenderer {
    /// 3:1 的画面，按 2 倍分辨率绘制，画中画窗口放大后也清晰。
    /// 尺寸固定不变：画面比例一变，系统会重新调整悬浮窗大小
    static let size = CGSize(width: 540, height: 180)

    private static let horizontalInset: CGFloat = 28
    /// 两行时每行的字号；只有一行时字更大
    private static let twoLineFontSize: CGFloat = 60
    private static let oneLineFontSize: CGFloat = 92

    private static let downloadColor = UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1)
    private static let uploadColor = UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
    private static let batteryColor = UIColor(red: 0.62, green: 0.95, blue: 0.30, alpha: 1)
    private static let chargingColor = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
    private static let cpuColor = UIColor(red: 0.66, green: 0.55, blue: 0.98, alpha: 1)
    private static let terminalGreen = UIColor(red: 0.30, green: 1, blue: 0.45, alpha: 1)

    static func makeSampleBuffer(style: FloatingStyle, snapshot: MetricsSnapshot?) -> CMSampleBuffer? {
        guard let pixelBuffer = makePixelBuffer() else { return nil }
        draw(into: pixelBuffer, style: style, snapshot: snapshot)
        return wrap(pixelBuffer)
    }

    private static func makePixelBuffer() -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
        ]
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        return buffer
    }

    private static func draw(into buffer: CVPixelBuffer, style: FloatingStyle, snapshot: MetricsSnapshot?) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }

        // CoreGraphics 原点在左下角，翻转成 UIKit 的左上角再画文字
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let lines = style.lines
        let width = size.width - horizontalInset * 2
        if lines.count == 1, let item = lines.first {
            drawLine(item, style: style, snapshot: snapshot, fontSize: oneLineFontSize,
                     in: CGRect(x: horizontalInset, y: 0, width: width, height: size.height))
        } else {
            for (index, item) in lines.enumerated() {
                // 上下两行，各占一半，和以前的位置基本一致
                let rect = CGRect(x: horizontalInset, y: 10 + CGFloat(index) * 80, width: width, height: 80)
                drawLine(item, style: style, snapshot: snapshot, fontSize: twoLineFontSize, in: rect)
            }
        }
    }

    /// 在 rect 里垂直居中画一行；太长就把字缩小到放得下（比如「⚡ 76% ≈ 18 W」）
    private static func drawLine(_ item: FloatingStyle.Item, style: FloatingStyle, snapshot: MetricsSnapshot?, fontSize: CGFloat, in rect: CGRect) {
        let text = FloatingStyle.text(for: item, snapshot: snapshot) as NSString
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color(for: item, palette: style.palette, snapshot: snapshot),
        ]
        let naturalWidth = text.size(withAttributes: attributes).width
        if naturalWidth > rect.width {
            attributes[.font] = UIFont.monospacedDigitSystemFont(ofSize: fontSize * rect.width / naturalWidth, weight: .semibold)
        }
        let textHeight = text.size(withAttributes: attributes).height
        text.draw(at: CGPoint(x: rect.minX, y: rect.midY - textHeight / 2), withAttributes: attributes)
    }

    private static func color(for item: FloatingStyle.Item, palette: FloatingStyle.Palette, snapshot: MetricsSnapshot?) -> UIColor {
        switch palette {
        case .white:
            return .white
        case .green:
            return terminalGreen
        case .colorful:
            switch item {
            case .download, .none: return downloadColor
            case .upload: return uploadColor
            case .battery: return snapshot?.battery.state.isPluggedIn == true ? chargingColor : batteryColor
            case .cpu: return cpuColor
            }
        }
    }

    private static func wrap(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        guard let format else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)
        guard let sampleBuffer else { return nil }

        // 不按时间戳排队播放，收到就立刻显示
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}
