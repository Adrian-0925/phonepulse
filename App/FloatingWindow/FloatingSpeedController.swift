import AVFoundation
import AVKit
import Observation
import UIKit

/// 画中画悬浮网速窗。
///
/// 原理：iOS 不允许 App 在别的 App 上面画东西，但允许"画中画播放视频"。
/// 这里每秒把网速（或用户在样式里选的其他内容）画成一帧视频喂给 AVSampleBufferDisplayLayer，再交给画中画显示。
/// 画中画开着时系统会让 App 在后台继续运行，所以能持续采样、刷新画面。
///
/// 前提：Info.plist 声明 UIBackgroundModes = audio（即"音频、AirPlay 和画中画"后台模式），音频会话设为 playback。
/// 审核风险：画中画的本意是播放视频，用来显示数据属于灰色地带，国区已有同类 App 上架，但不保证一定能过。
@MainActor
@Observable
final class FloatingSpeedController: NSObject {
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var isPossible = false
    private(set) var isActive = false
    private(set) var errorMessage: String?
    /// 诊断用：音频会话是否已配置成功
    private(set) var audioSessionReady = false
    /// 诊断用：渲染器进入 failed 状态后被重置的次数
    private(set) var rendererResetCount = 0
    /// 离开 App（回到桌面或切到其他 App，系统不区分这两种情况）时是否显示悬浮窗
    private(set) var showsOutsideApp = UserDefaults.standard.object(forKey: FloatingSpeedController.showsOutsideAppKey) as? Bool ?? true
    /// 悬浮窗画面里显示什么、用什么配色
    private(set) var style = FloatingStyle.load()

    static let showsOutsideAppKey = "floatingShowsOutsideApp"

    /// 画中画的视频源。必须放进界面里（仪表盘的预览卡片）才能开启画中画。
    let sourceView = SampleBufferView()

    private let engine: MetricsEngine
    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    /// 最近一次采样，改样式时马上用它重画，不用等下一秒
    @ObservationIgnored private var lastSnapshot: MetricsSnapshot?

    init(engine: MetricsEngine) {
        self.engine = engine
        super.init()
        sourceView.displayLayer.videoGravity = .resizeAspect
        render(nil)
        engine.onTick = { [weak self] snapshot in
            self?.render(snapshot)
        }
        setUpPictureInPicture()
    }

    /// 改样式：保存并立即重画（悬浮窗开着时也马上生效）
    func setStyle(_ newStyle: FloatingStyle) {
        guard newStyle != style else { return }
        style = newStyle
        newStyle.save()
        render(lastSnapshot)
        EventLog.shared.add("悬浮窗样式：\(newStyle.summary)")
    }

    /// 画中画要求音频会话为 playback；mixWithOthers 保证不会打断用户正在听的音乐。
    func prepare() {
        guard !audioSessionReady else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            audioSessionReady = true
            EventLog.shared.add("音频会话已设为 playback（可与其他声音混合）")
        } catch {
            errorMessage = "音频会话配置失败：\(error.localizedDescription)"
            EventLog.shared.add(errorMessage ?? "")
        }
    }

    /// 关闭后：离开 App 时不自动弹出悬浮窗，已经开着的也会收起。
    /// 注意 App 靠悬浮窗才能在后台继续运行，收起后 App 会被系统暂停，灵动岛停在最后的数据。
    func setShowsOutsideApp(_ value: Bool) {
        showsOutsideApp = value
        UserDefaults.standard.set(value, forKey: Self.showsOutsideAppKey)
        pipController?.canStartPictureInPictureAutomaticallyFromInline = value
        EventLog.shared.add("离开 App 时显示悬浮窗：\(value ? "开" : "关")")
    }

    /// App 进入后台时调用：按设置决定是否收起悬浮窗
    func appDidEnterBackground() {
        guard !showsOutsideApp, let pipController, pipController.isPictureInPictureActive else { return }
        EventLog.shared.add("离开 App，按设置收起悬浮窗")
        pipController.stopPictureInPicture()
    }

    func toggle() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            EventLog.shared.add("请求关闭画中画")
            pipController.stopPictureInPicture()
        } else {
            prepare()
            errorMessage = nil
            EventLog.shared.add("请求开启画中画")
            pipController.startPictureInPicture()
        }
    }

    private func setUpPictureInPicture() {
        guard isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sourceView.displayLayer,
            playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        // 在 App 里开着预览时切到后台，自动弹出悬浮窗（需用户在系统设置里开启"自动开启画中画"，且本 App 的设置允许）
        controller.canStartPictureInPictureAutomaticallyFromInline = showsOutsideApp
        controller.requiresLinearPlayback = true
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, change in
            let possible = change.newValue ?? false
            Task { @MainActor [weak self] in
                guard let self, self.isPossible != possible else { return }
                self.isPossible = possible
                EventLog.shared.add("画中画可开启：\(possible ? "是" : "否")")
            }
        }
        pipController = controller
    }

    private func render(_ snapshot: MetricsSnapshot?) {
        if let snapshot {
            lastSnapshot = snapshot
        }
        guard let buffer = SpeedFrameRenderer.makeSampleBuffer(style: style, snapshot: snapshot ?? lastSnapshot) else { return }
        let renderer = sourceView.displayLayer.sampleBufferRenderer
        // App 切后台等情况会让渲染器进入 failed 状态，需要 flush 才能继续显示
        if renderer.status == .failed {
            renderer.flush()
            rendererResetCount += 1
            EventLog.shared.add("渲染器失败，已重置（第 \(rendererResetCount) 次）")
        }
        renderer.enqueue(buffer)
    }
}

// MARK: - 画中画生命周期

extension FloatingSpeedController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = true
            EventLog.shared.add("画中画已开启（App \(UIApplication.shared.applicationState.label)）")
            // 切后台自动弹出的情况：切后台那一刻引擎已经停了，这里重新启动
            self.engine.start()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = false
            EventLog.shared.add("画中画已关闭（App \(UIApplication.shared.applicationState.label)）")
            if UIApplication.shared.applicationState == .background {
                self.engine.stop()
            }
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.errorMessage = "无法开启画中画：\(message)"
            EventLog.shared.add("画中画开启失败：\(message)")
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - 播放控制（我们的"视频"是实时内容，没有暂停和进度）

extension FloatingSpeedController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // 无限长的时间范围表示直播内容，画中画不显示进度条
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
