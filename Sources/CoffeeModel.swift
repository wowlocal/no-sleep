import AppKit
import Combine
import ServiceManagement

enum DurationChoice: Int, CaseIterable, Identifiable {
    case halfHour = 1800, hour = 3600, twoHours = 7200, unlimited = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .halfHour: return "30 мин"
        case .hour: return "1 час"
        case .twoHours: return "2 часа"
        case .unlimited: return "∞"
        }
    }
}

final class CoffeeModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remaining = ""
    @Published private(set) var duration: DurationChoice?
    @Published private(set) var cupsAdded = 0
    @Published private(set) var remainingFraction = 0.0
    @Published var keepDisplayAwake: Bool {
        didSet {
            defaults.set(keepDisplayAwake, forKey: "keepDisplayAwake")
            if isActive { enable(resetDeadline: false) }
        }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var error: String?
    let closedLid = ClosedLidController()

    private let session = CaffeinateSession()
    private let defaults: UserDefaults
    private let now: () -> Date
    private var configuredSeconds: Int
    private(set) var deadline: Date?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var closedLidObserver: AnyCancellable?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, observeSystemEvents: Bool = true) {
        self.defaults = defaults
        self.now = now
        let legacy = DurationChoice(rawValue: defaults.integer(forKey: "duration")) ?? .unlimited
        configuredSeconds = max(0, defaults.object(forKey: "sessionSeconds") as? Int ?? legacy.rawValue)
        duration = DurationChoice(rawValue: configuredSeconds)
        keepDisplayAwake = defaults.bool(forKey: "keepDisplayAwake")
        closedLid.onError = { [weak self] message in self?.error = message }
        closedLidObserver = closedLid.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if observeSystemEvents {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.tick() }
        }
        // Opening the app begins a fresh session; manually switching it off is remembered.
        if defaults.object(forKey: "enabled") == nil || defaults.bool(forKey: "enabled") {
            enable(resetDeadline: true)
        }
    }

    func toggle() {
        if isActive { disable() } else { enable(resetDeadline: true) }
    }

    func selectDuration(_ choice: DurationChoice) {
        configuredSeconds = choice.rawValue
        duration = choice
        cupsAdded = 0
        defaults.set(configuredSeconds, forKey: "sessionSeconds")
        if isActive { enable(resetDeadline: true) }
    }

    /// Add to the existing deadline so elapsed time is never silently reset.
    /// Unlimited, expired and stopped sessions start a fresh thirty minutes.
    func addCup() {
        let current = now()
        let continues = isActive && (deadline.map { $0 > current } ?? false)
        let base = continues ? deadline! : current
        configuredSeconds = continues ? configuredSeconds + 1800 : 1800
        deadline = base.addingTimeInterval(1800)
        duration = DurationChoice(rawValue: configuredSeconds)
        cupsAdded = continues ? cupsAdded + 1 : 1
        defaults.set(configuredSeconds, forKey: "sessionSeconds")
        enable(resetDeadline: false)
    }

    func disable() {
        closedLid.disable()
        session.stop()
        isActive = false
        deadline = nil
        remaining = ""
        remainingFraction = 0
        cupsAdded = 0
        defaults.set(false, forKey: "enabled")
    }

    func shutdown() { closedLid.shutdown(); session.stop() }

    func setClosedLidEnabled(_ enabled: Bool) {
        if enabled {
            if !isActive { enable(resetDeadline: true) }
            if isActive { closedLid.enable(until: deadline) }
        } else { closedLid.disable() }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                error = "Разрешите автозапуск в Системных настройках → Основные → Объекты входа."
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            self.error = "Не удалось изменить автозапуск: \(error.localizedDescription)"
        }
    }

    private func enable(resetDeadline: Bool) {
        if resetDeadline { deadline = configuredSeconds == 0 ? nil : now().addingTimeInterval(Double(configuredSeconds)) }
        do {
            try session.start(keepDisplayAwake: keepDisplayAwake, until: deadline)
            isActive = true
            error = nil
            defaults.set(true, forKey: "enabled")
            closedLid.update(until: deadline)
            updateRemaining()
        } catch {
            disable()
            self.error = "Не удалось включить: \(error.localizedDescription)"
        }
    }

    func tick() {
        guard isActive else { return }
        if let deadline, deadline <= now() { disable(); return }
        guard session.isRunning else {
            disable()
            error = "Режим завершился. Нажмите «Включить», чтобы запустить снова."
            return
        }
        updateRemaining()
    }

    private func updateRemaining() {
        guard let deadline else { remaining = "До выключения вручную"; remainingFraction = 1; return }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        remainingFraction = min(1, Double(seconds) / Double(max(1, configuredSeconds)))
        remaining = String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}
