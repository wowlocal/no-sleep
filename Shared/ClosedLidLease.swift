import Darwin
import Foundation

struct ClosedLidLease: Codable {
    let enabled: Bool
    let updatedAt: TimeInterval
    let deadline: TimeInterval?

    func isValid(at now: TimeInterval) -> Bool {
        guard enabled, updatedAt.isFinite, now.isFinite,
              now - updatedAt >= -5, now - updatedAt < 30 else { return false }
        return deadline.map { $0.isFinite && $0 > now } ?? true
    }

    /// The privileged helper never follows a symlink or reads another user's file.
    static func read(from path: String, ownerUID: uid_t) -> ClosedLidLease? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == ownerUID,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= 2048 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count else { return nil }
        return try? JSONDecoder().decode(ClosedLidLease.self, from: Data(bytes))
    }
}

enum SleepSettingError: Error { case unavailable, commandFailed }

enum SystemSleepSetting {
    static func parse(_ output: String) throws -> Bool {
        guard output.contains("System-wide power settings:") else { throw SleepSettingError.unavailable }
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled" {
                guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else { throw SleepSettingError.unavailable }
                return fields[1] == "1"
            }
        }
        return false
    }

    static func read() throws -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw SleepSettingError.commandFailed }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    static func set(_ disabled: Bool) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        // These are the only two commands the privileged helper can execute.
        task.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0, try read() == disabled else { throw SleepSettingError.commandFailed }
    }
}

/// Shared with tests so cleanup and preservation of an existing override are
/// exercised without ever changing the test machine's power settings.
final class SleepOverrideSession {
    private let read: () throws -> Bool
    private let write: (Bool) throws -> Void
    private var original: Bool?

    init(read: @escaping () throws -> Bool = SystemSleepSetting.read,
         write: @escaping (Bool) throws -> Void = SystemSleepSetting.set) {
        self.read = read
        self.write = write
    }

    func begin() throws {
        original = try read()
        try ensureAwake()
    }

    func ensureAwake() throws { if try !read() { try write(true) } }

    func finish() throws {
        guard let original else { return }
        if try read() != original { try write(original) }
        self.original = nil
    }
}
