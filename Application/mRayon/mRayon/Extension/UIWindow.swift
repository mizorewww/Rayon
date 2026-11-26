//
//  UIWindow.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import UIKit

extension UIWindow {
    /// The app's window, to present a screen from. Not whichever window is
    /// key: while a menu or the keyboard is up that is a window of the
    /// system's, and at the moment a menu item is chosen there may be none.
    static var shutUpKeyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        guard let scene else {
            NSLog("no window scene to present from")
            return nil
        }
        // The system's windows are of classes of its own.
        let own = scene.windows.filter { type(of: $0) == UIWindow.self && !$0.isHidden }
        let window = own.first(where: \.isKeyWindow) ?? own.first
            ?? scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        if window == nil { NSLog("no window to present from") }
        return window
    }

    var topMostViewController: UIViewController? {
        var result: UIViewController? = rootViewController
        while true {
            if let next = result?.presentedViewController {
                result = next
                continue
            }
            if let tabbar = result as? UITabBarController,
               let next = tabbar.selectedViewController
            {
                result = next
                continue
            }
            if let split = result as? UISplitViewController,
               let next = split.viewControllers.last
            {
                result = next
                continue
            }
            if let navigator = result as? UINavigationController,
               let next = navigator.viewControllers.last
            {
                result = next
                continue
            }
            break
        }
        return result
    }
}
