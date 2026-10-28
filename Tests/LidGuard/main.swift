import Darwin
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
}

let now = Date().timeIntervalSince1970
let unlimited = ClosedLidLease(enabled: true, updatedAt: now, deadline: nil)
require(unlimited.isValid(at: now + 5), "a live unlimited lease remains valid")
require(!unlimited.isValid(at: now + 31), "a stopped heartbeat releases the closed-lid session")
require(!ClosedLidLease(enabled: false, updatedAt: now, deadline: nil).isValid(at: now), "switching off invalidates the lease")
require(!ClosedLidLease(enabled: true, updatedAt: now, deadline: now).isValid(at: now), "the deadline expires independently of the app timer")
require(!ClosedLidLease(enabled: true, updatedAt: now, deadline: .infinity).isValid(at: now), "non-finite deadlines fail closed")
require(!ClosedLidLease(enabled: true, updatedAt: now + 60, deadline: nil).isValid(at: now), "future-dated heartbeats do not create a permanent override")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinate-lease-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: directory) }
let leaseURL = directory.appendingPathComponent("lease.json")
try JSONEncoder().encode(unlimited).write(to: leaseURL)
require(ClosedLidLease.read(from: leaseURL.path, ownerUID: getuid()) != nil, "the helper reads its owner's lease")
require(ClosedLidLease.read(from: leaseURL.path, ownerUID: getuid() + 1) == nil, "a different user's lease is rejected")
let link = directory.appendingPathComponent("link.json")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: leaseURL)
require(ClosedLidLease.read(from: link.path, ownerUID: getuid()) == nil, "the privileged reader rejects symlinks")
try Data(repeating: 0, count: 3000).write(to: leaseURL)
require(ClosedLidLease.read(from: leaseURL.path, ownerUID: getuid()) == nil, "oversized control files are rejected")
let absent = try SystemSleepSetting.parse("System-wide power settings:\nCurrently in use:\n sleep 1\n")
let present = try SystemSleepSetting.parse("System-wide power settings:\n SleepDisabled 1\n")
require(!absent, "an absent override means normal sleep")
require(present, "the native setting parser detects the override")

var power = false
var writes: [Bool] = []
let session = SleepOverrideSession(read: { power }, write: { power = $0; writes.append($0) })
try session.begin()
require(power && writes == [true], "starting the guard disables system sleep")
power = false
try session.ensureAwake()
require(power && writes == [true, true], "a reset after a power-source change is repaired")
try session.finish()
require(!power && writes.last == false, "finishing restores the original sleep setting")
let finishedCount = writes.count
try session.finish()
require(writes.count == finishedCount, "repeated cleanup does not rewrite the setting")

power = true
let existing = SleepOverrideSession(read: { power }, write: { power = $0 })
try existing.begin()
try existing.finish()
require(power, "an override that existed before the session is preserved")

enum SimulatedFailure: Error { case write }
power = false
var failOnce = true
let partial = SleepOverrideSession(read: { power }, write: {
    power = $0
    if failOnce { failOnce = false; throw SimulatedFailure.write }
})
do { try partial.begin() } catch { }
try partial.finish()
require(!power, "a partial startup failure still restores the original setting")

let source = ClosedLidController.authorizationScript(helper: "/tmp/Coffee's \"quoted\" $name/guard", lease: "/tmp/a'b/lease.json", pid: 123, uid: 501)
var compileError: NSDictionary?
let script = NSAppleScript(source: source)!
require(script.compileAndReturnError(&compileError), "the authorization script safely handles quoted paths")
require(source.hasSuffix("with administrator privileges"), "authorization goes through the native macOS prompt")
print("All closed-lid checks passed without changing system power settings.")
