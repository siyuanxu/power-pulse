import AppKit
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let reader = PowerReader()
    private let historyStore = PowerHistoryStore()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pausedItem: NSMenuItem!
    private var batteryStatusItem: NSMenuItem!
    private var historyWindowController: PowerHistoryWindowController?
    private var isPaused = false
    private var lastWidgetReload = Date.distantPast
    private var lastPowerForWidget: Double?
    private var lastExternalConnectedForWidget: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeStatusItem()
        refresh()
        if CommandLine.arguments.contains("--show-history") {
            DispatchQueue.main.async { [weak self] in self?.showPowerHistory() }
        }
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
        historyStore.flush()
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusBarImage(percent: nil, isCharging: false)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = "— W"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusItem.button?.toolTip = "Power Pulse · 实时供电与电脑用电"

        let menu = NSMenu()
        menu.delegate = self
        batteryStatusItem = NSMenuItem(title: "电池电量：—%", action: nil, keyEquivalent: "")
        batteryStatusItem.isEnabled = false
        let historyItem = NSMenuItem(title: "打开功率曲线…", action: #selector(showPowerHistory), keyEquivalent: "g")
        historyItem.target = self
        let helpItem = NSMenuItem(title: "如何添加桌面小组件…", action: #selector(showWidgetHelp), keyEquivalent: "")
        helpItem.target = self
        pausedItem = NSMenuItem(title: "暂停菜单栏刷新", action: #selector(togglePaused), keyEquivalent: "")
        pausedItem.target = self
        menu.addItem(batteryStatusItem)
        menu.addItem(.separator())
        menu.addItem(historyItem)
        menu.addItem(.separator())
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

    @objc private func showPowerHistory() {
        if historyWindowController == nil {
            historyWindowController = PowerHistoryWindowController(store: historyStore)
        }
        historyWindowController?.present()
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
        do {
            let snapshot = try reader.read()
            historyStore.record(snapshot)
            if !isPaused {
                statusItem.button?.image = statusBarImage(
                    percent: snapshot.batteryPercent,
                    isCharging: snapshot.externalConnected
                        && (snapshot.isCharging || (snapshot.batteryPowerW ?? 0) > 0.3)
                )
                let percentText = snapshot.batteryPercent.map { "\($0)%" } ?? "—%"
                batteryStatusItem.title = "电池电量：\(percentText)"
                batteryStatusItem.image = statusItem.button?.image
                if let power = snapshot.displayPowerW {
                    statusItem.button?.title = String(format: "%.1f W", power)
                    statusItem.button?.toolTip = "Power Pulse · \(snapshot.stateText) · \(snapshot.displayPowerLabel)"
                } else {
                    statusItem.button?.title = "— W"
                }
            }
            requestWidgetRefreshIfNeeded(snapshot: snapshot)
        } catch {
            if !isPaused {
                statusItem.button?.title = "读取失败"
                batteryStatusItem.title = "电池电量：—%"
            }
        }
    }

    private func statusBarImage(percent: Int?, isCharging: Bool) -> NSImage? {
        let description = isCharging ? "电池正在充电" : "电池电量 \(percent.map(String.init) ?? "未知")%"
        let imageSize = NSSize(width: isCharging ? 35 : 29, height: 14)
        let image = NSImage(size: imageSize, flipped: false) { bounds in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let body = NSBezierPath(
                roundedRect: NSRect(x: 0.75, y: 1.25, width: 25, height: 11.5),
                xRadius: 2.2,
                yRadius: 2.2
            )
            body.lineWidth = 1.15
            body.stroke()

            let terminal = NSBezierPath(
                roundedRect: NSRect(x: 26.4, y: 4.25, width: 1.8, height: 5.5),
                xRadius: 0.7,
                yRadius: 0.7
            )
            terminal.fill()

            let levelText = percent.map { String(max(0, min(100, $0))) } ?? "--"
            let font = NSFont.monospacedDigitSystemFont(
                ofSize: levelText.count == 3 ? 7.5 : 8.5,
                weight: .semibold
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ]
            (levelText as NSString).draw(
                in: NSRect(x: 2, y: 1.8, width: 22, height: 10),
                withAttributes: attributes
            )

            if isCharging {
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: 32.4, y: 12.2))
                bolt.line(to: NSPoint(x: 29.2, y: 7.4))
                bolt.line(to: NSPoint(x: 31.5, y: 7.4))
                bolt.line(to: NSPoint(x: 29.8, y: 1.8))
                bolt.line(to: NSPoint(x: 34.7, y: 8.4))
                bolt.line(to: NSPoint(x: 32.2, y: 8.4))
                bolt.close()
                bolt.fill()
            }
            return bounds.width > 0
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    private func requestWidgetRefreshIfNeeded(snapshot: PowerSnapshot) {
        let power = snapshot.displayPowerW
        let powerChangedEnough: Bool
        if let power, let previous = lastPowerForWidget {
            powerChangedEnough = abs(power - previous) >= 1.0
        } else {
            powerChangedEnough = power != nil || lastPowerForWidget != nil
        }
        let sourceChanged = lastExternalConnectedForWidget != snapshot.externalConnected
        guard (powerChangedEnough || sourceChanged), Date().timeIntervalSince(lastWidgetReload) >= 60 else { return }
        lastPowerForWidget = power
        lastExternalConnectedForWidget = snapshot.externalConnected
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: "PowerPulseWidget")
    }
}
