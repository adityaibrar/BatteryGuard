// CPUMonitor.swift
// BatteryGuard — Monitor penggunaan CPU via Mach host_processor_info
// Formula: (user + system + nice) / total ticks per interval

import Foundation

// MARK: - CPUMonitor

/// Membaca total CPU usage dari Mach kernel secara periodik
/// API: host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, ...)
final class CPUMonitor: ObservableObject {

    // MARK: - Published

    @Published var cpuStats: CPUStats = .zero

    // MARK: - Private

    private var timer: Timer?
    private let pollingInterval: TimeInterval
    private var previousInfo: [processor_cpu_load_info]?

    // MARK: - Init

    init(pollingInterval: TimeInterval = 1.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Baca pertama kali untuk inisialisasi baseline
        _ = readCPUInfo()

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.updateCPUStats()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - CPU Reading

    private func updateCPUStats() {
        guard let current = readCPUInfo() else { return }
        defer { previousInfo = current }

        guard let previous = previousInfo, previous.count == current.count else {
            previousInfo = current
            return
        }

        // Hitung delta ticks untuk setiap core, lalu rata-rata
        var totalIdle: Double = 0
        var totalAll: Double = 0

        for i in 0..<current.count {
            let curTicks = current[i]
            let prevTicks = previous[i]

            let user   = Double(curTicks.cpu_ticks.0) - Double(prevTicks.cpu_ticks.0)
            let system = Double(curTicks.cpu_ticks.1) - Double(prevTicks.cpu_ticks.1)
            let idle   = Double(curTicks.cpu_ticks.2) - Double(prevTicks.cpu_ticks.2)
            let nice   = Double(curTicks.cpu_ticks.3) - Double(prevTicks.cpu_ticks.3)

            let total = user + system + idle + nice
            totalIdle += idle
            totalAll  += total
        }

        let usage = totalAll > 0 ? (1.0 - totalIdle / totalAll) * 100.0 : 0.0
        let stats = CPUStats(totalUsagePercent: usage, timestamp: Date())

        DispatchQueue.main.async { [weak self] in
            self?.cpuStats = stats
        }
    }

    /// Baca processor info dari Mach kernel
    private func readCPUInfo() -> [processor_cpu_load_info]? {
        var processorInfo: processor_info_array_t?
        var processorMsgCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )

        guard result == KERN_SUCCESS, let info = processorInfo else { return nil }

        // Cast ke array of processor_cpu_load_info
        let count = Int(processorCount)
        var loadInfoArray = [processor_cpu_load_info]()
        loadInfoArray.reserveCapacity(count)

        // Stride dalam integer_t (sesuai Mach API output)
        let stride = MemoryLayout<processor_cpu_load_info>.size / MemoryLayout<integer_t>.size

        for i in 0..<count {
            let offset = stride * i
            let loadInfo = withUnsafePointer(to: info[offset]) {
                $0.withMemoryRebound(to: processor_cpu_load_info.self, capacity: 1) { $0.pointee }
            }
            loadInfoArray.append(loadInfo)
        }

        // Dealokasi memory dari kernel
        let size = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)

        return loadInfoArray
    }
}
