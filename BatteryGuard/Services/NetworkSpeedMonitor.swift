// NetworkSpeedMonitor.swift
// BatteryGuard — Monitor kecepatan jaringan via getifaddrs()
// Menggunakan delta byte counter tiap polling interval — public API, tidak butuh privilege

import Foundation
import Darwin

// MARK: - NetworkSpeedMonitor

/// Membaca kecepatan upload/download dari network interface secara real-time
/// Strategi: snapshot byte counter → delta / interval = speed
final class NetworkSpeedMonitor: ObservableObject {

    // MARK: - Published

    @Published var networkStats: NetworkStats = .zero

    // MARK: - Private

    private var timer: Timer?
    private let pollingInterval: TimeInterval
    /// Snapshot sebelumnya untuk menghitung delta
    private var previousSnapshot: [NetworkInterfaceSnapshot] = []

    // MARK: - Init

    init(pollingInterval: TimeInterval = 1.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Ambil snapshot awal (tanpa hitung speed dulu)
        previousSnapshot = getCurrentSnapshot()

        // Start timer — hitung delta dari snapshot kedua dst.
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.updateNetworkSpeed()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        previousSnapshot = []
    }

    // MARK: - Speed Calculation

    private func updateNetworkSpeed() {
        let currentSnapshot = getCurrentSnapshot()
        let now = Date()

        var totalDownload: Double = 0
        var totalUpload: Double = 0
        var primaryInterface = "—"

        for current in currentSnapshot {
            // Cari snapshot sebelumnya untuk interface yang sama
            if let previous = previousSnapshot.first(where: { $0.name == current.name }) {
                let interval = current.timestamp.timeIntervalSince(previous.timestamp)
                guard interval > 0 else { continue }

                // Delta bytes / interval = bytes per second
                // Gunakan wrapping subtraction untuk handle counter overflow
                let rxDelta = current.rxBytes &- previous.rxBytes
                let txDelta = current.txBytes &- previous.txBytes

                // Sanity check: skip jika delta terlalu besar (kemungkinan overflow/reset)
                let maxReasonableBytesPerSec: UInt64 = 1_250_000_000 // ~10 Gbps
                if rxDelta > maxReasonableBytesPerSec || txDelta > maxReasonableBytesPerSec {
                    continue
                }

                let downloadSpeed = Double(rxDelta) / interval
                let uploadSpeed = Double(txDelta) / interval

                totalDownload += downloadSpeed
                totalUpload += uploadSpeed

                // Track interface dengan traffic tertinggi sebagai primary
                if downloadSpeed + uploadSpeed > 0 && primaryInterface == "—" {
                    primaryInterface = current.name
                }
            }
        }

        networkStats = NetworkStats(
            downloadBytesPerSec: totalDownload,
            uploadBytesPerSec: totalUpload,
            primaryInterface: primaryInterface,
            timestamp: now
        )

        // Update snapshot untuk iterasi berikutnya
        previousSnapshot = currentSnapshot
    }

    // MARK: - getifaddrs() Snapshot

    /// Ambil snapshot byte counter dari semua interface via getifaddrs()
    private func getCurrentSnapshot() -> [NetworkInterfaceSnapshot] {
        var snapshots: [NetworkInterfaceSnapshot] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let current = ptr {
            let iface = current.pointee
            let name = String(cString: iface.ifa_name)

            // Filter: hanya proses AF_LINK (link layer), skip loopback
            let flags = Int32(iface.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isRunning = (flags & IFF_RUNNING) != 0

            // Skip loopback (lo0) dan interface yang tidak aktif
            if !isLoopback && isRunning {
                let family = iface.ifa_addr?.pointee.sa_family
                if family == UInt8(AF_LINK) {
                    // Cast ke if_data untuk dapat byte counter
                    if let data = iface.ifa_data?.load(as: if_data.self) {
                        snapshots.append(NetworkInterfaceSnapshot(
                            name: name,
                            rxBytes: UInt64(data.ifi_ibytes),
                            txBytes: UInt64(data.ifi_obytes),
                            timestamp: Date()
                        ))
                    }
                }
            }

            ptr = iface.ifa_next
        }

        // Deduplicate: jika ada beberapa entry untuk interface yang sama,
        // gunakan yang pertama (AF_LINK sudah unik per interface)
        let uniqueNames = Set(snapshots.map { $0.name })
        return uniqueNames.compactMap { name in
            snapshots.first { $0.name == name }
        }
    }

    // MARK: - Interface Filter Helper

    /// Daftar prefix interface yang ingin dimonitor
    /// en = Ethernet/WiFi, utun = VPN, ipsec = VPN
    /// Bridge/VLAN/virtual interfaces di-skip karena biasanya double-count
    private func shouldMonitorInterface(_ name: String) -> Bool {
        let monitored = ["en", "utun", "ipsec", "ppp"]
        let excluded = ["lo", "bridge", "vmnet", "p2p", "awdl", "llw"]

        for prefix in excluded {
            if name.hasPrefix(prefix) { return false }
        }
        for prefix in monitored {
            if name.hasPrefix(prefix) { return true }
        }
        return false
    }
}
