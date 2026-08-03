// BatteryMonitor.swift
// BatteryGuard — Monitor status baterai via IOKit + IOPowerSources
// Semua API yang dipakai adalah public Apple API, tidak ada reverse engineering
//
// Optimasi CPU usage:
// - Gunakan DispatchSourceTimer di background queue (bukan Timer di main RunLoop)
// - Interval dinaikkan 2s → 5s (battery % berubah ~1%/menit — 5s sudah lebih responsif)
// - io_service_t untuk AppleSmartBattery di-cache satu kali — eliminasi IOServiceGetMatchingService per-tick

import Foundation
import IOKit
import IOKit.ps

// MARK: - BatteryMonitor

/// Membaca semua data baterai dari IOKit secara periodik
/// - `IOPSCopyPowerSourcesInfo` + `IOPSGetPowerSourceDescription`: status & health
/// - `IOServiceGetMatchingService("AppleSmartBattery")`: specs detail (di-cache)
/// - `IOPSCopyExternalPowerAdapterDetails`: info adapter
final class BatteryMonitor: ObservableObject {

    // MARK: - Published Properties

    @Published var status: BatteryStatus = .placeholder
    @Published var specs: BatterySpecs = .empty
    @Published var health: BatteryHealth = .empty
    @Published var adapterInfo: AdapterInfo = .disconnected
    @Published var powerFlow: PowerFlow = .empty

    // MARK: - Private

    /// DispatchSourceTimer berjalan di background queue — tidak memblokir main thread
    private var timerSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.batteryguard.battery-monitor", qos: .utility)
    /// Interval polling dalam detik (default 5 detik — battery % berubah ~1%/menit)
    private let pollingInterval: TimeInterval

    /// Cache io_service_t untuk AppleSmartBattery
    /// Service ini selalu ada selama Mac hidup — aman untuk di-cache
    private var cachedBatteryService: io_service_t = IO_OBJECT_NULL

    // MARK: - Init

