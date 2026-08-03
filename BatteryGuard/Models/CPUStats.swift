// CPUStats.swift
// BatteryGuard — CPU usage data model

import Foundation

/// Statistik penggunaan CPU dari Mach host_processor_info
struct CPUStats: Equatable {
    /// Persentase total CPU usage (0–100)
    var totalUsagePercent: Double
    /// Timestamp polling (tidak diikutkan dalam perbandingan Equatable)
    var timestamp: Date

    /// Format singkat untuk menu bar (misal "42%")
    var shortFormatted: String {
        String(format: "%.0f%%", totalUsagePercent)
    }

    /// Dua CPUStats dianggap sama jika usage-nya identik dalam resolusi 1%
    /// Timestamp diabaikan — menghindari re-render SwiftUI yang tidak perlu
    static func == (lhs: CPUStats, rhs: CPUStats) -> Bool {
        Int(lhs.totalUsagePercent.rounded()) == Int(rhs.totalUsagePercent.rounded())
    }

    static let zero = CPUStats(totalUsagePercent: 0, timestamp: .distantPast)
}
