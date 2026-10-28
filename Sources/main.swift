import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct CoffeeView: View {
    @ObservedObject var model: CoffeeModel
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var durationSelection
    @State private var showInfo = false
    private var activeFill: Color { colorScheme == .dark ? Color(white: 0.94) : Color(white: 0.16) }
    private var activeInk: Color { colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.secondary)
                Text("Кофеин").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: model.isActive ? "checkmark.circle.fill" : "minus.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(model.isActive ? "Работает" : "Выключен").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(model.isActive ? activeInk : Color.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(model.isActive ? activeFill : .clear, in: Capsule())
                .coffeeGlass(in: Capsule())
            }
            .padding(.bottom, compact ? 12 : 16)

            if !compact {
                CoffeeCupButton(model: model).padding(.bottom, 8)
            }

            Text(model.isActive ? (model.duration == .unlimited ? "∞" : model.remaining) : "Пауза")
                .font(.system(size: compact ? 22 : 28, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(model.isActive ? 0.85 : 0.55))
                .frame(height: compact ? 30 : 38)
                .padding(.bottom, compact ? 12 : 17)
                .help(model.duration == .unlimited ? "Без таймера" : "Оставшееся время")

            HStack(spacing: 8) {
              Button(action: model.toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                    Text(model.isActive ? "Выключить" : "Включить")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).frame(height: compact ? 36 : 42)
                .coffeeGlass(in: Capsule(), interactive: true)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .keyboardShortcut(.space, modifiers: [])
              .accessibilityIdentifier("toggleCaffeinate")
              if compact { CoffeeCupButton(model: model, compact: true) }
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Таймер").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label("×\(model.cupsAdded)", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .opacity(model.cupsAdded > 0 ? 1 : 0)
                        .accessibilityHidden(model.cupsAdded == 0)
                }
                HStack(spacing: 3) {
                    ForEach(DurationChoice.allCases) { choice in
                        Button { model.selectDuration(choice) } label: {
                            Text(choice.title)
                                .font(.system(size: 11, weight: model.duration == choice ? .medium : .regular))
                                .foregroundStyle(model.duration == choice ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity).frame(height: 27)
                                .background {
                                    if model.duration == choice {
                                        Capsule().fill(.clear)
                                            .coffeeGlass(in: Capsule(), interactive: true)
                                            .matchedGeometryEffect(id: "selectedDuration", in: durationSelection)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice == .unlimited ? "Без таймера" : choice.title)
                        .accessibilityValue(model.duration == choice ? "Выбрано" : "")
                    }
                }
                .padding(3)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.duration)
                .help("Смена длительности запускает таймер заново")

                HStack {
                    Text("Не гасить экран")
                    Spacer()
                    Toggle("Не гасить экран", isOn: $model.keepDisplayAwake).labelsHidden()
                }
                .toggleStyle(QuietToggleStyle(label: "Не гасить экран")).font(.system(size: 12))
                HStack {
                    Text("Автозапуск")
                    Spacer()
                    Toggle("Открывать при входе", isOn: Binding(
                        get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
                    )).labelsHidden()
                }
                .toggleStyle(QuietToggleStyle(label: "Открывать при входе")).font(.system(size: 12))
            }
            .padding(compact ? 12 : 14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5))
            .padding(.top, compact ? 13 : 17)

            HStack {
                Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Как это работает")
                    .help("Как это работает")
                    .popover(isPresented: $showInfo) {
                        Text("Оставьте крышку открытой. Закрытие окна не выключает Кофеин. У Wi-Fi может быть свой лимит сессии.")
                            .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            .frame(width: 230, alignment: .leading).padding(14)
                    }
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.top, 12)
        }
        .padding(compact ? 16 : 22)
        .padding(.top, compact ? 0 : 16)
        .frame(width: compact ? 320 : 354)
        .alert("Кофеин", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct CoffeeCupButton: View {
    @ObservedObject var model: CoffeeModel
    var compact = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    @State private var bursts: [UUID] = []
    @State private var burstMinutes = 0
    private var fill: Color { colorScheme == .dark ? Color(white: 0.94) : Color(white: 0.16) }
    private var ink: Color { colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98) }

    var body: some View {
        Button(action: pour) {
            Group {
                if compact {
                    HStack(spacing: 5) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("+30").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 76, height: 36)
                    .coffeeGlass(in: Capsule(), interactive: true)
                } else {
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            ZStack {
                                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 2)
                                Circle().trim(from: 0, to: model.remainingFraction)
                                    .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.remainingFraction)
                                Image(systemName: model.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                                    .font(.system(size: 27))
                                    .foregroundStyle(model.isActive ? ink : Color.secondary)
                                    .frame(width: 64, height: 64)
                                    .background(model.isActive ? fill : .clear, in: Circle())
                                    .coffeeGlass(in: Circle(), interactive: true)
                            }
                            .frame(width: 78, height: 78)
                            if model.isActive {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(fill)
                                    .frame(width: 21, height: 21).background(ink, in: Circle())
                                    .overlay(Circle().strokeBorder(fill, lineWidth: 2))
                                    .offset(x: -2, y: -2)
                            }
                        }
                        Text("+30 мин")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.75)).frame(height: 14)
                    }
                }
            }
            .scaleEffect(!reduceMotion && bounce ? 1.07 : 1)
            .rotationEffect(.degrees(!reduceMotion && bounce ? -4 : 0))
            .overlay(alignment: .top) {
                ZStack { ForEach(bursts, id: \.self) { _ in CoffeeTimeBurst(minutes: burstMinutes, reduceMotion: reduceMotion) } }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ещё чашку: добавить 30 минут")
        .accessibilityHint("Каждая чашка продлевает таймер. Без таймера первая чашка запускает 30 минут.")
        .accessibilityIdentifier("pourCoffee")
        .help(model.duration == .unlimited ? "Чашка запустит таймер на 30 минут" : "Каждая чашка добавляет 30 минут")
    }

    private func pour() {
        model.addCup()
        guard model.isActive else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55)) { bounce = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6)) { bounce = false }
        }
        let id = UUID()
        // Rapid taps form one readable combo rather than overlapping labels.
        burstMinutes = bursts.isEmpty ? 30 : burstMinutes + 30
        bursts = [id]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { bursts.removeAll { $0 == id } }
    }
}

