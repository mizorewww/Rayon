//
//  EventLoopTaskExecutor.swift
//  RayonSSH
//
//  Runs a task's code on a channel's event loop. Citadel's
//  `SSHClient.connect(on:)` changes the channel's pipeline synchronously
//  before its first await, which NIO only allows on the channel's own
//  event loop; preferring this executor puts it there.
//

import NIOCore

final class EventLoopTaskExecutor: TaskExecutor {
    let eventLoop: EventLoop

    init(_ eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        eventLoop.execute { job.runSynchronously(on: executor) }
    }
}
