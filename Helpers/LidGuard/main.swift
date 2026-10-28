import Darwin
import Foundation
import IOKit.ps
import Security

func ownerSnapshot(_ pid: pid_t, uid: uid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = MemoryLayout<proc_bsdinfo>.size
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size,
          info.pbi_uid == uid, info.pbi_status != 5 else { return nil }
    return info
}

func isSignedApp(_ pid: pid_t) -> Bool {
    var code: SecCode?
    let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
          let code else { return false }
    var requirement: SecRequirement?
    let text = "anchor apple generic and certificate leaf[subject.OU] = \"H8QG3CBM96\" and identifier \"com.mishanevazhno.caffeinate\""
    guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
          let requirement else { return false }
    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
}

final class StopFlag {
    private let lock = NSLock()
    private var value = false
    func request() { lock.lock(); value = true; lock.unlock() }
    var requested: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

final class PowerChanges { var changed = true }

guard geteuid() == 0 else { fputs("Administrator authorization is required.\n", stderr); exit(77) }
guard CommandLine.arguments.count == 4,
      let pid = Int32(CommandLine.arguments[2]), pid > 1,
      let uid = UInt32(CommandLine.arguments[3]), uid > 0,
      let owner = ownerSnapshot(pid, uid: uid), isSignedApp(pid) else { exit(78) }
let leasePath = CommandLine.arguments[1]
guard ClosedLidLease.read(from: leasePath, ownerUID: uid)?.isValid(at: Date().timeIntervalSince1970) == true else { exit(78) }

// Serialize the global setting across users and duplicate app instances.
let lockFD = open("/var/run/com.mishanevazhno.caffeinate.lidguard.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(75) }
defer { close(lockFD) }

let stop = StopFlag()
let signals = [SIGTERM, SIGINT, SIGHUP].map { number -> DispatchSourceSignal in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler { stop.request() }
    source.resume()
    return source
}
defer { signals.forEach { $0.cancel() } }

let changes = PowerChanges()
let context = Unmanaged.passUnretained(changes).toOpaque()
let powerSource = IOPSNotificationCreateRunLoopSource({ context in
    if let context { Unmanaged<PowerChanges>.fromOpaque(context).takeUnretainedValue().changed = true }
}, context)?.takeRetainedValue()
if let powerSource { CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode) }
defer { if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), powerSource, .defaultMode) } }

let session = SleepOverrideSession()
// This runs on normal exit, owner death, stale/missing lease, timer expiration,
// a power-setting failure, and handled termination signals.
defer {
    for _ in 0..<10 {
        do { try session.finish(); break }
        catch { Thread.sleep(forTimeInterval: 0.5) }
    }
}
do {
    try session.begin()
    var nextCheck = Date.distantPast
    while !stop.requested {
        let now = Date()
        guard let currentOwner = ownerSnapshot(pid, uid: uid),
              currentOwner.pbi_start_tvsec == owner.pbi_start_tvsec,
              currentOwner.pbi_start_tvusec == owner.pbi_start_tvusec,
              ClosedLidLease.read(from: leasePath, ownerUID: uid)?.isValid(at: now.timeIntervalSince1970) == true else { break }
        if changes.changed || now >= nextCheck {
            try session.ensureAwake()
            changes.changed = false
            nextCheck = now.addingTimeInterval(5)
        }
        let iteration = Date()
        RunLoop.current.run(until: iteration.addingTimeInterval(0.5))
        let remainder = 0.5 - Date().timeIntervalSince(iteration)
        if remainder > 0 { Thread.sleep(forTimeInterval: remainder) }
    }
} catch {
    // Defer above restores the captured setting even after a partial failure.
    fputs("Closed-lid session ended because the system setting could not be maintained.\n", stderr)
}