struct CoffeeTimeBurst: View {
    let minutes: Int
    let reduceMotion: Bool
    @State private var floating = false
    var body: some View {
        Text("+\(minutes) мин")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .offset(y: reduceMotion ? -24 : floating ? -48 : -4)
            .opacity(floating ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.8 : 0.95)) { floating = true } }
    }
}

extension View {
    @ViewBuilder
    func coffeeGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
    }
}

struct QuietToggleStyle: ToggleStyle {
    let label: String
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(Color.primary.opacity(configuration.isOn ? 0.48 : 0.12))
                .frame(width: 28, height: 16)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(Color(white: 0.95)).frame(width: 12, height: 12)
                        .coffeeGlass(in: Circle(), interactive: true).padding(2)
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
        .accessibilityLabel(label)
        .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CoffeeModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow!
    private var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let content = CoffeeView(model: model)
        let naturalSize = NSHostingView(rootView: content).fittingSize
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 24
        let height = min(naturalSize.height, availableHeight)
        let host = NSHostingController(rootView:
            ScrollView(.vertical, showsIndicators: naturalSize.height > height) { content }
                .frame(width: 354, height: height).ignoresSafeArea()
        )
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 354, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Кофеин"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        let size = host.view.fittingSize
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.style = .regular
            glass.cornerRadius = 24
            glass.contentView = host.view
            surface = glass
        } else {
            let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.addSubview(host.view)
            surface = material
        }
        host.view.frame = surface.bounds
        host.view.autoresizingMask = [.width, .height]
        let container = NSViewController()
        container.view = surface
        container.addChild(host)
        window.contentViewController = container
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        installMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(showPopover)
            button.setAccessibilityLabel("Кофеин")
        }
        popover.behavior = .transient
        popover.animates = true
        observer = model.$isActive.sink { [weak self] active in
            guard let self else { return }
            let image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: active ? "Кофеин включён" : "Кофеин выключен")
            image?.isTemplate = true
            self.statusItem.button?.image = image
            self.statusItem.button?.toolTip = active ? "Кофеин — Mac не уснёт" : "Кофеин — выключен"
        }
        // Login launches stay in the menu bar. User-initiated launches show the control.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { showWindow() }
    }

    private func installMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let open = NSMenuItem(title: "Показать Кофеин", action: #selector(showWindow), keyEquivalent: "0")
        open.target = self
        appMenu.addItem(open)
        let showMenu = NSMenuItem(title: "Показать меню", action: #selector(showPopover), keyEquivalent: "m")
        showMenu.keyEquivalentModifierMask = [.command, .shift]
        showMenu.target = self
        appMenu.addItem(showMenu)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть Кофеин", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Выйти из Кофеина", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        NSApp.mainMenu = menu
    }

    @objc private func showWindow() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            // A separate compact layout fits short laptop screens. Still cap its
            // height to this status item's actual screen and allow scrolling.
            let content = CoffeeView(model: model, compact: true)
            let naturalSize = NSHostingView(rootView: content).fittingSize
            let visibleHeight = button.window?.screen?.visibleFrame.height ?? 600
            let height = min(naturalSize.height, max(180, visibleHeight - 48))
            popover.contentViewController = NSHostingController(rootView:
                ScrollView(.vertical, showsIndicators: false) { content }
                    .frame(width: 320, height: height)
            )
            popover.contentSize = NSSize(width: 320, height: height)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
