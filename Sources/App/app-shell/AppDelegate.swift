import AppKit
import SwiftUI
import TrafficMonitorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var store: SQLiteStore?
    private var scheduler: SamplingScheduler?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        installSignalHandlers()
        startSampling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.flush()
        scheduler?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "network", accessibilityDescription: "Traffic Monitor")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
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

    private func startSampling() {
        do {
            let store = try SQLiteStore(path: SQLiteStore.defaultPath())
            let interval = ProcessInfo.processInfo.environment["TM_INTERVAL"].flatMap(Double.init) ?? 5
            let scheduler = SamplingScheduler(store: store, interval: interval)
            scheduler.onError = { error in
                FileHandle.standardError.write(Data("采样失败: \(error)\n".utf8))
            }
            scheduler.start()
            self.store = store
            self.scheduler = scheduler
        } catch {
            FileHandle.standardError.write(Data("无法打开数据库: \(error)\n".utf8))
        }
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "freewind-traffic-monitor"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