    init(pollingInterval: TimeInterval = 5.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        queue.async { [weak self] in
            // Buat cache service handle satu kali
            self?.buildServiceCache()
            // Baca data langsung saat pertama kali
            self?.readAll()
        }

        // Setup DispatchSourceTimer di background queue
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(500) // toleransi ±500ms — battery data tidak butuh presisi tinggi
        )
        source.setEventHandler { [weak self] in
            self?.readAll()
        }
        source.resume()
        timerSource = source
    }

    func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil

        // Lepaskan cached service handle
        queue.async { [weak self] in
            self?.releaseServiceCache()
        }
    }

    // MARK: - IOKit Service Cache

    private func buildServiceCache() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return }
        cachedBatteryService = service // Retained — akan dirilis di releaseServiceCache()
    }

    private func releaseServiceCache() {
        if cachedBatteryService != IO_OBJECT_NULL {
            IOObjectRelease(cachedBatteryService)
            cachedBatteryService = IO_OBJECT_NULL
        }
    }

    // MARK: - Read All
    // Dipanggil dari background queue — aman untuk IOKit calls

    private func readAll() {
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
            // kIOPSCurrentCapacityKey sudah dalam satuan yang sama dengan kIOPSMaxCapacityKey
            // Biasanya keduanya adalah persentase (0-100)
            let currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity     = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            // Gunakan nilai langsung jika maxCapacity = 100, atau hitung jika unit berbeda
            let percentage = (maxCapacity == 100)
                ? currentCapacity
                : (maxCapacity > 0 ? currentCapacity * 100 / maxCapacity : currentCapacity)

            let isCharging  = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // Time remaining (menit)
            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let timeToFull  = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let timeRemaining: Double? = isCharging
                ? (timeToFull >= 0 ? Double(timeToFull) : nil)
                : (timeToEmpty >= 0 ? Double(timeToEmpty) : nil)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.status = BatteryStatus(
                    percentage: percentage,
                    isCharging: isCharging,
                    isPluggedIn: isPluggedIn,
                    chargeLimitReached: false // Di-update oleh ChargeLimitManager
                )
                self.powerFlow.timeRemainingMinutes = timeRemaining

                // Health dari IOPSGetPowerSourceDescription
                if let maxCap = desc["MaxCapacity"] as? Int {
                    self.health.maxCapacity = maxCap
                }
                if let designCap = desc["DesignCapacity"] as? Int {
                    self.health.designCapacity = designCap
                }
            }
        }
    }

    // MARK: - AppleSmartBattery (via cached IOKit service)

    /// Baca detail specs & health dari AppleSmartBattery IOKit service (cached)
    /// Equivalent dengan: `ioreg -rn AppleSmartBattery`
    private func readAppleSmartBattery() {
        // Gunakan cached service — hindari IOServiceGetMatchingService() per-tick
        // Jika cache belum ada (misalnya dipanggil sebelum buildServiceCache selesai), rebuild
        if cachedBatteryService == IO_OBJECT_NULL {
            buildServiceCache()
            guard cachedBatteryService != IO_OBJECT_NULL else { return }
        }

        let service = cachedBatteryService

        // Helper: baca property dari IOKit service
        func getProperty<T>(_ key: String) -> T? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? T
        }

        // MARK: Specs (local var dahulu)
        let newSpecs = BatterySpecs(
            designCapacity: getProperty("DesignCapacity"),
            serialNumber:   getProperty("BatterySerialNumber"),
            manufacturer:   getProperty("Manufacturer"),
            manufactureDate: parseManufactureDate(getProperty("ManufactureDate")),
            deviceName:     getProperty("DeviceName"),
            firmwareVersion: nil // Jarang tersedia via IOKit publik
        )

        // MARK: Health (local var)
        let cycleCount: Int? = getProperty("CycleCount")
        let maxCap: Int?     = getProperty("AppleRawMaxCapacity")
        let designCap: Int?  = getProperty("DesignCapacity")
        // NominalChargeCapacity: nilai yang dipakai macOS System Information
        // untuk menampilkan "Maximum Capacity" percentage (contoh: 3925 mAh → 86%)
        let nominalCap: Int? = getProperty("NominalChargeCapacity")

        let newHealth = BatteryHealth(
            maxCapacity:           maxCap,
            nominalChargeCapacity: nominalCap,
            designCapacity:        designCap,
            cycleCount:            cycleCount,
            condition:             getProperty("BatteryHealthCondition"),
            maxCapacityPercent:    getProperty("BatteryHealthMaxCapacityPercent")
        )

        // MARK: Power Flow (local var)
        // Voltage dalam mV, Amperage dalam mA dari IOKit
        let voltageMV: Int? = getProperty("Voltage")
        let amperageMa: Int? = getProperty("Amperage")

        // Konversi ke Volt dan Ampere
        let voltage   = voltageMV.map  { Double($0) / 1000.0 }
        let amperage  = amperageMa.map { Double($0) / 1000.0 }

        // MARK: Accurate Battery Percentage
        // CurrentCapacity dari AppleSmartBattery = persentase (0–100)
        // MaxCapacity = 100 (konfirmasi satuan adalah persen, bukan mAh)
        // Nilai ini sama persis dengan yang ditampilkan macOS System Information
        // dan menu bar battery icon.
        // JANGAN gunakan StateOfCharge dari BatteryData — itu nilai internal gauge
        // yang bisa berbeda ±3% dari yang ditampilkan macOS ke user.
        let accuratePercent: Int? = getProperty("CurrentCapacity")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.specs  = newSpecs
            self.health = newHealth

            // Preserve timeRemainingMinutes dari powerFlow yang sudah di-set sebelumnya
            let preserved = self.powerFlow.timeRemainingMinutes
            self.powerFlow = PowerFlow(
                amperage: amperage,
                voltage: voltage,
                timeRemainingMinutes: preserved
            )

            // Override percentage dengan nilai lebih akurat dari AppleSmartBattery
            if let pct = accuratePercent {
                self.status.percentage = min(100, max(0, pct))
            }
        }
    }

    // MARK: - External Power Adapter

    /// Baca info adapter dari IOPSCopyExternalPowerAdapterDetails()
    /// Documented Apple API, tidak butuh privilege khusus
    private func readAdapterInfo() {
        guard let adapterRef = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue(),
              let adapterDict = adapterRef as? [String: Any]
        else {
            DispatchQueue.main.async { [weak self] in
                self?.adapterInfo = .disconnected
            }
            return
        }

        // Key yang tersedia: kIOPSPowerAdapterWattsKey, kIOPSPowerAdapterCurrentKey, dll.
        let wattage  = (adapterDict["Watts"] as? Double) ?? (adapterDict["Wattage"] as? Double)
        let amperage = (adapterDict["Current"] as? Double).map { $0 / 1000.0 } // mA → A
        let voltage  = (adapterDict["Voltage"] as? Double).map { $0 / 1000.0 }  // mV → V
        let name     = adapterDict["Description"] as? String ?? adapterDict["Name"] as? String

        let newAdapterInfo = AdapterInfo(
            wattage:  wattage,
            amperage: amperage,
            voltage:  voltage,
            name:     name,
            family:   adapterDict["Family"] as? String
        )

        DispatchQueue.main.async { [weak self] in
            self?.adapterInfo = newAdapterInfo
        }
    }

    // MARK: - Helpers

    /// Parse ManufactureDate dari IOKit (format BCD atau integer encoded date)
    private func parseManufactureDate(_ raw: Int?) -> Date? {
        guard let raw = raw else { return nil }
        // ManufactureDate dari AppleSmartBattery biasanya dalam format:
        // bits 15-9: Year offset dari 1980, bits 8-5: Month, bits 4-0: Day
        let year  = 1980 + ((raw >> 9) & 0x7F)
        let month = (raw >> 5) & 0x0F
        let day   = raw & 0x1F
        guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else { return nil }

        var components   = DateComponents()
        components.year  = year
        components.month = month
        components.day   = day
        return Calendar.current.date(from: components)
    }
}
