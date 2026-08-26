import AppKit
import Charts
import SwiftUI

private enum HistoryRange: TimeInterval, CaseIterable, Identifiable {
    case fifteenMinutes = 900
    case oneHour = 3_600
    case sixHours = 21_600
    case oneDay = 86_400

    var id: TimeInterval { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 分钟"
        case .oneHour: "1 小时"
        case .sixHours: "6 小时"
        case .oneDay: "24 小时"
        }
    }
}

struct PowerHistoryView: View {
    @ObservedObject var store: PowerHistoryStore
    @State private var selectedRange: HistoryRange = .oneHour

    private var filteredSamples: [PowerHistorySample] {
        let cutoff = Date().addingTimeInterval(-selectedRange.rawValue)
        return store.samples.filter { $0.recordedAt >= cutoff }
    }

    private var chartSamples: [PowerHistorySample] {
        let values = filteredSamples
        guard values.count > 1_200 else { return values }
        let step = max(1, values.count / 1_200)
        var reduced = values.enumerated().compactMap { index, sample in
            index.isMultiple(of: step) ? sample : nil
        }
        if let last = values.last, reduced.last?.recordedAt != last.recordedAt {
            reduced.append(last)
        }
        return reduced
    }

    private var latest: PowerHistorySample? { store.samples.last }

    private var averageSystemLoadW: Double? {
        let values = filteredSamples.compactMap(\.systemLoadW)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summaryCards
            charts
            footer
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 450)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.028, blue: 0.045),
                    Color(red: 0.025, green: 0.075, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("功率记录")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("功率、电池电量与区间平均")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("时间范围", selection: $selectedRange) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 310)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            metricCard("外部输入", latest?.inputPowerW, color: .cyan)
            metricCard("整机功耗", latest?.systemLoadW, color: Color(red: 0.25, green: 0.64, blue: 1.0))
            metricCard("电池净功率", latest?.batteryPowerW, signed: true, color: .orange)
            metricCard("平均功耗", averageSystemLoadW, color: Color(red: 0.35, green: 0.9, blue: 0.62))
        }
    }

    private var charts: some View {
        Group {
            if chartSamples.isEmpty {
                ContentUnavailableView(
                    "正在积累记录",
                    systemImage: "chart.xyaxis.line",
                    description: Text("保持 Power Pulse 运行，曲线会每 5 秒增加一个采样点。")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    powerChart

                    Divider().overlay(.white.opacity(0.08))

                    HStack {
                        Text("电池电量")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(latest?.batteryPercent.map { "\($0)%" } ?? "—")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.purple)
                    }

                    batteryChart
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.cyan.opacity(0.12), lineWidth: 1)
        }
    }

    private var powerChart: some View {
        Chart {
            RuleMark(y: .value("零线", 0))
                .foregroundStyle(.white.opacity(0.16))

            if let average = averageSystemLoadW {
                RuleMark(y: .value("平均功耗", average))
                    .foregroundStyle(Color(red: 0.35, green: 0.9, blue: 0.62).opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(String(format: "平均 %.1f W", average))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 0.35, green: 0.9, blue: 0.62))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.58), in: Capsule())
                    }
            }

            ForEach(chartSamples) { sample in
                if let value = sample.inputPowerW {
                    LineMark(
                        x: .value("时间", sample.recordedAt),
                        y: .value("功率", value),
                        series: .value("指标", "外部输入")
                    )
                    .foregroundStyle(by: .value("指标", "外部输入"))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let value = sample.systemLoadW {
                    LineMark(
                        x: .value("时间", sample.recordedAt),
                        y: .value("功率", value),
                        series: .value("指标", "整机功耗")
                    )
                    .foregroundStyle(by: .value("指标", "整机功耗"))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let value = sample.batteryPowerW {
                    LineMark(
                        x: .value("时间", sample.recordedAt),
                        y: .value("功率", value),
                        series: .value("指标", "电池净功率")
                    )
                    .foregroundStyle(by: .value("指标", "电池净功率"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
        }
        .chartForegroundStyleScale([
            "外部输入": Color.cyan,
            "整机功耗": Color(red: 0.25, green: 0.64, blue: 1.0),
            "电池净功率": Color.orange
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 16)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel()
            }
        }
        .frame(minHeight: 220)
    }

    private var batteryChart: some View {
        Chart {
            ForEach(chartSamples) { sample in
                if let percent = sample.batteryPercent {
                    AreaMark(
                        x: .value("时间", sample.recordedAt),
                        y: .value("电量", percent)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple.opacity(0.32), .purple.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("时间", sample.recordedAt),
                        y: .value("电量", percent)
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                if let percent = value.as(Int.self) {
                    AxisValueLabel { Text("\(percent)%") }
                }
            }
        }
        .frame(height: 110)
    }

    private var footer: some View {
        HStack {
            Text("每 5 秒采样 · 自动保留最近 24 小时")
            Spacer()
            if let error = store.storageError {
                Text("记录保存失败：\(error)")
                    .foregroundStyle(.red)
            } else if let date = latest?.recordedAt {
                Text("最后记录 \(date.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func metricCard(_ title: String, _ value: Double?, signed: Bool = false, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value.map { String(format: signed ? "%+.1f W" : "%.1f W", $0) } ?? "— W")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
final class PowerHistoryWindowController: NSWindowController {
    init(store: PowerHistoryStore) {
        let hostingController = NSHostingController(rootView: PowerHistoryView(store: store))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Power Pulse · 功率记录"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 650))
        window.minSize = NSSize(width: 720, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
