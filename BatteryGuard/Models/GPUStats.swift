// GPUStats.swift
// BatteryGuard — GPU usage data model

import Foundation

/// Statistik penggunaan GPU (Apple Silicon integrated GPU via IOKit)
struct GPUStats: Equatable {
    /// Persentase GPU usage (0–100), nil jika tidak tersedia
    var usagePercent: Double?
    /// Timestamp polling (tidak diikutkan dalam perbandingan Equatable)
    var timestamp: Date

    /// Format singkat untuk menu bar (misal "44%"), "--" jika tidak ada data
    var shortFormatted: String {
        guard let usage = usagePercent else { return "--" }
        return String(format: "%.0f%%", usage)
    }

    /// Dua GPUStats dianggap sama jika usage-nya identik dalam resolusi 1%
    /// Timestamp diabaikan — menghindari re-render SwiftUI yang tidak perlu
    static func == (lhs: GPUStats, rhs: GPUStats) -> Bool {
        switch (lhs.usagePercent, rhs.usagePercent) {
        case (nil, nil): return true
        case (let a?, let b?): return Int(a.rounded()) == Int(b.rounded())
        default: return false
        }
    }

    static let zero = GPUStats(usagePercent: nil, timestamp: .distantPast)
}
