import Foundation

/// Folds a run of changes to one setting (a held stepper, a dragged
/// slider) into one undo step: the run's first change registers how to set
/// back what was there before it, and the ones close after it on the same
/// undo stack register nothing. A pause, an undo or redo, or anything else
/// going on that stack ends the run. A run that comes back to where it
/// started (a toggle switched on and off again) takes its step off the
/// stack, so Edit › Undo never offers one that changes nothing.
@MainActor
public final class SettingUndoRun {
    public static let shared = SettingUndoRun()

    /// How long after a change the next one to the same setting still
    /// belongs to its run: longer than a stepper's repeat or a drag's step.
    private static let pause: Duration = .seconds(1)

    private weak var manager: UndoManager?
    private var key: String?
    private var last: ContinuousClock.Instant?
    private var start: (any Equatable)?
    /// The run's step is a top-level undo group of its own, so undoing it
    /// takes back nothing else.
    private var alone = false
    private var registering = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let names: [Notification.Name] = [.NSUndoManagerDidOpenUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange]
        // Synchronous (no queue), so a group our own registration opens
        // arrives while `registering` says so.
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                guard Thread.isMainThread, let manager = note.object as? UndoManager else { return }
                let id = ObjectIdentifier(manager)
                MainActor.assumeIsolated {
                    guard let self, !self.registering, let current = self.manager, ObjectIdentifier(current) == id else { return }
                    self.end()
                }
            }
        }
    }

    /// Calls `register` to put the change to `key`, from `old` to `new`, on
    /// `manager`, unless it continues a run whose first change already did.
    /// The caller has already made the change, so undoing a step that
    /// returns to `new` does nothing and registers no redo.
    public func record<Value: Equatable>(_ key: String, from old: Value, to new: Value, on manager: UndoManager, register: () -> Void) {
        let now = ContinuousClock.now
        let continues = !manager.isUndoing && !manager.isRedoing && manager.canUndo
            && manager === self.manager && key == self.key
            && last.map { now - $0 < Self.pause } ?? false
        if continues, alone, (start as? Value) == new, manager.groupingLevel == 0 {
            // The run's step would put back what is there now. Undoing it
            // removes it; the undo notification ends the run.
            manager.undo()
            return
        }
        if !continues {
            // A top-level group of its own, not the event's automatic one,
            // which another registration in the same event would join.
            // Beginning a group while grouping by event first opens that
            // automatic group, so grouping by event is off meanwhile.
            // Inside a group someone else opened, the step is not alone.
            alone = manager.groupingLevel == 0
            registering = true
            if alone {
                let groupsByEvent = manager.groupsByEvent
                manager.groupsByEvent = false
                manager.beginUndoGrouping()
                register()
                manager.endUndoGrouping()
                manager.groupsByEvent = groupsByEvent
            } else {
                register()
            }
            registering = false
            start = old
        }
        if manager.isUndoing || manager.isRedoing {
            end()
        } else {
            self.manager = manager
            self.key = key
            last = now
        }
    }

    /// The next change starts a new step: what the stack held was replaced
    /// or cleared.
    public func end() {
        manager = nil
        key = nil
        last = nil
        start = nil
        alone = false
    }
}
