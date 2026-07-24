// HelperTool.swift
// BatteryGuardHelper — Implementasi XPC protocol di privileged daemon
//
// Charge limiting menggunakan pendekatan software polling (sama seperti AlDente):
//   - Monitor battery % setiap 15 detik via DispatchSourceTimer
//   - Saat battery% >= limit → tulis CH0B = 0x02 (stop charging)
//   - Saat battery% <= limit - hysteresis → tulis CH0B = 0x00 (allow charging)
//   - Hysteresis default 2% mencegah toggling terlalu cepat

import Foundation
import IOKit

// MARK: - Helper Tool

final class HelperTool: NSObject, BatteryGuardXPCProtocol {

    static let version = "1.0.0"

    /// Satu instance ChargeMonitor per daemon — berjalan selama launchd daemon aktif
    private let monitor = ChargeMonitor()
    private var isMonitoring = false
    private var currentLimit = 100

    // MARK: - applyChargeLimit

    /// Terapkan charge limit dengan nilai persentase bebas (20–100).
    ///
    /// Mekanisme identik dengan AlDente: software polling + SMC CH0B key
    ///   - Battery% >= limit  → CH0B = 0x02 (inhibit/stop charging)
    ///   - Battery% < limit-2 → CH0B = 0x00 (allow charging normal)
    func applyChargeLimit(_ limit: Int, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] applyChargeLimit: %d%%", limit)

        guard limit >= 20 && limit <= 100 else {
            reply(false, "Limit harus antara 20–100%")
            return
        }

        currentLimit = limit

        if limit == 100 {
            // 100% = tidak ada limit — hentikan monitoring dan izinkan charging penuh
            if isMonitoring {
                monitor.stopMonitoring()
                isMonitoring = false
            }
            NSLog("[HelperTool] Limit = 100%%, charge limit dinonaktifkan")
            reply(true, nil)
            return
        }

        if isMonitoring {
            // Monitoring sudah jalan — cukup update limitnya saja
            monitor.updateLimit(limit)
        } else {
            // Mulai monitoring fresh
            monitor.startMonitoring(limit: limit)
            isMonitoring = true
        }

        NSLog("[HelperTool] ✅ Monitoring aktif, limit: %d%%", limit)
        reply(true, nil)
    }

    // MARK: - disableChargeLimit

    /// Nonaktifkan charge limit — baterai boleh isi hingga 100%
    func disableChargeLimit(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] disableChargeLimit dipanggil")
        monitor.stopMonitoring()
        isMonitoring = false
        currentLimit = 100
        reply(true, nil)
    }

    // MARK: - Discharge Mode (belum diimplementasikan)

    func setDischargeModeEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] setDischargeModeEnabled: %@ — belum diimplementasikan",
              enabled ? "true" : "false")
        reply(false, "Discharge mode belum tersedia di versi ini.")
    }

    // MARK: - Version & Uninstall

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply(HelperTool.version)
    }

    func uninstallHelper(reply: @escaping (Bool) -> Void) {
        // Unregister daemon ditangani dari sisi Main App via SMAppService
        reply(false)
    }
}
