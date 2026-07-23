// RAMStats.swift
// BatteryGuard — RAM/Memory usage data model

import Foundation

/// Statistik penggunaan memori dari Mach vm_statistics64
struct RAMStats: Equatable {
    /// Total physical memory (bytes)
    var totalBytes: UInt64
    /// Active memory — sedang digunakan oleh proses aktif (bytes)
    var activeBytes: UInt64
    /// Inactive memory — bisa di-reclaim (bytes)
    var inactiveBytes: UInt64
    /// Wired memory — tidak bisa di-swap (bytes)
    var wiredBytes: UInt64
    /// Compressed/swap memory (bytes)
    var compressedBytes: UInt64
    /// Free memory (bytes)
    var freeBytes: UInt64
    /// Timestamp polling
    var timestamp: Date

    // MARK: - Computed Properties

    /// Memory yang dianggap "used" = active + wired + compressed
    var usedBytes: UInt64 { activeBytes + wiredBytes + compressedBytes }

    /// Persentase penggunaan (0.0–1.0)
    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// Persentase dalam persen (0–100)
    var usagePercent: Double { usageRatio * 100.0 }

    /// Format GB dipakai / total GB
    var formattedUsage: String {
        let usedGB = Double(usedBytes) / 1_073_741_824
        let totalGB = Double(totalBytes) / 1_073_741_824
        return String(format: "%.1f / %.0f GB", usedGB, totalGB)
    }

    /// Format singkat untuk menu bar (misal "12.4 GB")
    var shortFormatted: String {
        let usedGB = Double(usedBytes) / 1_073_741_824
        return String(format: "%.1fG", usedGB)
    }

    static let zero = RAMStats(
        totalBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        freeBytes: 0,
        timestamp: .distantPast
    )
}
