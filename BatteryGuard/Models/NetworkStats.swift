// NetworkStats.swift
// BatteryGuard — Network speed data model

import Foundation

/// Data kecepatan jaringan untuk satu polling interval
struct NetworkStats: Equatable {
    /// Kecepatan download saat ini (bytes per detik)
    var downloadBytesPerSec: Double
    /// Kecepatan upload saat ini (bytes per detik)
    var uploadBytesPerSec: Double
    /// Nama interface aktif yang dipakai (misal "en0")
    var primaryInterface: String
    /// Timestamp polling
    var timestamp: Date

    /// Download dalam format human-readable (KB/s, MB/s)
    var downloadFormatted: String { formatSpeed(downloadBytesPerSec) }
    /// Upload dalam format human-readable
    var uploadFormatted: String { formatSpeed(uploadBytesPerSec) }

    static let zero = NetworkStats(
        downloadBytesPerSec: 0,
        uploadBytesPerSec: 0,
        primaryInterface: "—",
        timestamp: .distantPast
    )

    // MARK: - Private Helpers

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let mbPerSec = bytesPerSec / 1_048_576
        if mbPerSec >= 1.0 {
            return String(format: "%.1f MB/s", mbPerSec)
        }
        let kbPerSec = bytesPerSec / 1024
        if kbPerSec >= 1.0 {
            return String(format: "%.0f KB/s", kbPerSec)
        }
        return String(format: "%.0f B/s", bytesPerSec)
    }
}

/// Snapshot byte counter per interface, dipakai untuk menghitung delta
struct NetworkInterfaceSnapshot {
    var name: String
    var rxBytes: UInt64   // Received (download)
    var txBytes: UInt64   // Transmitted (upload)
    var timestamp: Date
}
