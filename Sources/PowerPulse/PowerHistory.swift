import Combine
import Foundation

struct PowerHistorySample: Codable, Identifiable {
    let recordedAt: Date
    let inputPowerW: Double?
    let computerPowerW: Double?
    let batteryPowerW: Double?
    let batteryPercent: Int?
    let externalConnected: Bool
    let measurementVersion: Int?

    var id: Date { recordedAt }

    init(snapshot: PowerSnapshot) {
        recordedAt = snapshot.readAt
        inputPowerW = snapshot.inputPowerW
        computerPowerW = snapshot.computerPowerW
        batteryPowerW = snapshot.batteryPowerW
        batteryPercent = snapshot.batteryPercent
        externalConnected = snapshot.externalConnected
        measurementVersion = 3
    }

    private init(
        recordedAt: Date,
        inputPowerW: Double?,
        computerPowerW: Double?,
        batteryPowerW: Double?,
        batteryPercent: Int?,
        externalConnected: Bool,
        measurementVersion: Int?
    ) {
        self.recordedAt = recordedAt
        self.inputPowerW = inputPowerW
        self.computerPowerW = computerPowerW
        self.batteryPowerW = batteryPowerW
        self.batteryPercent = batteryPercent
        self.externalConnected = externalConnected
        self.measurementVersion = measurementVersion
    }

    var normalized: PowerHistorySample {
        let normalizedComputerPowerW: Double? = {
            if measurementVersion == 3 { return computerPowerW.map(abs) }
            if measurementVersion == 2 {
                if !externalConnected, (computerPowerW ?? 0) <= 0.05 {
                    return batteryPowerW.map(abs)
                }
                return computerPowerW.map(abs)
            }
            return nil
        }()

        return PowerHistorySample(
            recordedAt: recordedAt,
            inputPowerW: measurementVersion == 2 || measurementVersion == 3 ? inputPowerW.map(abs) : nil,
            computerPowerW: normalizedComputerPowerW,
            batteryPowerW: measurementVersion == 2 || measurementVersion == 3
                ? batteryPowerW.map { externalConnected ? $0 : -abs($0) }
                : nil,
            batteryPercent: batteryPercent,
            externalConnected: externalConnected,
            measurementVersion: measurementVersion == 2 ? 3 : measurementVersion
        )
    }
}

@MainActor
final class PowerHistoryStore: ObservableObject {
    @Published private(set) var samples: [PowerHistorySample] = []
    @Published private(set) var storageError: String?

    private let retention: TimeInterval = 24 * 60 * 60
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingData = Data()
    private var lastFlush = Date.distantPast
    private var lastCompaction = Date.distantPast

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = supportURL.appendingPathComponent("Power Pulse", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("power-history.jsonl")

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try loadFromDisk()
            try compactFile()
            lastCompaction = Date()
        } catch {
            storageError = error.localizedDescription
        }
    }

    func record(_ snapshot: PowerSnapshot) {
        let sample = PowerHistorySample(snapshot: snapshot)
        samples.append(sample)
        pruneMemory(now: sample.recordedAt)

        do {
            pendingData.append(try encoder.encode(sample))
            pendingData.append(0x0A)
            if sample.recordedAt.timeIntervalSince(lastFlush) >= 30 {
                try flushPendingData()
            }
            if sample.recordedAt.timeIntervalSince(lastCompaction) >= 60 * 60 {
                try compactFile()
                lastCompaction = sample.recordedAt
            }
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func flush() {
        do {
            try flushPendingData()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func loadFromDisk() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        let cutoff = Date().addingTimeInterval(-retention)
        samples = data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(PowerHistorySample.self, from: Data($0)) }
            .map(\.normalized)
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private func pruneMemory(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        if let firstValid = samples.firstIndex(where: { $0.recordedAt >= cutoff }), firstValid > 0 {
            samples.removeFirst(firstValid)
        }
    }

    private func flushPendingData() throws {
        guard !pendingData.isEmpty else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: pendingData)
            try handle.close()
        } else {
            try pendingData.write(to: fileURL, options: .atomic)
        }

        pendingData.removeAll(keepingCapacity: true)
        lastFlush = Date()
    }

    private func compactFile() throws {
        try flushPendingData()
        var compacted = Data()
        for sample in samples {
            compacted.append(try encoder.encode(sample))
            compacted.append(0x0A)
        }
        try compacted.write(to: fileURL, options: .atomic)
    }
}
