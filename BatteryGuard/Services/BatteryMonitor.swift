// BatteryMonitor.swift
// BatteryGuard — Monitor status baterai via IOKit + IOPowerSources
// Semua API yang dipakai adalah public Apple API, tidak ada reverse engineering

import Foundation
import IOKit
import IOKit.ps

// MARK: - BatteryMonitor

/// Membaca semua data baterai dari IOKit secara periodik
/// - `IOPSCopyPowerSourcesInfo` + `IOPSGetPowerSourceDescription`: status & health
/// - `IOServiceGetMatchingService("AppleSmartBattery")`: specs detail
/// - `IOPSCopyExternalPowerAdapterDetails`: info adapter
final class BatteryMonitor: ObservableObject {

    // MARK: - Published Properties

    @Published var status: BatteryStatus = .placeholder
    @Published var specs: BatterySpecs = .empty
    @Published var health: BatteryHealth = .empty
    @Published var adapterInfo: AdapterInfo = .disconnected
    @Published var powerFlow: PowerFlow = .empty

    // MARK: - Private

    private var timer: Timer?
    /// Interval polling dalam detik (default 2 detik)
    private let pollingInterval: TimeInterval

    // MARK: - Init

    init(pollingInterval: TimeInterval = 2.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Baca langsung saat pertama kali
        readAll()

        // Setup timer periodic
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.readAll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Read All

    private func readAll() {
        // Baca di background, publish di main thread
        readPowerSourceInfo()
        readAppleSmartBattery()
        readAdapterInfo()
    }

    // MARK: - IOPowerSources (status & basic health)

    /// Baca status baterai dari IOPowerSources API (public, documented)
    private func readPowerSourceInfo() {
        // Dapatkan blob info semua power source
        guard let psInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let sources = IOPSCopyPowerSourcesList(psInfo)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(psInfo, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            // Filter hanya internal battery
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            // Parse status
            let currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = maxCapacity > 0 ? (currentCapacity * 100 / maxCapacity) : currentCapacity

            let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // Time remaining (menit)
            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let timeRemaining: Double? = isCharging
                ? (timeToFull >= 0 ? Double(timeToFull) : nil)
                : (timeToEmpty >= 0 ? Double(timeToEmpty) : nil)

            status = BatteryStatus(
                percentage: percentage,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                chargeLimitReached: false, // Di-update oleh ChargeLimitManager
                lastUpdated: Date()
            )

            powerFlow.timeRemainingMinutes = timeRemaining

            // Health dari IOPSGetPowerSourceDescription
            if let maxCap = desc["MaxCapacity"] as? Int {
                health.maxCapacity = maxCap
            }
            if let designCap = desc["DesignCapacity"] as? Int {
                health.designCapacity = designCap
            }
        }
    }

    // MARK: - AppleSmartBattery (via IOKit service)

    /// Baca detail specs & health dari AppleSmartBattery IOKit service
    /// Equivalent dengan: `ioreg -rn AppleSmartBattery`
    private func readAppleSmartBattery() {
        // Match service AppleSmartBattery
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("AppleSmartBattery")
        )

        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        // Helper: baca property dari IOKit service
        func getProperty<T>(_ key: String) -> T? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? T
        }

        // MARK: Specs
        specs = BatterySpecs(
            designCapacity: getProperty("DesignCapacity"),
            serialNumber: getProperty("BatterySerialNumber"),
            manufacturer: getProperty("Manufacturer"),
            manufactureDate: parseManufactureDate(getProperty("ManufactureDate")),
            deviceName: getProperty("DeviceName"),
            firmwareVersion: nil // Jarang tersedia via IOKit publik
        )

        // MARK: Health
        let cycleCount: Int? = getProperty("CycleCount")
        let maxCap: Int? = getProperty("AppleRawMaxCapacity")
        let designCap: Int? = getProperty("DesignCapacity")

        health = BatteryHealth(
            maxCapacity: maxCap,
            designCapacity: designCap,
            cycleCount: cycleCount,
            condition: getProperty("BatteryHealthCondition"),
            maxCapacityPercent: getProperty("BatteryHealthMaxCapacityPercent")
        )

        // MARK: Power Flow
        // Voltage dalam mV, Amperage dalam mA dari IOKit
        let voltageMV: Int? = getProperty("Voltage")
        let amperageMa: Int? = getProperty("Amperage")

        // Konversi ke Volt dan Ampere
        let voltage = voltageMV.map { Double($0) / 1000.0 }
        let amperage = amperageMa.map { Double($0) / 1000.0 }

        powerFlow = PowerFlow(
            amperage: amperage,
            voltage: voltage,
            timeRemainingMinutes: powerFlow.timeRemainingMinutes
        )

        // MARK: Battery Temperature (dari AppleSmartBattery)
        // Temperature key dalam unit 0.01°C (perlu dibagi 100)
        if let tempRaw: Int = getProperty("Temperature") {
            let tempCelsius = Double(tempRaw) / 100.0
            // Note: TemperatureMonitor akan menggunakan nilai ini sebagai fallback
            _ = tempCelsius // Akan di-publish via TemperatureMonitor atau langsung
        }
    }

    // MARK: - External Power Adapter

    /// Baca info adapter dari IOPSCopyExternalPowerAdapterDetails()
    /// Documented Apple API, tidak butuh privilege khusus
    private func readAdapterInfo() {
        guard let adapterRef = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue(),
              let adapterDict = adapterRef as? [String: Any]
        else {
            adapterInfo = .disconnected
            return
        }

        // Key yang tersedia: kIOPSPowerAdapterWattsKey, kIOPSPowerAdapterCurrentKey, dll.
        let wattage = (adapterDict["Watts"] as? Double) ??
                      (adapterDict["Wattage"] as? Double)
        let amperage = (adapterDict["Current"] as? Double).map { $0 / 1000.0 } // mA → A
        let voltage = (adapterDict["Voltage"] as? Double).map { $0 / 1000.0 }  // mV → V
        let name = adapterDict["Description"] as? String ??
                   adapterDict["Name"] as? String

        adapterInfo = AdapterInfo(
            wattage: wattage,
            amperage: amperage,
            voltage: voltage,
            name: name,
            family: adapterDict["Family"] as? String
        )
    }

    // MARK: - Helpers

    /// Parse ManufactureDate dari IOKit (format BCD atau integer encoded date)
    private func parseManufactureDate(_ raw: Int?) -> Date? {
        guard let raw = raw else { return nil }
        // ManufactureDate dari AppleSmartBattery biasanya dalam format:
        // bits 15-9: Year offset dari 1980, bits 8-5: Month, bits 4-0: Day
        let year = 1980 + ((raw >> 9) & 0x7F)
        let month = (raw >> 5) & 0x0F
        let day = raw & 0x1F
        guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }
}
