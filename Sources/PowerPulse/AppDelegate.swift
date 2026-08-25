import AppKit
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let reader = PowerReader()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pausedItem: NSMenuItem!
    private var isPaused = false
    private var lastWidgetReload = Date.distantPast
    private var lastPowerForWidget: Double?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeStatusItem()
        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⚡ — W"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusItem.button?.toolTip = "Power Pulse · Mac 侧实时输入功率"

        let menu = NSMenu()
        menu.delegate = self
        let helpItem = NSMenuItem(title: "如何添加桌面小组件…", action: #selector(showWidgetHelp), keyEquivalent: "")
        helpItem.target = self
        pausedItem = NSMenuItem(title: "暂停菜单栏刷新", action: #selector(togglePaused), keyEquivalent: "")
        pausedItem.target = self
        menu.addItem(helpItem)
        menu.addItem(pausedItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Power Pulse", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pausedItem.state = isPaused ? .on : .off
    }

    @objc private func showWidgetHelp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "添加 Power Pulse 桌面小组件"
        alert.informativeText = "在桌面空白处右键，选择“编辑小组件”，搜索 Power Pulse，然后把小号组件拖到桌面。它会占用系统组件网格，桌面文件不会与它重叠。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func togglePaused() {
        isPaused.toggle()
        pausedItem.state = isPaused ? .on : .off
        if !isPaused { refresh() }
    }

    @objc private func timerFired() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refresh() {
        guard !isPaused else { return }
        do {
            let snapshot = try reader.read()
            if let power = snapshot.inputPowerW {
                statusItem.button?.title = String(format: "⚡ %.1f W", power)
            } else {
                statusItem.button?.title = snapshot.externalConnected ? "⚡ — W" : "🔋 电池"
            }
            requestWidgetRefreshIfNeeded(power: snapshot.inputPowerW)
        } catch {
            statusItem.button?.title = "⚡ 读取失败"
        }
    }

    private func requestWidgetRefreshIfNeeded(power: Double?) {
        let changedEnough: Bool
        if let power, let previous = lastPowerForWidget {
            changedEnough = abs(power - previous) >= 1.0
        } else {
            changedEnough = power != nil || lastPowerForWidget != nil
        }
        guard changedEnough, Date().timeIntervalSince(lastWidgetReload) >= 60 else { return }
        lastPowerForWidget = power
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: "PowerPulseWidget")
    }
}
