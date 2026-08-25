import SwiftUI
import WidgetKit

struct PowerPulseEntry: TimelineEntry {
    let date: Date
    let snapshot: PowerSnapshot?
}

struct PowerPulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PowerPulseEntry {
        PowerPulseEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PowerPulseEntry) -> Void) {
        completion(PowerPulseEntry(date: Date(), snapshot: try? PowerReader().read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PowerPulseEntry>) -> Void) {
        let now = Date()
        let entry = PowerPulseEntry(date: now, snapshot: try? PowerReader().read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct PowerPulseWidgetView: View {
    let entry: PowerPulseEntry

    private var snapshot: PowerSnapshot? { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("POWER PULSE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 2)
                Circle()
                    .fill(snapshot?.telemetryAvailable == true ? Color.cyan : Color.gray)
                    .frame(width: 6, height: 6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(powerText)
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.15, green: 0.72, blue: 1.0))
                Text("W")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.cyan)
            }

            Text("MAC 侧实时输入")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            Divider().overlay(Color.cyan.opacity(0.25))

            HStack {
                compactMetric("额定", ratedText)
                Spacer()
                compactMetric("电量", batteryText)
            }

            HStack {
                compactMetric("电压", voltageText)
                Spacer()
                compactMetric("电流", currentText)
            }

            HStack(spacing: 4) {
                Text(snapshot?.protocolName ?? "等待数据")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 2)
                Text(netBatteryText)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.cyan.opacity(0.85))
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.045, blue: 0.075),
                    Color(red: 0.035, green: 0.105, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(title).foregroundStyle(.white.opacity(0.46))
            Text(value).foregroundStyle(.white.opacity(0.9)).monospacedDigit()
        }
        .font(.system(size: 9, weight: .medium))
    }

    private var powerText: String {
        snapshot?.inputPowerW.map { String(format: "%.1f", $0) } ?? "—"
    }

    private var ratedText: String {
        snapshot?.ratedPowerW.map { String(format: "%.0f W", $0) } ?? "—"
    }

    private var batteryText: String {
        snapshot?.batteryPercent.map { "\($0)%" } ?? "—"
    }

    private var voltageText: String {
        snapshot?.inputVoltageV.map { String(format: "%.1f V", $0) } ?? "—"
    }

    private var currentText: String {
        snapshot?.inputCurrentA.map { String(format: "%.2f A", $0) } ?? "—"
    }

    private var netBatteryText: String {
        guard let power = snapshot?.batteryPowerW else { return "净 — W" }
        return String(format: "净 %+.1f W", power)
    }
}

struct PowerPulseWidget: Widget {
    let kind = "PowerPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PowerPulseProvider()) { entry in
            PowerPulseWidgetView(entry: entry)
        }
        .configurationDisplayName("Power Pulse")
        .description("显示 Mac 的供电功率、PD 合约参数和电池状态。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct PowerPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PowerPulseWidget()
    }
}
