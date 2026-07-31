// CPUStats.swift
// BatteryGuard — CPU usage data model

import Foundation

/// Statistik penggunaan CPU dari Mach host_processor_info
struct CPUStats: Equatable {
    /// Persentase total CPU usage (0–100)
    var totalUsagePercent: Double
    /// Timestamp polling
    var timestamp: Date

    /// Format singkat untuk menu bar (misal "42%")
    var shortFormatted: String {
        String(format: "%.0f%%", totalUsagePercent)
    }

    static let zero = CPUStats(totalUsagePercent: 0, timestamp: .distantPast)
}
