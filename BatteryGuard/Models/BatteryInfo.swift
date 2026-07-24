// BatteryInfo.swift
// BatteryGuard — Core battery data models
// Semua value types, aman di-pass antar thread

import Foundation

// MARK: - Battery Status (real-time)

/// Status baterai yang di-update setiap polling interval
struct BatteryStatus: Equatable {
    /// Persentase baterai saat ini (0–100)
    var percentage: Int
    /// Apakah sedang dalam kondisi charging
    var isCharging: Bool
    /// Apakah charger/adapter terhubung (bisa plugged in tapi tidak charging)
    var isPluggedIn: Bool
    /// True jika baterai sudah mencapai charge limit yang di-set user
    var chargeLimitReached: Bool
    /// Timestamp terakhir update
    var lastUpdated: Date

    static let placeholder = BatteryStatus(
        percentage: 0,
        isCharging: false,
        isPluggedIn: false,
        chargeLimitReached: false,
        lastUpdated: .distantPast
    )
}

// MARK: - Battery Specs (static / semi-static)

/// Informasi statis dari IOKit AppleSmartBattery
struct BatterySpecs: Equatable {
    /// Kapasitas desain (mAh) — nilai pabrik
    var designCapacity: Int?
    /// Serial number baterai
    var serialNumber: String?
    /// Nama manufacturer
    var manufacturer: String?
    /// Tanggal manufaktur (parsed dari IOKit DeviceName/ManufactureDate)
    var manufactureDate: Date?
    /// Hardware model
    var deviceName: String?
    /// Firmware versi (jika tersedia)
    var firmwareVersion: String?

    static let empty = BatterySpecs()
}

// MARK: - Battery Health

/// Informasi kesehatan baterai dari IOKit
struct BatteryHealth: Equatable {
    /// Kapasitas maksimum saat ini (mAh) dari AppleRawMaxCapacity
    var maxCapacity: Int?
    /// Kapasitas nominal (mAh) dari NominalChargeCapacity — dipakai macOS System Information
    /// 86% = NominalChargeCapacity(3925) / DesignCapacity(4563)
    var nominalChargeCapacity: Int?
    /// Kapasitas desain (mAh) — sama dengan BatterySpecs.designCapacity
    var designCapacity: Int?
    /// Persentase health versi macOS System Information:
    /// = NominalChargeCapacity / DesignCapacity × 100
    /// Jika NominalChargeCapacity tidak tersedia, fallback ke AppleRawMaxCapacity
    var healthPercent: Double? {
        if let nominal = nominalChargeCapacity, let design = designCapacity, design > 0 {
            return Double(nominal) / Double(design) * 100.0
        }
        guard let max = maxCapacity, let design = designCapacity, design > 0 else { return nil }
        return Double(max) / Double(design) * 100.0
    }
    /// Jumlah siklus pengisian
    var cycleCount: Int?
    /// Kondisi baterai dari macOS (Good, Fair, Poor, dll.)
    /// IOKit key: BatteryHealthCondition
    var condition: String?
    /// Persentase maksimum kapasitas dari macOS Health Assessment
    /// IOKit key: BatteryHealthMaxCapacityPercent
    var maxCapacityPercent: Int?

    static let empty = BatteryHealth()
}


// MARK: - Power Adapter Info

/// Informasi adapter eksternal dari IOPSCopyExternalPowerAdapterDetails()
struct AdapterInfo: Equatable {
    /// Wattage adapter (Watt)
    var wattage: Double?
    /// Arus output (Ampere)
    var amperage: Double?
    /// Tegangan output (Volt)
    var voltage: Double?
    /// Nama/deskripsi adapter
    var name: String?
    /// Family (USB-C / MagSafe, dll.)
    var family: String?

    /// True jika adapter terhubung
    var isConnected: Bool { wattage != nil }

    static let disconnected = AdapterInfo()
}

// MARK: - Power Flow

/// Data konsumsi daya real-time
struct PowerFlow: Equatable {
    /// Arus saat ini (mA dari IOKit, dikonversi ke Ampere)
    var amperage: Double?
    /// Tegangan (mV dari IOKit, dikonversi ke Volt)
    var voltage: Double?
    /// Daya sesaat = |amperage × voltage| (Watt)
    var instantWattage: Double? {
        guard let a = amperage, let v = voltage else { return nil }
        return abs(a * v)
    }
    /// Arah aliran: positif = charging, negatif = discharging
    var isCharging: Bool { (amperage ?? 0) > 0 }
    /// Estimasi waktu tersisa (menit), dari IOPSGetTimeRemainingEstimate()
    /// Nilai khusus: -1 = sedang kalkulasi, -2 = tidak terbatas (saat charging penuh)
    var timeRemainingMinutes: Double?

    static let empty = PowerFlow()
}

// MARK: - Charge Limit State

/// State charge limit yang di-set user
struct ChargeLimitState: Equatable {
    /// Batas pengisian (20–100%)
    var limitPercent: Int
    /// Apakah fitur aktif
    var isEnabled: Bool
    /// Apakah dalam discharge mode (jalan di baterai meski plugged in)
    var dischargeModeEnabled: Bool

    static let `default` = ChargeLimitState(
        limitPercent: 80,
        isEnabled: false,
        dischargeModeEnabled: false
    )
}
