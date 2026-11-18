import Foundation
import Network

enum Connectivity {
    /// True on mobile data or a personal hotspot. Answers once, from the first path update.
    static func isExpensive() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let once = Once()
            monitor.pathUpdateHandler = { path in
                once.run {
                    continuation.resume(returning: path.isExpensive)
                    monitor.cancel()
                }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
    }
}

/// Runs its block the first time only, from any thread.
final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func run(_ block: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
    }
}
