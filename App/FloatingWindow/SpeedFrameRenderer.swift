import AVFoundation
import UIKit

/// 把网速画成一帧"视频"（CMSampleBuffer），交给画中画显示。
enum SpeedFrameRenderer {
    /// 3:1 的画面，按 2 倍分辨率绘制，画中画窗口放大后也清晰
    static let size = CGSize(width: 540, height: 180)

    private static let font = UIFont.monospacedDigitSystemFont(ofSize: 60, weight: .semibold)
    private static let downloadColor = UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1)
    private static let uploadColor = UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)

    static func makeSampleBuffer(download: Double, upload: Double) -> CMSampleBuffer? {
        guard let pixelBuffer = makePixelBuffer() else { return nil }
        draw(into: pixelBuffer, download: download, upload: upload)
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

    private static func draw(into buffer: CVPixelBuffer, download: Double, upload: Double) {
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
        drawText("↓ \(Format.speed(download))", color: downloadColor, at: CGPoint(x: 28, y: 18))
        drawText("↑ \(Format.speed(upload))", color: uploadColor, at: CGPoint(x: 28, y: 92))
    }

    private static func drawText(_ text: String, color: UIColor, at point: CGPoint) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
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
