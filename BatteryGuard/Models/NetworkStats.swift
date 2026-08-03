// NetworkStats.swift
// BatteryGuard — Network speed data model
// Unit: decimal (SI) — 1 KB = 1,000 bytes, 1 MB = 1,000,000 bytes
// Konsisten dengan Activity Monitor macOS

import Foundation

/// Data kecepatan jaringan untuk satu polling interval
struct NetworkStats: Equatable {
    /// Kecepatan download saat ini (bytes per detik)
    var downloadBytesPerSec: Double
    /// Kecepatan upload saat ini (bytes per detik)
    var uploadBytesPerSec: Double
    /// Nama interface aktif yang dipakai (misal "en0")
    var primaryInterface: String
    /// Timestamp polling (tidak diikutkan dalam perbandingan Equatable)
    var timestamp: Date

    /// Dua NetworkStats dianggap sama jika kecepatan beda kurang dari 50 KB/s
    /// Timestamp diabaikan — menghindari re-render SwiftUI yang tidak perlu
    static func == (lhs: NetworkStats, rhs: NetworkStats) -> Bool {
        abs(lhs.downloadBytesPerSec - rhs.downloadBytesPerSec) < 50_000 &&
        abs(lhs.uploadBytesPerSec   - rhs.uploadBytesPerSec)   < 50_000
    }

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

    /// Format kecepatan dalam satuan decimal (SI) — sama dengan Activity Monitor
    /// 1 KB/s = 1,000 bytes/s  |  1 MB/s = 1,000,000 bytes/s
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let mbPerSec = bytesPerSec / 1_000_000
        if mbPerSec >= 1.0 {
            return String(format: "%.1f MB/s", mbPerSec)
        }
        let kbPerSec = bytesPerSec / 1_000
        if kbPerSec >= 1.0 {
            return String(format: "%.0f KB/s", kbPerSec)
        }
        if bytesPerSec > 0 {
            return String(format: "%.0f B/s", bytesPerSec)
        }
        return "0 KB/s"
    }
}

/// Snapshot byte counter per interface, dipakai untuk menghitung delta
struct NetworkInterfaceSnapshot {
    var name: String
    var rxBytes: UInt64   // Received (download)
    var txBytes: UInt64   // Transmitted (upload)
    var timestamp: Date
}
