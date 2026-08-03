// TemperatureReading.swift
// BatteryGuard — Temperature sensor data model

import Foundation

/// Satu pembacaan sensor suhu
struct TemperatureReading: Equatable, Identifiable {
    var id: String { sensorName }
    /// Nama sensor (misal "CPU Core", "Battery", "Ambient")
    var sensorName: String
    /// Suhu dalam Celsius
    var celsius: Double
    /// Timestamp pembacaan (tidak diikutkan dalam perbandingan Equatable)
    var timestamp: Date

    /// Suhu dalam Fahrenheit
    var fahrenheit: Double { celsius * 9 / 5 + 32 }

    /// Format display: "42.5°C"
    var formattedCelsius: String { String(format: "%.1f°C", celsius) }
    /// Format singkat untuk menu bar: "43°"
    var shortFormatted: String { String(format: "%.0f°", celsius) }

    /// Dua pembacaan dianggap sama jika suhunya beda kurang dari 0.5°C
    /// Timestamp diabaikan — menghindari re-render SwiftUI yang tidak perlu
    static func == (lhs: TemperatureReading, rhs: TemperatureReading) -> Bool {
        lhs.sensorName == rhs.sensorName &&
        abs(lhs.celsius - rhs.celsius) < 0.5
    }
}

/// Kumpulan semua pembacaan sensor dalam satu snapshot
struct SystemTemperatures: Equatable {
    /// Suhu CPU (diambil dari sensor CPU terkait)
    var cpuTemperature: TemperatureReading?
    /// Suhu baterai (dari IOKit AppleSmartBattery Temperature key)
    var batteryTemperature: TemperatureReading?
    /// Semua sensor yang tersedia
    var allReadings: [TemperatureReading]
    /// Timestamp snapshot (tidak diikutkan dalam perbandingan Equatable)
    var timestamp: Date

    /// Suhu CPU untuk display di menu bar
    var cpuTempFormatted: String {
        cpuTemperature?.shortFormatted ?? "--°"
    }

    /// Dua snapshot dianggap sama jika suhu CPU dan baterai-nya identik
    /// Timestamp diabaikan — menghindari re-render SwiftUI yang tidak perlu
    static func == (lhs: SystemTemperatures, rhs: SystemTemperatures) -> Bool {
        lhs.cpuTemperature == rhs.cpuTemperature &&
        lhs.batteryTemperature == rhs.batteryTemperature
    }

    static let empty = SystemTemperatures(
        cpuTemperature: nil,
        batteryTemperature: nil,
        allReadings: [],
        timestamp: .distantPast
    )
}
