import Foundation
import QuartzCore

/// Notices when the main thread stops answering — what shows up as the spinning beachball —
/// and writes down how long it lasted and what the app was doing.
final class StallWatchdog: @unchecked Sendable {
    static let shared = StallWatchdog()

    struct Stall { var activity: String; var ms: Double }

    private let queue = DispatchQueue(label: "KoiPond.watchdog", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var pingSentAt: CFTimeInterval?
    private var activity = "idle"
    private var stuckDuring: String?
    private var recorded: [Stall] = []
    private var logURL: URL?

    /// Anything slower than this counts as a stall.
    let threshold: CFTimeInterval = 0.25

    func start(logToDisk: Bool) {
        if logToDisk {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/KoiPond")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logURL = dir.appendingPathComponent("stalls.log")
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1, leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.ping() }
        t.resume()
        timer = t
    }

    /// Labels the main-thread work in `body`, so a stall inside it is attributed correctly.
    func during<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        lock.lock(); let previous = activity; activity = label; lock.unlock()
        defer { lock.lock(); activity = previous; lock.unlock() }
        return try body()
    }

    /// Stalls recorded since the last call.
    func drain() -> [Stall] {
        lock.lock(); defer { lock.unlock() }
        let out = recorded
        recorded = []
        return out
    }

    private func ping() {
        let now = CACurrentMediaTime()
        lock.lock()
        if let sent = pingSentAt {
            // Still waiting on the last ping: note what the main thread was busy with while it's stuck.
            if stuckDuring == nil && now - sent > threshold { stuckDuring = activity }
            lock.unlock()
            return
        }
        pingSentAt = now
        lock.unlock()
        DispatchQueue.main.async { [self] in pong() }
    }

    private func pong() {
        let now = CACurrentMediaTime()
        lock.lock()
        guard let sent = pingSentAt else { lock.unlock(); return }
        pingSentAt = nil
        let late = now - sent
        let what = stuckDuring ?? activity
        stuckDuring = nil
        let stall = late > threshold ? Stall(activity: what, ms: late * 1000) : nil
        if let stall { recorded.append(stall) }
        lock.unlock()
        if let stall { write(stall) }
    }

    private func write(_ stall: Stall) {
        guard let logURL else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) stall \(Int(stall.ms))ms during \(stall.activity)\n"
        queue.async {
            // Keep the log small: start over once it passes 256 KB.
            let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
            if size > 256 * 1024 { try? FileManager.default.removeItem(at: logURL) }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: logURL)
            }
        }
    }
}

/// Collects frame-to-frame intervals for the debug tour.
final class FrameMeter {
    static let shared = FrameMeter()
    private(set) var intervals: [Double] = []
    var enabled = false

    func record(_ interval: TimeInterval) {
        guard enabled else { return }
        intervals.append(interval * 1000)
    }

    func drain() -> [Double] {
        let out = intervals
        intervals = []
        return out
    }
}
