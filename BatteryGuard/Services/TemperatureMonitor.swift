// TemperatureMonitor.swift
// BatteryGuard — Monitor suhu via IOKit public API
//
// Status akurasi per platform:
// ✅ Battery temperature: IOKit AppleSmartBattery.Temperature (0.01°C unit) — akurat, no root
// ❌ CPU temperature:     Apple Silicon (M-series) menggunakan AppleARMPMUTempSensor via
//                         IOHIDEventService yang memerlukan private entitlement/root.
//                         Tidak ada public sysctl/IOKit property yang bisa dibaca tanpa root.
//                         Kode ini TIDAK membuat estimasi palsu — nil jika tidak tersedia.

import Foundation
import IOKit

// MARK: - Temperature Monitor Protocol

protocol TemperatureProviding {
    func fetchTemperatures() async -> SystemTemperatures
}

// MARK: - TemperatureMonitor

/// Monitor suhu — battery temp selalu tersedia, CPU temp hanya jika platform support
final class TemperatureMonitor: ObservableObject {

    // MARK: - Published

    @Published var temperatures: SystemTemperatures = .empty

    // MARK: - Private

    private var timer: Timer?
    private let pollingInterval: TimeInterval
    private let provider: TemperatureProviding

    // MARK: - Init

    init(pollingInterval: TimeInterval = 3.0) {
        self.pollingInterval = pollingInterval
        self.provider = BatteryTemperatureProvider()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        Task { @MainActor [weak self] in await self?.fetchTemperatures() }

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchTemperatures()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    @MainActor
    private func fetchTemperatures() async {
        temperatures = await provider.fetchTemperatures()
    }
}

// MARK: - Battery Temperature Provider

/// Baca suhu baterai dari AppleSmartBattery IOKit — public API, no root needed
/// Battery Temperature key dalam unit 0.01°C (contoh: 3028 → 30.28°C)
final class BatteryTemperatureProvider: TemperatureProviding {

    func fetchTemperatures() async -> SystemTemperatures {
        let batteryTemp = readBatteryTemperature()

        return SystemTemperatures(
            // CPU temp: nil — tidak tersedia tanpa root di Apple Silicon
            // AppleARMPMUTempSensor memerlukan IOHIDEventService private entitlement
            cpuTemperature: nil,
            batteryTemperature: batteryTemp,
            allReadings: batteryTemp.map { [$0] } ?? [],
            timestamp: Date()
        )
    }

    // MARK: - Battery Temperature (IOKit AppleSmartBattery — public API)

    private func readBatteryTemperature() -> TemperatureReading? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        // "Temperature" key dari AppleSmartBattery dalam unit 0.01°C
        // Contoh: 3028 = 30.28°C (sama dengan System Information)
        guard let rawVal = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }

        let raw: Int
        if let n = rawVal as? Int { raw = n }
        else if let n = rawVal as? NSNumber { raw = n.intValue }
        else { return nil }

        // Validasi: suhu baterai yang valid antara -10°C sampai 80°C
        // raw = 0 berarti tidak ada data
        guard raw > 0 else { return nil }

        let celsius = Double(raw) / 100.0

        // Sanity check range yang wajar untuk baterai laptop
        guard celsius > -10 && celsius < 100 else { return nil }

        return TemperatureReading(
            sensorName: "Battery",
            celsius: celsius,
            timestamp: Date()
        )
    }
}
