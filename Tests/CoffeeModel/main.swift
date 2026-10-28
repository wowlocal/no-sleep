import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
}

let suite = "com.mishanevazhno.caffeinate.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set(false, forKey: "enabled")
var current = Date()
let model = CoffeeModel(defaults: defaults, now: { current }, observeSystemEvents: false)
defer { model.shutdown() }

model.addCup()
require(model.isActive && model.deadline == current.addingTimeInterval(1800), "one cup starts thirty minutes from a stopped session")
let originalDeadline = model.deadline!
current = current.addingTimeInterval(600)
model.tick()
require(model.remaining == "0:20:00", "elapsed time is reflected in the countdown")
model.addCup()
require(model.deadline == originalDeadline.addingTimeInterval(1800) && model.remaining == "0:50:00", "another cup adds thirty minutes without resetting elapsed time")
require(model.cupsAdded == 2 && model.remainingFraction < 1, "cup count and remaining-time ring track the session")
model.addCup()
require(model.duration == nil && model.remaining == "1:20:00", "three cups support a duration between the presets")
let deadlineBeforeScreenChange = model.deadline
model.keepDisplayAwake.toggle()
require(model.deadline == deadlineBeforeScreenChange, "display settings preserve the accumulated deadline")

model.selectDuration(.unlimited)
require(model.isActive && model.deadline == nil && model.cupsAdded == 0, "unlimited mode remains available")
model.addCup()
require(model.deadline == current.addingTimeInterval(1800) && model.cupsAdded == 1, "a cup converts unlimited mode to a fresh thirty-minute timer")
current = current.addingTimeInterval(1900)
model.tick()
require(!model.isActive, "the accumulated timer stops protection when it expires")
model.addCup()
require(model.deadline == current.addingTimeInterval(1800) && model.cupsAdded == 1, "a cup after expiration starts a fresh session")
model.addCup()
model.addCup()
model.shutdown()
let restored = CoffeeModel(defaults: defaults, now: { current }, observeSystemEvents: false)
defer { restored.shutdown() }
require(restored.isActive && restored.deadline == current.addingTimeInterval(5400), "a custom coffee duration is remembered on reopening")
print("All coffee timer checks passed.")
