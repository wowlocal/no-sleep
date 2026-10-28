import Combine
import Darwin
import Foundation

final class ClosedLidController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    var onError: ((String) -> Void)?

    private var requested = false
    private var deadline: Date?
    private var leaseURL: URL?
    private var workerPID: pid_t?
    private var authorization: Process?
    private var timer: Timer?
    private var startedAt: Date?
    private var activity: NSObjectProtocol?
    private var generation = 0

    func enable(until deadline: Date?) {
        guard !isBusy, !isEnabled else { return }
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "CaffeinateLidGuard") else {
            onError?("Не найден помощник режима закрытой крышки. Переустановите приложение.")
            return
        }
        generation += 1
        let operation = generation
        self.deadline = deadline
        requested = true
        isBusy = true
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Keep the closed-lid session responsive")
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinate-lid-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            leaseURL = directory.appendingPathComponent("lease.json")
            try writeLease()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            let script = Self.authorizationScript(helper: helper.path, lease: leaseURL!.path,
                                                  pid: ProcessInfo.processInfo.processIdentifier, uid: getuid())
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            let output = Pipe(), errors = Pipe()
            task.standardOutput = output
            task.standardError = errors
            authorization = task
            try task.run()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let pid = Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                let message = String(decoding: errorData, as: UTF8.self)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == operation else { return }
                    self.authorization = nil
                    guard task.terminationStatus == 0, let pid, pid > 1 else {
                        let cancelled = message.contains("-128") || message.localizedCaseInsensitiveContains("canceled")
                        self.finish()
                        if !cancelled { self.onError?("Не удалось получить разрешение администратора для режима закрытой крышки.") }
                        return
                    }
                    self.workerPID = pid
                    self.startedAt = Date()
                    self.tick()
                }
            }
        } catch {
            finish()
            onError?("Не удалось включить режим закрытой крышки: \(error.localizedDescription)")
        }
    }

    func update(until deadline: Date?) {
        self.deadline = deadline
        if requested { do { try writeLease() } catch { fail("Потеряна связь с помощником закрытой крышки.") } }
    }

    func disable() {
        requested = false
        do { try writeLease() } catch { removeLease() }
        if workerPID == nil && authorization == nil { finish() }
        else { isBusy = true }
    }

    func shutdown() {
        generation += 1
        requested = false
        removeLease()
        if authorization?.isRunning == true { authorization?.terminate() }
        authorization = nil
        finish()
    }

    deinit {
        timer?.invalidate()
        removeLease()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    static func authorizationScript(helper: String, lease: String, pid: pid_t, uid: uid_t) -> String {
        func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "/usr/bin/nohup \(shellQuote(helper)) \(shellQuote(lease)) \(pid) \(uid) </dev/null >/dev/null 2>&1 & /bin/echo $!"
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\" with administrator privileges"
    }

    private func tick() {
        if requested, let deadline, deadline <= Date() { disable() }
        do { try writeLease() } catch { fail("Потеряна связь с помощником закрытой крышки."); return }
        guard let workerPID else { return }
        let alive = kill(workerPID, 0) == 0 || errno == EPERM
        guard alive else {
            let unexpected = requested
            finish()
            if unexpected { onError?("Режим закрытой крышки завершился. Включите его снова.") }
            return
        }
        if !requested { return }
        if !isEnabled {
            if (try? SystemSleepSetting.read()) == true { isEnabled = true; isBusy = false }
            else if let startedAt, Date().timeIntervalSince(startedAt) > 5 {
                fail("macOS не подтвердила запрет сна с закрытой крышкой. Попробуйте включить режим снова.")
            }
        }
    }

    private func writeLease() throws {
        guard let leaseURL else { return }
        let lease = ClosedLidLease(enabled: requested, updatedAt: Date().timeIntervalSince1970, deadline: deadline?.timeIntervalSince1970)
        try JSONEncoder().encode(lease).write(to: leaseURL, options: .atomic)
    }

    private func fail(_ message: String) {
        disable()
        onError?(message)
    }

    private func removeLease() {
        if let leaseURL { try? FileManager.default.removeItem(at: leaseURL.deletingLastPathComponent()) }
        leaseURL = nil
    }

    private func finish() {
        requested = false
        timer?.invalidate()
        timer = nil
        removeLease()
        workerPID = nil
        authorization = nil
        startedAt = nil
        isEnabled = false
        isBusy = false
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
}
