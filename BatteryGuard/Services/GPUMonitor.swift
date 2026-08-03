// GPUMonitor.swift
// BatteryGuard — Monitor penggunaan GPU Apple Silicon via IOKit
// Membaca "Device Utilization %" dari IOAccelerator
//
// Optimasi CPU usage:
// - Gunakan DispatchSourceTimer di background queue (bukan Timer di main RunLoop)
// - Interval dinaikkan 1s → 3s (GPU data jarang berubah drastis)
// - IOServiceGetMatchingServices di-cache — tidak perlu traversal IOKit setiap tick

import Foundation
import IOKit

// MARK: - GPUMonitor

/// Membaca GPU usage dari IOKit IOAccelerator secara periodik
/// Bekerja pada Apple Silicon (M1/M2/M3/M4) — integrated GPU
final class GPUMonitor: ObservableObject {

    // MARK: - Published

    @Published var gpuStats: GPUStats = .zero

    // MARK: - Private

    /// DispatchSourceTimer berjalan di background queue — tidak memblokir main thread
    private var timerSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.batteryguard.gpu-monitor", qos: .utility)
    private let pollingInterval: TimeInterval

    /// Cache daftar IOAccelerator service objects
    /// IOAccelerator adalah GPU internal yang selalu ada selama device hidup
    private var cachedServices: [io_object_t] = []

    // MARK: - Init

    init(pollingInterval: TimeInterval = 3.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        queue.async { [weak self] in
            // Buat cache service handles satu kali
            self?.buildServiceCache()
            // Baca pertama kali
            self?.readGPUUsage()
        }

        // Setup DispatchSourceTimer di background queue
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(300) // toleransi ±300ms
        )
        source.setEventHandler { [weak self] in
            self?.readGPUUsage()
        }
        source.resume()
        timerSource = source
    }

    func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil

        // Lepaskan semua cached service handles
        queue.async { [weak self] in
            self?.releaseServiceCache()
        }
    }

    // MARK: - IOKit Service Cache

    /// Buat cache io_object_t untuk semua IOAccelerator service
    /// Dipanggil sekali saat startMonitoring — jauh lebih efisien daripada
    /// memanggil IOServiceGetMatchingServices() setiap tick
    private func buildServiceCache() {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return }

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var services: [io_object_t] = []
        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            // Retain service agar tetap valid setelah iterator direlease
            services.append(service)
            service = IOIteratorNext(iterator)
        }
        cachedServices = services
    }

    /// Lepaskan semua cached service handles
    private func releaseServiceCache() {
        for service in cachedServices {
            IOObjectRelease(service)
        }
        cachedServices.removeAll()
    }

    // MARK: - GPU Reading
    // Dipanggil dari background queue — aman untuk IOKit calls

    private func readGPUUsage() {
        let usage = fetchGPUUsagePercent()
        let stats = GPUStats(usagePercent: usage, timestamp: Date())

        DispatchQueue.main.async { [weak self] in
            self?.gpuStats = stats
        }
    }

    /// Membaca GPU utilization dari cached IOAccelerator services
    /// Key: "Device Utilization %" — tersedia di Apple Silicon (M-series)
    private func fetchGPUUsagePercent() -> Double? {
        // Jika cache kosong (misalnya setelah sleep/wake), rebuild
        if cachedServices.isEmpty {
            buildServiceCache()
            guard !cachedServices.isEmpty else { return nil }
        }

        var totalUsage: Double = 0
        var count = 0

        for service in cachedServices {
            var properties: Unmanaged<CFMutableDictionary>?
            let propResult = IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            )

            guard propResult == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any]
            else { continue }

            // Cari "PerformanceStatistics" dictionary
            if let perfStats    = props["PerformanceStatistics"] as? [String: Any],
               let utilization  = perfStats["Device Utilization %"] as? Double {
                totalUsage += utilization
                count      += 1
            }
        }

        guard count > 0 else { return nil }
        // Rata-rata jika ada lebih dari 1 accelerator
        return totalUsage / Double(count)
    }
}
