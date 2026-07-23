// HelperTool.swift
// BatteryGuardHelper — Implementasi XPC protocol di server side
// Berjalan dengan elevated privileges sebagai daemon

import Foundation

// MARK: - Helper Tool Implementation

/// Implementasi BatteryGuardXPCProtocol di sisi helper (privileged)
/// Semua method charge control adalah TODO — user mengisi implementasi
/// actual setelah riset mekanisme Apple Silicon power management
final class HelperTool: NSObject, BatteryGuardXPCProtocol {

    /// Versi helper — harus di-increment saat ada perubahan interface
    static let version = "1.0.0"

    // MARK: - Charge Limit

    /// TODO: Implementasikan mekanisme charge limiting untuk Apple Silicon
    ///
    /// Referensi untuk diriset secara mandiri:
    /// - `bclm` project: menggunakan IOKit untuk write ke AppleSmartBattery
    /// - Apple Silicon berbeda dengan Intel (bukan SMC keys biasa)
    /// - Cek `ioreg -brl AppleSmartBattery` untuk melihat writable keys
    /// - Perlu root/elevated privilege untuk write ke IOKit registry
    ///
    /// - Parameters:
    ///   - limit: Persentase limit 20–100
    ///   - reply: Callback (success, errorMessage?)
    func applyChargeLimit(_ limit: Int, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] applyChargeLimit called with limit: %d", limit)

        // Validasi input
        guard limit >= 20 && limit <= 100 else {
            reply(false, "Limit harus antara 20-100%")
            return
        }

        // TODO: Implementasi actual charge limit di sini
        // Contoh struktur yang perlu diisi:
        //
        // do {
        //     try PowerManagementService.setChargeLimit(limit)
        //     reply(true, nil)
        // } catch {
        //     reply(false, error.localizedDescription)
        // }

        NSLog("[HelperTool] ⚠️ applyChargeLimit: stub, implementasi belum diisi")
        reply(false, "Stub: implementasi charge limit belum diisi. Riset mekanisme Apple Silicon dulu.")
    }

    // MARK: - Discharge Mode

    /// TODO: Implementasikan discharge mode untuk Apple Silicon
    ///
    /// Discharge mode: paksa Mac jalan dari baterai meski adapter terhubung
    /// Ini lebih kompleks dari charge limit dan butuh riset lebih lanjut
    ///
    /// - Parameters:
    ///   - enabled: true untuk aktifkan
    ///   - reply: Callback (success, errorMessage?)
    func setDischargeModeEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] setDischargeModeEnabled called: %@", enabled ? "true" : "false")

        // TODO: Implementasi actual discharge mode di sini
        NSLog("[HelperTool] ⚠️ setDischargeModeEnabled: stub, implementasi belum diisi")
        reply(false, "Stub: implementasi discharge mode belum diisi.")
    }

    // MARK: - Disable Charge Limit

    /// Restore behavior charging default macOS
    func disableChargeLimit(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] disableChargeLimit called")

        // TODO: Restore ke behavior default (biasanya set limit ke 100)
        NSLog("[HelperTool] ⚠️ disableChargeLimit: stub, implementasi belum diisi")
        reply(false, "Stub: implementasi disable charge limit belum diisi.")
    }

    // MARK: - Helper Info

    /// Return versi helper yang ter-install
    func getHelperVersion(reply: @escaping (String) -> Void) {
        NSLog("[HelperTool] getHelperVersion: %@", HelperTool.version)
        reply(HelperTool.version)
    }

    // MARK: - Uninstall

    /// Uninstall helper tool
    func uninstallHelper(reply: @escaping (Bool) -> Void) {
        NSLog("[HelperTool] uninstallHelper called")
        // SMAppService unregistration dilakukan dari main app
        // Helper hanya perlu exit setelah dapat sinyal ini
        reply(true)
        exit(0)
    }
}
