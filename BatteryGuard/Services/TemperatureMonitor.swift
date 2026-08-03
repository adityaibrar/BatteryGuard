// TemperatureMonitor.swift
// BatteryGuard — Monitor suhu via IOKit public API
//
// Status akurasi per platform:
// ✅ Battery temperature: IOKit AppleSmartBattery.Temperature (0.01°C unit) — akurat, no root
// ❌ CPU temperature:     Apple Silicon (M-series) menggunakan AppleARMPMUTempSensor via
//                         IOHIDEventService yang memerlukan private entitlement/root.
//                         Tidak ada public sysctl/IOKit property yang bisa dibaca tanpa root.
//                         Kode ini TIDAK membuat estimasi palsu — nil jika tidak tersedia.
//
// Optimasi CPU usage:
// - Gunakan DispatchSourceTimer di background queue (bukan Task { @MainActor } di dalam Timer)
// - Interval dinaikkan 3s → 5s (suhu tidak berubah tiba-tiba)
// - AppleSmartBattery service handle di-cache satu kali

import Foundation
import IOKit

// MARK: - Temperature Monitor Protocol

protocol TemperatureProviding {
    func fetchTemperatures() -> SystemTemperatures
}

// MARK: - TemperatureMonitor

/// Monitor suhu — battery temp selalu tersedia, CPU temp hanya jika platform support
final class TemperatureMonitor: ObservableObject {

    // MARK: - Published

    @Published var temperatures: SystemTemperatures = .empty

    // MARK: - Private

    /// DispatchSourceTimer berjalan di background queue — tidak memblokir main thread
    private var timerSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.batteryguard.temp-monitor", qos: .utility)
    private let pollingInterval: TimeInterval
    private let provider: TemperatureProviding

    // MARK: - Init

    init(pollingInterval: TimeInterval = 5.0) {
        self.pollingInterval = pollingInterval
        self.provider = BatteryTemperatureProvider()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Baca pertama kali di background
        queue.async { [weak self] in
            self?.fetchAndPublish()
        }

        // Setup DispatchSourceTimer di background queue
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(500) // toleransi ±500ms — suhu tidak butuh presisi tinggi
        )
        source.setEventHandler { [weak self] in
            self?.fetchAndPublish()
        }
        source.resume()
        timerSource = source
    }

    func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil
    }

    // MARK: - Private
    // Dipanggil dari background queue — synchronous fetch (tidak perlu async)

    private func fetchAndPublish() {
        let result = provider.fetchTemperatures()
        DispatchQueue.main.async { [weak self] in
            self?.temperatures = result
        }
    }
}

// MARK: - Battery Temperature Provider

/// Baca suhu baterai dari AppleSmartBattery IOKit — public API, no root needed
/// Battery Temperature key dalam unit 0.01°C (contoh: 3028 → 30.28°C)
final class BatteryTemperatureProvider: TemperatureProviding {

    /// Cache io_service_t untuk AppleSmartBattery
    private var cachedService: io_service_t = IO_OBJECT_NULL

    init() {
        buildServiceCache()
    }

    deinit {
        releaseServiceCache()
    }

    // MARK: - IOKit Cache

    private func buildServiceCache() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return }
        cachedService = service
    }

    private func releaseServiceCache() {
        if cachedService != IO_OBJECT_NULL {
            IOObjectRelease(cachedService)
            cachedService = IO_OBJECT_NULL
        }
    }

    // MARK: - TemperatureProviding

    /// Synchronous fetch — dipanggil dari background queue oleh TemperatureMonitor
    func fetchTemperatures() -> SystemTemperatures {
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
        // Gunakan cached service — rebuild jika belum ada
        if cachedService == IO_OBJECT_NULL {
            buildServiceCache()
            guard cachedService != IO_OBJECT_NULL else { return nil }
        }

        // "Temperature" key dari AppleSmartBattery dalam unit 0.01°C
        // Contoh: 3028 = 30.28°C (sama dengan System Information)
        guard let rawVal = IORegistryEntryCreateCFProperty(
            cachedService,
            "Temperature" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }

        let raw: Int
        if let n = rawVal as? Int           { raw = n }
        else if let n = rawVal as? NSNumber { raw = n.intValue }
        else                                { return nil }

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
