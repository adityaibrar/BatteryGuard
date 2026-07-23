// RAMStats.swift
// BatteryGuard — RAM/Memory usage data model
// Formula cocok dengan Activity Monitor macOS

import Foundation

/// Statistik penggunaan memori dari Mach vm_statistics64
/// Semua formula IDENTIK dengan Activity Monitor macOS
struct RAMStats: Equatable {
    /// Total physical memory (bytes)
    var totalBytes: UInt64
    /// App Memory — sedang dipakai proses aktif (bytes)
    var activeBytes: UInt64
    /// Inactive/Cached Files — bisa di-reclaim oleh OS (bytes)
    var inactiveBytes: UInt64
    /// Wired Memory — kernel + non-pageable (bytes)
    var wiredBytes: UInt64
    /// Compressed Memory (bytes)
    var compressedBytes: UInt64
    /// Speculative Memory — pre-fetched, siap di-free (bytes)
    var speculativeBytes: UInt64
    /// Free Memory — benar-benar kosong (bytes)
    var freeBytes: UInt64
    /// Timestamp polling
    var timestamp: Date

    // MARK: - Computed Properties (Activity Monitor formula)

    /// "Memory Used" di Activity Monitor = App + Wired + Compressed
    /// TIDAK termasuk inactive/cached (itu "Cached Files")
    var usedBytes: UInt64 { activeBytes + wiredBytes + compressedBytes }

    /// "Cached Files" di Activity Monitor = inactive + speculative
    var cachedBytes: UInt64 { inactiveBytes + speculativeBytes }

    /// Persentase Used/Total (0.0–1.0), sama dengan Activity Monitor Memory Pressure
    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// Persentase dalam persen (0–100)
    var usagePercent: Double { usageRatio * 100.0 }

    /// Format "X.X / Y GB" — Used vs Total
    var formattedUsage: String {
        let usedGB  = Double(usedBytes)  / 1_073_741_824
        let totalGB = Double(totalBytes) / 1_073_741_824
        return String(format: "%.1f / %.0f GB", usedGB, totalGB)
    }

    /// Format singkat untuk menu bar (misal "12.4 GB used")
    var shortFormatted: String {
        let usedGB = Double(usedBytes) / 1_073_741_824
        return String(format: "%.1fG", usedGB)
    }

    /// Format detail breakdown (misal "App: 5.2G | Wired: 2.1G | Comp: 0.8G")
    var detailFormatted: String {
        func gb(_ b: UInt64) -> String { String(format: "%.1f", Double(b) / 1_073_741_824) }
        return "App: \(gb(activeBytes))G  Wired: \(gb(wiredBytes))G  Comp: \(gb(compressedBytes))G"
    }

    static let zero = RAMStats(
        totalBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        speculativeBytes: 0,
        freeBytes: 0,
        timestamp: .distantPast
    )
}
