import SwiftUI
import UIKit

/// 只让充电大屏横屏，其他页面保持竖屏。
/// Info.plist 里声明了横屏方向，实际允许哪些方向由这里的 mask 决定。
@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { error in
            EventLog.shared.add("切换屏幕方向失败：\(error.localizedDescription)")
        }
        // 当前最上层的页面（全屏弹出的充电大屏）也要重新询问支持的方向
        var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        while let presented = controller?.presentedViewController {
            presented.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = presented
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
