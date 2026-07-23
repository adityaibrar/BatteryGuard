// BatteryGuardXPCProtocol.swift
// BatteryGuard — Shared XPC protocol antara Main App dan Privileged Helper
// File ini di-include ke KEDUA target: BatteryGuard dan BatteryGuardHelper

import Foundation

// MARK: - XPC Protocol

/// Protocol yang diimplementasikan oleh HelperTool (server side)
/// @objc required karena NSXPCConnection menggunakan ObjC runtime
@objc(BatteryGuardXPCProtocol)
protocol BatteryGuardXPCProtocol {

    /// Set charge limit pada power management system
    /// - Parameters:
    ///   - limit: Persentase limit (20–100)
    ///   - reply: Callback dengan (success, errorMessage?)
    /// - Note: Implementasi actual di HelperTool.swift — stub kosong untuk scaffolding
    func applyChargeLimit(
        _ limit: Int,
        reply: @escaping (_ success: Bool, _ errorMessage: String?) -> Void
    )

    /// Enable/disable discharge mode (jalan di baterai meski plugged in)
    /// - Parameters:
    ///   - enabled: true untuk aktifkan discharge mode
    ///   - reply: Callback dengan (success, errorMessage?)
    func setDischargeModeEnabled(
        _ enabled: Bool,
        reply: @escaping (_ success: Bool, _ errorMessage: String?) -> Void
    )

    /// Disable charge limit (restore ke behavior default macOS)
    /// - Parameter reply: Callback dengan (success, errorMessage?)
    func disableChargeLimit(
        reply: @escaping (_ success: Bool, _ errorMessage: String?) -> Void
    )

    /// Ambil versi helper yang ter-install
    /// Berguna untuk verifikasi compatibility antara app dan helper
    func getHelperVersion(reply: @escaping (_ version: String) -> Void)

    /// Uninstall helper tool (opsional, untuk clean uninstall)
    func uninstallHelper(reply: @escaping (_ success: Bool) -> Void)
}

// MARK: - XPC Interface

extension BatteryGuardXPCProtocol {
    /// Bundle ID helper — harus match dengan target name di Xcode
    static var helperBundleID: String { "com.ibrardev.BatteryGuard.Helper" }

    /// Nama Mach service untuk XPC listener (harus match di helper's Info.plist)
    static var machServiceName: String { "com.ibrardev.BatteryGuard.Helper" }
}

// MARK: - NSXPCInterface Factory

/// Buat NSXPCInterface yang sudah dikonfigurasi untuk BatteryGuardXPCProtocol
/// Harus dipanggil di KEDUA sisi (app dan helper) dengan konfigurasi yang sama
func makeBatteryGuardXPCInterface() -> NSXPCInterface {
    return NSXPCInterface(with: BatteryGuardXPCProtocol.self)
}
