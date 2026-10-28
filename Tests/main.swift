import Darwin
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
}

func waitFor(_ predicate: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(4)
    repeat {
        if predicate() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < end
    return false
}

func assertions(for pid: Int32) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try! task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n")
        .filter { $0.contains("pid \(pid)(caffeinate)") }.joined(separator: "\n")
}

if CommandLine.arguments.contains("--orphan-owner") {
    let session = CaffeinateSession()
    try session.start(keepDisplayAwake: false, until: nil)
    let pid = session.processIdentifier!
    guard waitFor({ assertions(for: pid).contains("PreventUserIdleSystemSleep") }) else { exit(2) }
    FileHandle.standardOutput.write(Data("\(pid)".utf8))
    // Simulate a crash: skip Swift destructors and application termination hooks.
    _exit(0)
}

let session = CaffeinateSession()
defer { session.stop() }
try session.start(keepDisplayAwake: false, until: nil)
let firstPID = session.processIdentifier!
require(waitFor { assertions(for: firstPID).contains("PreventUserIdleSystemSleep") }, "macOS registers the idle-sleep assertion")
require(!assertions(for: firstPID).contains("PreventUserIdleDisplaySleep"), "screen may sleep by default")

try session.start(keepDisplayAwake: true, until: nil)
let secondPID = session.processIdentifier!
require(firstPID != secondPID, "settings replace the owned session")
require(waitFor { assertions(for: firstPID).isEmpty }, "replacement releases the old assertions")
require(waitFor { assertions(for: secondPID).contains("PreventUserIdleDisplaySleep") }, "optional display protection reaches macOS")
session.stop()
require(!session.isRunning && assertions(for: secondPID).isEmpty, "switching off releases all owned assertions")

try session.start(keepDisplayAwake: false, until: Date().addingTimeInterval(1))
let timedPID = session.processIdentifier!
require(waitFor { assertions(for: timedPID).contains("PreventUserIdleSystemSleep") }, "timed session starts")
require(waitFor { !session.isRunning && assertions(for: timedPID).isEmpty }, "caffeinate releases protection when the timer expires")

let owner = Process()
owner.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
owner.arguments = ["--orphan-owner"]
let output = Pipe()
owner.standardOutput = output
try owner.run()
let orphanPID = Int32(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
owner.waitUntilExit()
require(owner.terminationStatus == 0 && orphanPID != nil, "crash simulation creates a live owned assertion")
require(waitFor { assertions(for: orphanPID!).isEmpty }, "owner exit cleans up protection without termination hooks")
print("All integration checks passed.")
