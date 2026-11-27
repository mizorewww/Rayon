//
//  UIViewController.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/4.
//

#if os(iOS)
    import UIKit

    extension UIViewController {
        func present(next: UIViewController) {
            if let navigator = navigationController,
               !(next is UIAlertController),
               !(next is UIActivityViewController)
            {
                navigator.pushViewController(next, animated: true)
            } else {
                // The caller chooses the presentation style; the terminal asks
                // for .fullScreen on iPhone.
                next.modalTransitionStyle = .coverVertical
                present(next, animated: true, completion: nil)
            }
        }
    }

    /// Presents over the app's topmost view controller once the way is clear.
    /// UIKit drops a present issued while a sheet animates in or out, and at
    /// launch the scene has no window yet: the present follows the transition
    /// in flight, or the first window to become key.
    @MainActor
    enum ModalPresenter {
        /// - Parameter push: UIViewController.present(next:) semantics, pushed
        ///   when the topmost controller sits in a navigation controller.
        static func present(_ controller: UIViewController, push: Bool = false) {
            guard let top = UIWindow.shutUpKeyWindow?.topMostViewController, top.viewIfLoaded?.window != nil else {
                Task {
                    for await _ in NotificationCenter.default.notifications(named: UIWindow.didBecomeKeyNotification) {
                        break
                    }
                    present(controller, push: push)
                }
                return
            }
            if let coordinator = top.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in
                    MainActor.assumeIsolated { present(controller, push: push) }
                }
                return
            }
            if push {
                top.present(next: controller)
            } else {
                top.present(controller, animated: true)
            }
        }
    }

#endif
