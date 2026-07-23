// TemperatureMonitor.swift
// BatteryGuard — Skeleton monitor suhu CPU/system
//
// Implementasi detail sensor reading perlu diriset sendiri:
// - Approach 1 (recommended): IOHIDEventSystemClient (dipakai iStat Menus, Macs Fan Control)
//   → Private API Apple, perlu entitlement khusus atau workaround
//   → Referensi: https://github.com/exelban/stats (open source, cek implementasinya)
// - Approach 2 (fallback): shell `powermetrics --samplers smc` → butuh sudo
//   → Kasih toggle "Enable Temperature Monitoring" di Settings yang minta izin terpisah
// - Approach 3 (battery only): baca Temperature key dari AppleSmartBattery via IOKit
//   → Ini public API, tapi hanya suhu baterai, bukan CPU

import Foundation
import IOKit

// MARK: - Temperature Monitor Protocol

/// Protocol untuk temperature provider yang bisa di-swap implementasinya
protocol TemperatureProviding {
    func fetchTemperatures() async -> SystemTemperatures
}

// MARK: - TemperatureMonitor

/// Monitor suhu CPU dan sistem
/// Saat ini hanya baca suhu baterai dari AppleSmartBattery (public API)
/// CPU temperature reading adalah TODO — user implementasikan setelah riset
final class TemperatureMonitor: ObservableObject {

    // MARK: - Published

    @Published var temperatures: SystemTemperatures = .empty
    /// True jika monitoring aktif (user bisa toggle dari Settings)
    @Published var isEnabled: Bool = false

    // MARK: - Private

    private var timer: Timer?
    private let pollingInterval: TimeInterval
    private var provider: TemperatureProviding?

    // MARK: - Init

    init(pollingInterval: TimeInterval = 3.0) {
        self.pollingInterval = pollingInterval
        // Default: gunakan battery-only provider (public API)
        self.provider = BatteryTemperatureProvider()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard isEnabled else { return }

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchTemperatures()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)

        // Baca langsung saat start
        Task { await fetchTemperatures() }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
            temperatures = .empty
        }
    }

    /// Swap provider (misal dari battery-only ke full IOHIDEventSystemClient)
    func setProvider(_ provider: TemperatureProviding) {
        self.provider = provider
        if isEnabled {
            Task { await fetchTemperatures() }
        }
    }

    // MARK: - Private

    private func fetchTemperatures() async {
        guard let provider = provider else { return }
        temperatures = await provider.fetchTemperatures()
    }
}

// MARK: - Battery Temperature Provider (Public API fallback)

/// Baca suhu baterai dari AppleSmartBattery IOKit — public API
/// Ini bukan CPU temperature, tapi berguna sebagai data baterai
final class BatteryTemperatureProvider: TemperatureProviding {

    func fetchTemperatures() async -> SystemTemperatures {
        let batteryTemp = readBatteryTemperature()
        return SystemTemperatures(
            cpuTemperature: nil, // Tidak tersedia via public API
            batteryTemperature: batteryTemp,
            allReadings: batteryTemp.map { [$0] } ?? [],
            timestamp: Date()
        )
    }

    private func readBatteryTemperature() -> TemperatureReading? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        // IOKit key "Temperature" dalam unit 0.01°C
        guard let rawTemp = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int else { return nil }

        let celsius = Double(rawTemp) / 100.0

        return TemperatureReading(
            sensorName: "Battery",
            celsius: celsius,
            timestamp: Date()
        )
    }
}

// MARK: - CPU Temperature Provider (TODO — user implementasikan)

/// Placeholder untuk implementasi CPU temperature reading
/// Opsi implementasi yang perlu diriset:
/// 1. IOHIDEventSystemClient (lihat Stats app open source untuk referensi)
/// 2. powermetrics shell-out (butuh sudo)
final class CPUTemperatureProvider: TemperatureProviding {

    func fetchTemperatures() async -> SystemTemperatures {
        // TODO: Implementasikan salah satu approach di bawah:
        //
        // Approach 1 — IOHIDEventSystemClient:
        // let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        // IOHIDEventSystemClientSetMatching(client, matchingDict)
        // let services = IOHIDEventSystemClientCopyServices(client)
        // → Baca sensor via IOHIDServiceClientCopyProperty
        //
        // Approach 2 — powermetrics:
        // let task = Process()
        // task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        // task.arguments = ["--samplers", "smc", "-n", "1", "--format", "plist"]
        // → Parse output untuk nilai temperature
        //
        // Approach 3 — SMCKit (kalau mau pakai library pihak ketiga)

        return SystemTemperatures.empty
    }
}
