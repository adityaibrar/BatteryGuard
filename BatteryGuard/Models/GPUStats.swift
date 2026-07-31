// GPUStats.swift
// BatteryGuard — GPU usage data model

import Foundation

/// Statistik penggunaan GPU (Apple Silicon integrated GPU via IOKit)
struct GPUStats: Equatable {
    /// Persentase GPU usage (0–100), nil jika tidak tersedia
    var usagePercent: Double?
    /// Timestamp polling
    var timestamp: Date

    /// Format singkat untuk menu bar (misal "44%"), "--" jika tidak ada data
    var shortFormatted: String {
        guard let usage = usagePercent else { return "--" }
        return String(format: "%.0f%%", usage)
    }

    static let zero = GPUStats(usagePercent: nil, timestamp: .distantPast)
}
