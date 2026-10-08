//
//  StatusItem+Loop.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/1.
//

import AppKit
import MachineStatusView
import RayonModule
import SwiftUI

extension MenubarStatusItem {
    func beginFrameLoop() {
        let thread = Thread { [weak self] in
            while self?.loopContinue ?? false {
                usleep(100)
                guard let self = self else {
                    return
                }
                self.switchNextFrame()
                self.accessLock.lock()
                let interval = self.catSpeed.rawValue
                self.accessLock.unlock()
                var sleepInterval = (UInt32(exactly: interval * 1_000_000) ?? 1_000_000)
                if sleepInterval < 1000 { sleepInterval = 1000 }
                usleep(sleepInterval)
            }
            debugPrint("\(#function) end")
        }
        thread.start()
    }

    /// The cat's pace follows CPU load; the title shows upload and download speed.
    func observeSession() {
        // objectWillChange fires before the change lands; the short debounce on
        // the main run loop reads the new values.
        session.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshFromSession() }
            .store(in: &cancellables)
    }

    func refreshFromSession() {
        let speed: CatSpeed
        if session.phase != .connected || !session.status.hasData {
            speed = .broken
        } else {
            let cpu = session.status.processor.summary.sumUsed
            switch cpu {
            case ..<5: speed = .hang
            case ..<20: speed = .walk
            case ..<50: speed = .run
            case ..<80: speed = .fast
            default: speed = .light
            }
        }
        accessLock.lock()
        catSpeed = speed
        accessLock.unlock()

        guard let button = statusItem.button else { return }
        if session.phase == .connected, session.status.hasData {
            let up = RXFormat.rateString(Double(session.status.totalTransmitPerSecond))
            let down = RXFormat.rateString(Double(session.status.totalReceivePerSecond))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            paragraph.maximumLineHeight = 10
            paragraph.minimumLineHeight = 10
            button.attributedTitle = NSAttributedString(
                string: "↑ \(up)\n↓ \(down)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .paragraphStyle: paragraph,
                    .baselineOffset: -5,
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    func switchNextFrame() {
        guard accessLock.try() else {
            return
        }
        defer { accessLock.unlock() }

        guard !frames.isEmpty else {
            return
        }
        let interval = catSpeed.rawValue
        if interval <= 0 {
            mainActor { [self] in
                statusItem.button?.image = NSImage(named: "cat_frame_crash")
            }
            return
        }
        defer { currentImageIndex += 1 }
        if currentImageIndex > frames.count - 1 {
            currentImageIndex = 0
        }
        let image = frames[currentImageIndex]
        mainActor { [self] in
            statusItem.button?.image = image

            // check if already deleted
            let check = RayonStore.shared.machineGroup[machine.id]
            guard check.isNotPlaceholder() else {
                closeThisItem()
                return
            }
        }
    }
}
