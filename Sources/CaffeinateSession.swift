import Foundation

/// Owns only this application's assertion process. -w also releases assertions
/// if the application crashes or is force-quit.
final class CaffeinateSession {
    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }
    var processIdentifier: Int32? { isRunning ? process?.processIdentifier : nil }

    func start(keepDisplayAwake: Bool, until deadline: Date?) throws {
        let next = Process()
        next.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var arguments = ["-i", "-s", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if keepDisplayAwake { arguments.append("-d") }
        if let deadline {
            arguments += ["-t", String(max(1, Int(ceil(deadline.timeIntervalSinceNow))))]
        }
        next.arguments = arguments
        next.standardOutput = FileHandle.nullDevice
        next.standardError = FileHandle.nullDevice
        // Acquire the replacement before releasing the old assertions.
        try next.run()
        stop()
        process = next
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
    }

    deinit { stop() }
}
