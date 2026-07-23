// TemperatureMonitor.swift
// BatteryGuard — Monitor suhu baterai (IOKit public API)
// CPU temp via sysctl thermal + battery temp via AppleSmartBattery

import Foundation
import IOKit

// MARK: - Temperature Monitor Protocol

protocol TemperatureProviding {
    func fetchTemperatures() async -> SystemTemperatures
}

// MARK: - TemperatureMonitor

/// Monitor suhu baterai SELALU aktif (tidak butuh toggle).
/// Battery temp: IOKit AppleSmartBattery (public API, no root needed).
/// CPU temp: sysctl + powermetrics estimation (best-effort, no root).
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
        // Selalu pakai BatteryTemperatureProvider (public API, battery temp)
        self.provider = BatteryTemperatureProvider()
    }

    // MARK: - Lifecycle

    /// Mulai monitoring — SELALU aktif, tidak perlu user toggle
    func startMonitoring() {
        // Baca langsung saat start
        Task { @MainActor [weak self] in await self?.fetchTemperatures() }

        // Polling setiap pollingInterval detik
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

/// Baca suhu baterai dari AppleSmartBattery IOKit — public API, no root
/// Temperature key dalam unit 0.01°C
final class BatteryTemperatureProvider: TemperatureProviding {

    func fetchTemperatures() async -> SystemTemperatures {
        let batteryTemp = readBatteryTemperature()
        let cpuTemp = readCPUTemperatureEstimate()

        var readings: [TemperatureReading] = []
        if let b = batteryTemp { readings.append(b) }
        if let c = cpuTemp { readings.append(c) }

        return SystemTemperatures(
            cpuTemperature: cpuTemp,
            batteryTemperature: batteryTemp,
            allReadings: readings,
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

        // "Temperature" key dalam unit 0.01°C — divide by 100 untuk Celsius
        guard let rawVal = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }

        // Value bisa berupa Int atau NSNumber
        let raw: Int
        if let n = rawVal as? Int { raw = n }
        else if let n = rawVal as? NSNumber { raw = n.intValue }
        else { return nil }

        guard raw > 0 else { return nil }

        let celsius = Double(raw) / 100.0
        return TemperatureReading(
            sensorName: "Battery",
            celsius: celsius,
            timestamp: Date()
        )
    }

    // MARK: - CPU Temperature Estimate (sysctl — no root, Apple Silicon)

    /// Baca thermal pressure level dari sysctl sebagai proxy CPU temp.
    /// Ini bukan angka Celsius sesungguhnya tapi cukup untuk menampilkan
    /// status thermal (nominal/elevated/critical).
    /// Untuk Celsius akurat butuh IOReport (private) atau powermetrics (root).
    private func readCPUTemperatureEstimate() -> TemperatureReading? {
        // Coba baca dari IOKit AppleSMC — beberapa key tersedia tanpa root
        // Key "TC0P" = CPU proximity temperature di Intel; Apple Silicon berbeda
        // Pada M-series, coba "Tp09" (Efficiency core) atau "Tp01" (Performance core)

        // Approach: baca dari sysctl kern.thermal_level sebagai indikator
        // kemudian scale ke kisaran suhu tipikal berdasarkan level
        var thermalLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size

        // kern.thermalf bisa di-read tanpa root
        if sysctlbyname("kern.thermalf", &thermalLevel, &size, nil, 0) == 0 {
            // kern.thermalf: 0 = nominal, 1 = elevated, 2 = critical
            // Mapping ke kisaran estimasi Celsius pada Apple Silicon
            // Idle M2: ~30-40°C, Load: 50-70°C, Throttle: 70-90°C
            let estimatedCelsius: Double
            switch thermalLevel {
            case 0: estimatedCelsius = -1   // nominal, tidak bisa estimate
            case 1: estimatedCelsius = 70   // elevated
            case 2: estimatedCelsius = 85   // critical
            default: estimatedCelsius = -1
            }

            // Hanya tampilkan jika elevated/critical untuk menghindari misleading
            if estimatedCelsius > 0 {
                return TemperatureReading(
                    sensorName: "CPU (Thermal Level)",
                    celsius: estimatedCelsius,
                    timestamp: Date()
                )
            }
        }

        return nil  // CPU temp tidak tersedia tanpa root/private API
    }
}
