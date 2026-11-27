//
//  UIViewController.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/4.
//

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

    /// Whether a present issued now would stick: the view is in a window
    /// and no transition is in flight on this controller. UIKit answers a
    /// present issued mid-transition with a console warning and drops the
    /// controller, so PresentationQueue waits for this instead of having
    /// callers guess a delay.
    var isReadyForPresentation: Bool {
        presentedViewController == nil
            && !isBeingPresented
            && !isBeingDismissed
            && !isMovingToParent
            && !isMovingFromParent
            && viewIfLoaded?.window != nil
    }
}

/// Presents over the app's window as soon as the window can take it. The
/// two moments it cannot — the window is not in the hierarchy yet (launch),
/// or a sheet is still animating in or out — used to be covered by guessed
/// delays, and a miss was lost silently on an optional chain. Requests now
/// go up immediately when the way is clear, are replayed when a window
/// becomes key and on a short poll while a transition finishes, and a
/// request that outlives its timeout is logged rather than dropped quietly.
enum PresentationQueue {
    private struct Request {
        let controller: UIViewController
        let push: Bool
        let deadline: Date
        let completion: ((Bool) -> Void)?
    }

    private static var requests: [Request] = []
    private static var pollTimer: Timer?
    private static var keyWindowObserver: NSObjectProtocol?

    /// Modal present over the topmost view controller.
    static func present(
        _ controller: UIViewController,
        timeout: TimeInterval = 2,
        completion: ((Bool) -> Void)? = nil
    ) {
        enqueue(controller, push: false, timeout: timeout, completion: completion)
    }

    /// Present over the topmost view controller with
    /// UIViewController.present(next:) semantics: pushed when that
    /// controller sits inside a navigation controller, modal otherwise.
    static func present(
        next controller: UIViewController,
        timeout: TimeInterval = 2,
        completion: ((Bool) -> Void)? = nil
    ) {
        enqueue(controller, push: true, timeout: timeout, completion: completion)
    }

    private static func enqueue(
        _ controller: UIViewController,
        push: Bool,
        timeout: TimeInterval,
        completion: ((Bool) -> Void)?
    ) {
        assert(Thread.isMainThread, "PresentationQueue drives UIKit presentation and must run on the main thread")
        let request = Request(
            controller: controller,
            push: push,
            deadline: Date().addingTimeInterval(timeout),
            completion: completion
        )
        // Queued requests go first, so overlapping presents keep their
        // arrival order instead of covering one another at random.
        guard requests.isEmpty else {
            requests.append(request)
            return
        }
        guard !attempt(request) else { return }
        requests.append(request)
        startWatching()
    }

    @discardableResult
    private static func attempt(_ request: Request) -> Bool {
        guard let presenter = UIWindow.shutUpKeyWindow?.topMostViewController,
              presenter.isReadyForPresentation
        else { return false }
        if request.push {
            presenter.present(next: request.controller)
        } else {
            presenter.present(request.controller, animated: true, completion: nil)
        }
        request.completion?(true)
        return true
    }

    private static func startWatching() {
        guard pollTimer == nil else { return }
        // A window becoming key often means the way just cleared (launch,
        // a dismissed alert); a sheet transition posts no notification,
        // hence the poll alongside.
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in flush() }
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in flush() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private static func flush() {
        assert(Thread.isMainThread)
        requests = requests.filter { request in
            if attempt(request) { return false }
            if Date() >= request.deadline {
                NSLog("PresentationQueue: no window accepted %@ in time; the present is dropped", request.controller)
                request.completion?(false)
                return false
            }
            return true
        }
        if requests.isEmpty {
            pollTimer?.invalidate()
            pollTimer = nil
            if let keyWindowObserver {
                NotificationCenter.default.removeObserver(keyWindowObserver)
                self.keyWindowObserver = nil
            }
        }
    }
}
