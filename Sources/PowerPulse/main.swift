import AppKit
import Foundation

if CommandLine.arguments.contains("--diagnose") {
    do {
        let value = try PowerReader().read()
        func show(_ number: Double?, decimals: Int = 2) -> String {
            guard let number else { return "不可用" }
            return String(format: "%.*f", decimals, number)
        }
        print("Power Pulse 本机诊断")
        print("当前主功率: \(value.displayPowerLabel) · \(show(value.displayPowerW)) W")
        print("Mac 侧输入: \(show(value.inputPowerW)) W")
        print("整机功耗: \(show(value.systemLoadW)) W")
        print("实时参数: \(show(value.inputVoltageV)) V / \(show(value.inputCurrentA)) A")
        print("充电器额定: \(show(value.ratedPowerW, decimals: 0)) W")
        print("协议: \(value.protocolName) · \(value.contractDescription ?? "合约未知")")
        print("电池: \(value.batteryPercent.map(String.init) ?? "未知")% · \(value.stateText)")
        print("电池净功率: \(show(value.batteryPowerW)) W（正值充入，负值放出）")
        print("遥测可用: \(value.telemetryAvailable ? "是" : "否")")
        exit(value.telemetryAvailable ? EXIT_SUCCESS : EXIT_FAILURE)
    } catch {
        fputs("Power Pulse 诊断失败: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
