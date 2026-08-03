// NetworkSpeedMonitor.swift
// BatteryGuard — Monitor kecepatan jaringan via getifaddrs()
//
// Strategi (sama dengan Activity Monitor):
// 1. Temukan interface yang punya IP address aktif (AF_INET / AF_INET6)
// 2. Baca AF_LINK byte counter HANYA untuk interface tersebut
// 3. Delta / interval = speed bytes per detik
//
// Ini memastikan nilai sama dengan Activity Monitor karena:
// - En1/En2 (Thunderbolt bridge) diexclude — IFF_RUNNING tapi tidak punya IP
// - anpi0/anpi1, awdl0, llw0, ap1 juga diexclude dengan cara yang sama
// - utun* (VPN) diinclude hanya jika aktif dengan IP
//
// Optimasi CPU usage:
// - Gunakan DispatchSourceTimer di background queue (bukan Timer di main RunLoop)
// - Interval dinaikkan 1s → 2s (cukup untuk indikasi traffic, jauh lebih hemat)

import Foundation
import Darwin

// MARK: - NetworkSpeedMonitor

/// Membaca kecepatan upload/download dari network interface secara real-time
/// Hanya memonitor interface yang punya IP address aktif (= Activity Monitor behavior)
final class NetworkSpeedMonitor: ObservableObject {

    // MARK: - Published

    @Published var networkStats: NetworkStats = .zero

    // MARK: - Private

    /// DispatchSourceTimer berjalan di background queue — tidak memblokir main thread
    private var timerSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.batteryguard.network-monitor", qos: .utility)
    private let pollingInterval: TimeInterval
    /// Snapshot sebelumnya untuk menghitung delta
    private var previousSnapshot: [NetworkInterfaceSnapshot] = []

    // MARK: - Init

    init(pollingInterval: TimeInterval = 2.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Ambil snapshot awal di background (tanpa hitung speed dulu)
        queue.async { [weak self] in
            self?.previousSnapshot = self?.getCurrentSnapshot() ?? []
        }

        // Setup DispatchSourceTimer di background queue
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(200) // toleransi ±200ms
        )
        source.setEventHandler { [weak self] in
            self?.updateNetworkSpeed()
        }
        source.resume()
        timerSource = source
    }

    func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil
        previousSnapshot = []
    }

    // MARK: - Speed Calculation
    // Dipanggil dari background queue — aman untuk getifaddrs() calls

    private func updateNetworkSpeed() {
        let currentSnapshot = getCurrentSnapshot()
        let now = Date()

        var totalDownload: Double = 0
        var totalUpload: Double   = 0
        var primaryInterface      = "—"

        for current in currentSnapshot {
            if let previous = previousSnapshot.first(where: { $0.name == current.name }) {
                let interval = current.timestamp.timeIntervalSince(previous.timestamp)
                guard interval > 0 else { continue }

                // Wrapping subtraction untuk handle counter overflow/reset
                let rxDelta = current.rxBytes &- previous.rxBytes
                let txDelta = current.txBytes &- previous.txBytes

                // Sanity check: skip jika delta tidak masuk akal (>10 Gbps)
                let maxReasonableBytesPerSec: UInt64 = 1_250_000_000
                guard rxDelta <= maxReasonableBytesPerSec, txDelta <= maxReasonableBytesPerSec
                else { continue }

                let downloadSpeed = Double(rxDelta) / interval
                let uploadSpeed   = Double(txDelta) / interval

                totalDownload += downloadSpeed
                totalUpload   += uploadSpeed

                // Simpan nama interface pertama yang punya traffic sebagai primary
                if downloadSpeed + uploadSpeed > 0, primaryInterface == "—" {
                    primaryInterface = current.name
                }
            }
        }

        // Update snapshot untuk iterasi berikutnya
        previousSnapshot = currentSnapshot

        let stats = NetworkStats(
            downloadBytesPerSec: totalDownload,
            uploadBytesPerSec: totalUpload,
            primaryInterface: friendlyName(primaryInterface),
            timestamp: now
        )

        DispatchQueue.main.async { [weak self] in
            self?.networkStats = stats
        }
    }

    // MARK: - getifaddrs() Two-Pass Snapshot
    //
    // Pass 1: kumpulkan nama interface yang punya AF_INET atau AF_INET6 address.
    //         Ini secara natural mengexclude: Thunderbolt bridge (en1/en2),
    //         anpi, awdl, llw, ap1 — semua yang RUNNING tapi tidak connected ke network.
    //
    // Pass 2: baca AF_LINK byte counter hanya untuk interface dari Pass 1.
    //
    // Hasilnya identik dengan apa yang dimonitor Activity Monitor.

    private func getCurrentSnapshot() -> [NetworkInterfaceSnapshot] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        // --- Pass 1: Kumpulkan interface yang punya IP address aktif ---
        var activeInterfaces = Set<String>()
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let current = ptr {
            let iface  = current.pointee
            let name   = String(cString: iface.ifa_name)
            let family = iface.ifa_addr?.pointee.sa_family ?? 0

            // Hanya interface dengan IPv4 atau IPv6 address nyata
            if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                // Skip loopback (127.x, ::1)
                let flags      = Int32(iface.ifa_flags)
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                if !isLoopback {
                    activeInterfaces.insert(name)
                }
            }
            ptr = iface.ifa_next
        }

        // --- Pass 2: Baca AF_LINK stats hanya untuk interface aktif ---
        var snapshots: [NetworkInterfaceSnapshot] = []
        ptr = firstAddr

        while let current = ptr {
            let iface  = current.pointee
            let name   = String(cString: iface.ifa_name)
            let family = iface.ifa_addr?.pointee.sa_family ?? 0

            // Hanya proses interface dari Pass 1 dengan AF_LINK data
            guard activeInterfaces.contains(name), family == UInt8(AF_LINK) else {
                ptr = iface.ifa_next
                continue
            }

            // Interface harus dalam state RUNNING
            let flags     = Int32(iface.ifa_flags)
            let isRunning = (flags & IFF_RUNNING) != 0
            guard isRunning else {
                ptr = iface.ifa_next
                continue
            }

            // Baca byte counter dari if_data struct
            if let data = iface.ifa_data?.load(as: if_data.self) {
                snapshots.append(NetworkInterfaceSnapshot(
                    name: name,
                    rxBytes: UInt64(data.ifi_ibytes),
                    txBytes: UInt64(data.ifi_obytes),
                    timestamp: Date()
                ))
            }

            ptr = iface.ifa_next
        }

        return snapshots
    }

    // MARK: - Friendly Name

    /// Konversi nama interface ke label yang mudah dibaca
    private func friendlyName(_ name: String) -> String {
        if name == "—"  { return "—" }
        if name.hasPrefix("en0")  { return "Wi-Fi" }
        if name.hasPrefix("en")   { return "Ethernet" }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") { return "VPN" }
        if name.hasPrefix("ppp")  { return "PPP" }
        return name
    }
}
