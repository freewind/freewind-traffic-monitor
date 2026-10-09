import Foundation
import Combine
import SwiftUI
import TrafficMonitorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var store: SQLiteStore?
    private var scheduler: SamplingScheduler?
    private var model: TrafficViewModel?
    private var signalSources: [DispatchSourceSignal] = []
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = makeStore()
        let model = TrafficViewModel(store: store)
        self.store = store
        self.model = model

        setupStatusItem()
        observeRates(model)
        installSignalHandlers()
        startSampling(store: store, model: model)

        // 便于自动化验证：启动时直接打开主窗口。
        if ProcessInfo.processInfo.environment["TM_OPEN_WINDOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.flush()
        scheduler?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func makeStore() -> SQLiteStore? {
        do {
            return try SQLiteStore(path: SQLiteStore.defaultPath())
        } catch {
            FileHandle.standardError.write(Data("无法打开数据库: \(error)\n".utf8))
            return nil
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "TM"
            button.toolTip = "freewind-traffic-monitor"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开主窗口", action: #selector(openWindow), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func openWindow() {
        showWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// 被 kill 或 LaunchAgent 停止时也能正常收尾，把最后一段流量落库。
    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func observeRates(_ model: TrafficViewModel) {
        model.$downloadRate
            .combineLatest(model.$uploadRate)
            .sink { [weak self] download, upload in
                self?.statusItem?.button?.title =
                    "↓\(ByteFormat.rate(download)) ↑\(ByteFormat.rate(upload))"
            }
            .store(in: &cancellables)
    }

    private func startSampling(store: SQLiteStore?, model: TrafficViewModel) {
        guard let store else {
            return
        }

        let interval = ProcessInfo.processInfo.environment["TM_INTERVAL"].flatMap(Double.init) ?? 5
        let scheduler = SamplingScheduler(store: store, interval: interval)
        scheduler.onError = { error in
            FileHandle.standardError.write(Data("采样失败: \(error)\n".utf8))
        }
        scheduler.onSample = { sample in
            Task { @MainActor in
                model.apply(sample, interval: interval)
            }
        }
        scheduler.start()
        self.scheduler = scheduler
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let model else {
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "freewind-traffic-monitor"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
