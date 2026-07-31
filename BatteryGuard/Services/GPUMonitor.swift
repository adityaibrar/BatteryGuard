// GPUMonitor.swift
// BatteryGuard — Monitor penggunaan GPU Apple Silicon via IOKit
// Membaca "Device Utilization %" dari IOAccelerator

import Foundation
import IOKit

// MARK: - GPUMonitor

/// Membaca GPU usage dari IOKit IOAccelerator secara periodik
/// Bekerja pada Apple Silicon (M1/M2/M3/M4) — integrated GPU
final class GPUMonitor: ObservableObject {

    // MARK: - Published

    @Published var gpuStats: GPUStats = .zero

    // MARK: - Private

    private var timer: Timer?
    private let pollingInterval: TimeInterval

    // MARK: - Init

    init(pollingInterval: TimeInterval = 1.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        readGPUUsage()

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.readGPUUsage()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - GPU Reading

    private func readGPUUsage() {
        let usage = fetchGPUUsagePercent()
        let stats = GPUStats(usagePercent: usage, timestamp: Date())

        DispatchQueue.main.async { [weak self] in
            self?.gpuStats = stats
        }
    }

    /// Membaca GPU utilization dari IOKit IOAccelerator
    /// Key: "Device Utilization %" — tersedia di Apple Silicon (M-series)
    private func fetchGPUUsagePercent() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        )

        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var totalUsage: Double = 0
        var count = 0

        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            // Baca properties dari service
            var properties: Unmanaged<CFMutableDictionary>?
            let propResult = IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            )

            guard propResult == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Cari "PerformanceStatistics" dictionary
            if let perfStats = props["PerformanceStatistics"] as? [String: Any],
               let utilization = perfStats["Device Utilization %"] as? Double {
                totalUsage += utilization
                count += 1
            }
        }

        guard count > 0 else { return nil }
        // Rata-rata jika ada lebih dari 1 accelerator
        return totalUsage / Double(count)
    }
}
