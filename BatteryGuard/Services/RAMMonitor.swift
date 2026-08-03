// RAMMonitor.swift
// BatteryGuard — Monitor penggunaan RAM via Mach API
// Formula cocok dengan Activity Monitor macOS
//
// Optimasi CPU usage:
// - Gunakan DispatchSourceTimer di background queue (bukan Timer di main RunLoop)
// - Interval dinaikkan 1s → 3s (RAM tidak berfluktuasi cepat)
// - host_statistics64() tidak perlu dipanggil lebih dari setiap 3 detik

import Foundation

// MARK: - RAMMonitor

/// Membaca statistik memori dari Mach kernel secara periodik
/// API: host_statistics64(mach_host_self(), HOST_VM_INFO64, ...) → vm_statistics64_data_t
///
/// Formula cocok dengan Activity Monitor:
///   Used     = active + wired + compressed
///   Cached   = inactive + speculative (bukan "wasted", bisa reclaim)
///   Free     = truly free pages
final class RAMMonitor: ObservableObject {

    // MARK: - Published

    @Published var ramStats: RAMStats = .zero

    // MARK: - Private

    /// DispatchSourceTimer berjalan di background queue — tidak memblokir main thread
    private var timerSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.batteryguard.ram-monitor", qos: .utility)
    private let pollingInterval: TimeInterval
    private let hostPort = mach_host_self()

    // MARK: - Init

    init(pollingInterval: TimeInterval = 3.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Baca langsung saat start (di background)
        queue.async { [weak self] in
            self?.readMemoryStats()
        }

        // Setup DispatchSourceTimer di background queue
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(300) // toleransi ±300ms
        )
        source.setEventHandler { [weak self] in
            self?.readMemoryStats()
        }
        source.resume()
        timerSource = source
    }

    func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil
    }

    // MARK: - Memory Reading
    // Dipanggil dari background queue — aman untuk Mach calls

    /// Baca vm_statistics64 dari Mach kernel
    private func readMemoryStats() {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        // Page size: 16384 bytes (16 KB) di Apple Silicon
        let pageSize = UInt64(vm_kernel_page_size)

        // Total physical RAM
        let totalBytes = UInt64(ProcessInfo.processInfo.physicalMemory)

        // Breakdown sesuai Activity Monitor:
        // ┌─────────────────────────────────────────────────────┐
        // │ "App Memory"  = active (pages sedang dipakai proses)│
        // │ "Wired"       = wired (kernel, non-pageable)        │
        // │ "Compressed"  = compressor_page_count               │
        // │ "Cached"      = inactive + speculative              │
        // │ "Free"        = free_count                          │
        // │ "Used"        = App + Wired + Compressed            │
        // └─────────────────────────────────────────────────────┘
        let activeBytes      = UInt64(vmStats.active_count)          * pageSize
        let inactiveBytes    = UInt64(vmStats.inactive_count)        * pageSize
        let wiredBytes       = UInt64(vmStats.wire_count)            * pageSize
        let compressedBytes  = UInt64(vmStats.compressor_page_count) * pageSize
        let speculativeBytes = UInt64(vmStats.speculative_count)     * pageSize
        let freeBytes        = UInt64(vmStats.free_count)            * pageSize

        let stats = RAMStats(
            totalBytes: totalBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            speculativeBytes: speculativeBytes,
            freeBytes: freeBytes,
            timestamp: Date()
        )

        // Update di main thread
        DispatchQueue.main.async { [weak self] in
            self?.ramStats = stats
        }
    }
}
