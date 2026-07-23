// RAMMonitor.swift
// BatteryGuard — Monitor penggunaan RAM via Mach API
// Menggunakan host_statistics64 dengan HOST_VM_INFO64 — public API, tidak butuh privilege

import Foundation

// MARK: - RAMMonitor

/// Membaca statistik memori dari Mach kernel secara periodik
/// API: host_statistics64(mach_host_self(), HOST_VM_INFO64, ...) → vm_statistics64_data_t
final class RAMMonitor: ObservableObject {

    // MARK: - Published

    @Published var ramStats: RAMStats = .zero

    // MARK: - Private

    private var timer: Timer?
    private let pollingInterval: TimeInterval
    private let hostPort = mach_host_self()

    // MARK: - Init

    init(pollingInterval: TimeInterval = 1.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Baca langsung saat start
        readMemoryStats()

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.readMemoryStats()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Memory Reading

    /// Baca vm_statistics64 dari Mach kernel
    private func readMemoryStats() {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            // Gagal baca — tidak perlu crash, cukup log
            return
        }

        // Page size dari kernel (biasanya 16KB di Apple Silicon)
        let pageSize = UInt64(vm_kernel_page_size)

        // Total physical RAM dari ProcessInfo
        let totalBytes = UInt64(ProcessInfo.processInfo.physicalMemory)

        // Kalkulasi bytes per kategori
        let activeBytes     = UInt64(vmStats.active_count)     * pageSize
        let inactiveBytes   = UInt64(vmStats.inactive_count)   * pageSize
        let wiredBytes      = UInt64(vmStats.wire_count)       * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let freeBytes       = UInt64(vmStats.free_count)       * pageSize

        let stats = RAMStats(
            totalBytes: totalBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            freeBytes: freeBytes,
            timestamp: Date()
        )

        // Pastikan update di main thread
        DispatchQueue.main.async { [weak self] in
            self?.ramStats = stats
        }
    }
}
