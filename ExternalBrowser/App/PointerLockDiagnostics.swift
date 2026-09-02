import UIKit
import Combine

/// Records what happens around pointer lock, because none of it is
/// observable from the device otherwise.
///
/// The question this exists to answer: pulling Control Center down and up
/// engages pointer lock, while `setNeedsUpdateOfPrefersPointerLocked()`
/// seems to do nothing. Either UIKit never re-reads our preference when
/// asked, or it reads it and the system declines to grant the lock. The
/// read counter distinguishes the two — if it climbs when we re-arm but
/// the mouse still misbehaves, we're being refused rather than ignored.
final class PointerLockDiagnostics: ObservableObject {
    static let shared = PointerLockDiagnostics()

    /// Manual triggers, so each re-arm mechanism can be tested on its own
    /// instead of firing all three and guessing which one worked.
    static let requestRootSwap = Notification.Name("pointerLockRequestRootSwap")
    static let requestGeometryNudge = Notification.Name("pointerLockRequestGeometryNudge")

    /// How many times UIKit has asked for `prefersPointerLocked`.
    @Published private(set) var reads = 0
    /// What we answered the last time it asked.
    @Published private(set) var lastAnswer = false
    /// How many times we asked UIKit to re-read it.
    @Published private(set) var rearms = 0
    /// What triggered the most recent re-arm attempt.
    @Published private(set) var lastRearmReason = "—"
    /// Reads recorded at the moment of the last re-arm, so it's visible
    /// whether that request produced a read at all.
    private var readsAtLastRearm = 0
    @Published private(set) var readsSinceLastRearm = 0

    /// The last key forwarded to the page, exactly as the page saw it.
    /// Modifier problems are invisible otherwise — this shows whether
    /// Alt actually left the app, which is the difference between "we
    /// never sent it" and "the remote session ignored it".
    @Published private(set) var lastKey = "—"

    private init() {}

    func recordKey(_ description: String) {
        DispatchQueue.main.async { self.lastKey = description }
    }

    func recordRead(_ answer: Bool) {
        // May be called during a UIKit layout pass; hop to the next
        // runloop turn so publishing never mutates state mid-render.
        DispatchQueue.main.async {
            self.reads += 1
            self.lastAnswer = answer
            self.readsSinceLastRearm = self.reads - self.readsAtLastRearm
        }
    }

    func recordRearm(_ reason: String) {
        DispatchQueue.main.async {
            self.rearms += 1
            self.lastRearmReason = reason
            self.readsAtLastRearm = self.reads
            self.readsSinceLastRearm = 0
        }
    }
}
