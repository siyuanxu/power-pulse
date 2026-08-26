import Foundation
import IOKit
import IOKit.ps

struct PowerSnapshot {
    let readAt: Date
    let inputPowerW: Double?
    let systemLoadW: Double?
    let inputVoltageV: Double?
    let inputCurrentA: Double?
    let batteryVoltageV: Double?
    let batteryCurrentA: Double?
    let ratedPowerW: Double?
    let batteryPowerW: Double?
    let batteryPercent: Int?
    let externalConnected: Bool
    let isCharging: Bool
    let isFullyCharged: Bool
    let protocolName: String
    let contractDescription: String?
    let telemetryAvailable: Bool

    var displayPowerW: Double? {
        if externalConnected { return inputPowerW }
        return systemLoadW ?? batteryPowerW.map(abs)
    }

    var displayPowerLabel: String {
        externalConnected ? "MAC 侧实时输入" : "电脑实时总功耗"
    }

    var stateText: String {
        if !externalConnected { return "电池供电" }
        if isFullyCharged { return "已充满" }
        if let batteryPowerW, batteryPowerW > 0.3 { return "电池充电中" }
        if let batteryPowerW, batteryPowerW < -0.3 { return "电池补充供电" }
        if isCharging { return "充电待机" }
        return "已连接 · 未充电"
    }
}

enum PowerReadError: LocalizedError {
    case serviceUnavailable
    case propertiesUnavailable(kern_return_t)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "未找到 AppleSmartBattery 服务"
        case .propertiesUnavailable(let code):
            return "读取电源属性失败（IOKit \(code)）"
        }
    }
}

final class PowerReader {
    func read() throws -> PowerSnapshot {
        let properties = try readBatteryProperties()
        let telemetry = dictionary(properties["PowerTelemetryData"])
        let privateAdapter = dictionary(properties["AdapterDetails"])
            ?? array(properties["AppleRawAdapterDetails"])?.first.flatMap(dictionary)
        let publicAdapter = readPublicAdapterDetails()

        let connected = bool(properties["ExternalConnected"])
            ?? bool(properties["AppleRawExternalConnected"])
            ?? false
        let charging = bool(properties["IsCharging"]) ?? false
        let full = bool(properties["FullyCharged"]) ?? false

        let systemPowerMW = signedNumber(telemetry?["SystemPowerIn"])
        let systemLoadMW = signedNumber(telemetry?["SystemLoad"])
        let batteryPowerMW = signedNumber(telemetry?["BatteryPower"])
        let voltageMV = signedNumber(telemetry?["SystemVoltageIn"])
        let currentMA = signedNumber(telemetry?["SystemCurrentIn"])
        let batteryVoltageMV = signedNumber(properties["Voltage"])
            ?? signedNumber(properties["AppleRawBatteryVoltage"])
        let batteryCurrentMA = signedNumber(properties["InstantAmperage"])
            ?? signedNumber(properties["Amperage"])

        let reliableBatteryPowerMW: Double? = {
            guard let batteryPowerMW else { return nil }
            guard let systemPowerMW, let systemLoadMW else { return batteryPowerMW }
            let balancePower = systemPowerMW - systemLoadMW
            let tolerance = max(300, abs(systemPowerMW) * 0.03)
            return abs(batteryPowerMW - balancePower) <= tolerance ? batteryPowerMW : nil
        }()

        let ratedPower = signedNumber(publicAdapter?[kIOPSPowerAdapterWattsKey as String])
            ?? signedNumber(privateAdapter?["Watts"])
        let contractVoltageMV = signedNumber(privateAdapter?["AdapterVoltage"])
        let contractCurrentMA = signedNumber(privateAdapter?["Current"])
        let adapterDescription = (privateAdapter?["Description"] as? String)?.lowercased()
        let isPD = adapterDescription?.contains("pd") == true

        let contract: String? = {
            guard let v = contractVoltageMV, let a = contractCurrentMA else { return nil }
            return String(format: "合约 %.0f V / %.1f A", v / 1_000, a / 1_000)
        }()
        let hasDisplayTelemetry = connected
            ? systemPowerMW != nil
            : (systemLoadMW != nil || reliableBatteryPowerMW != nil)

        return PowerSnapshot(
            readAt: Date(),
            inputPowerW: connected ? systemPowerMW.map { $0 / 1_000 } : nil,
            systemLoadW: systemLoadMW.map { $0 / 1_000 },
            inputVoltageV: connected ? voltageMV.map { $0 / 1_000 } : nil,
            inputCurrentA: connected ? currentMA.map { $0 / 1_000 } : nil,
            batteryVoltageV: batteryVoltageMV.map { $0 / 1_000 },
            batteryCurrentA: batteryCurrentMA.map { $0 / 1_000 },
            ratedPowerW: connected ? ratedPower : nil,
            batteryPowerW: reliableBatteryPowerMW.map { $0 / 1_000 },
            batteryPercent: signedNumber(properties["CurrentCapacity"]).map { Int($0.rounded()) },
            externalConnected: connected,
            isCharging: charging,
            isFullyCharged: full,
            protocolName: connected ? (isPD ? "USB-C PD" : "外接电源") : "未连接",
            contractDescription: connected ? contract : nil,
            telemetryAvailable: telemetry != nil && hasDisplayTelemetry
        )
    }

    private func readBatteryProperties() throws -> NSDictionary {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            throw PowerReadError.serviceUnavailable
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { throw PowerReadError.serviceUnavailable }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS, let unmanagedProperties else {
            throw PowerReadError.propertiesUnavailable(result)
        }
        return unmanagedProperties.takeRetainedValue() as NSDictionary
    }

    private func readPublicAdapterDetails() -> NSDictionary? {
        guard let details = IOPSCopyExternalPowerAdapterDetails() else { return nil }
        return details.takeRetainedValue() as NSDictionary
    }

    private func dictionary(_ value: Any?) -> NSDictionary? {
        value as? NSDictionary
    }

    private func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private func signedNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.uint64Value
        if raw > UInt64(Int64.max) {
            return Double(Int64(bitPattern: raw))
        }
        return number.doubleValue
    }
}
