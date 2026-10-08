#!/usr/bin/env python3
"""Exercise the actual scheduling helpers without launching Rayon or reading credentials."""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELPERS = [
    ("Application/Rayon/Extension/UIBridge/UIBridge.swift", "mainActor"),
    ("Application/Rayon/Extension/UIBridge/UIBridge.swift", "mainActorUI"),
    ("Foundation/RayonModule/Sources/RayonModule/Utils/MainActor.swift", "mainActor"),
    ("Foundation/MachineStatus/Sources/MachineStatus/ServerStatusInfo.swift", "mainActor"),
]

HARNESS = r'''
final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(value)
    }
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

@main
struct SchedulingCheck {
    @MainActor static func main() {
        let events = Events()
        events.append("before")
        HELPER {
            precondition(Thread.isMainThread)
            events.append("inline")
        }
        events.append("after")
        precondition(events.values == ["before", "inline", "after"])

        let scheduled = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            HELPER {
                precondition(Thread.isMainThread)
                events.append("background")
            }
            events.append("background-returned")
            scheduled.signal()
        }
        precondition(scheduled.wait(timeout: .now() + 5) == .success)
        precondition(events.values.last == "background-returned")

        let start = Date()
        HELPER(delay: 0.1) {
            precondition(Thread.isMainThread)
            precondition(Date().timeIntervalSince(start) >= 0.09)
            events.append("delayed")
        }
        precondition(!events.values.contains("delayed"))
        let deadline = Date().addingTimeInterval(5)
        while events.values.count < 6 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(events.values == [
            "before", "inline", "after", "background-returned", "background", "delayed"
        ])
        print("PASS: inline ordering, background enqueue, delayed execution, main-thread callbacks")
    }
}
'''


def extract_function(source: str, name: str) -> str:
    start = source.index(f"func {name}(")
    body = source.index("{", start)
    depth = 1
    end = body + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


with tempfile.TemporaryDirectory(prefix="rayon-swift6-scheduling-") as directory:
    temporary = Path(directory)
    for relative, helper in HELPERS:
        implementation = extract_function((ROOT / relative).read_text(), helper)
        source = temporary / "SchedulingCheck.swift"
        source.write_text("import Foundation\n" + implementation + HARNESS.replace("HELPER", helper))
        executable = temporary / "SchedulingCheck"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
            str(source), "-o", str(executable),
        ], check=True)
        print(f"{relative} :: {helper}", flush=True)
        subprocess.run([str(executable)], check=True, timeout=10)
