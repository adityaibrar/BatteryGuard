// AppDelegate.swift
// BatteryGuard — Application lifecycle + helper installation

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sembunyikan dari Dock (menu bar only app)
        // Sudah dihandle oleh LSUIElement = YES di Info.plist
        // Tapi jika perlu force:
        // NSApp.setActivationPolicy(.accessory)

        // Start semua monitor via ViewModel
        // ViewModel di-inject dari BatteryGuardApp, tapi AppDelegate perlu
        // inisialisasi helper terlebih dahulu
        checkAndInstallHelper()

        // Setup notifikasi dari sistem (baterai sangat rendah, dll.)
        setupSystemNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup jika perlu
        // Helper daemon tetap berjalan setelah app quit (by design)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-open dashboard jika user klik icon di Dock atau Finder
        if !flag {
            openDashboard()
        }
        return true
    }

    // MARK: - Helper Installation

    /// Cek apakah helper sudah ter-install, jika belum tampilkan onboarding
    private func checkAndInstallHelper() {
        let service = SMAppService.daemon(plistName: "com.ibrardev.BatteryGuard.Helper.plist")
        let status = service.status

        switch status {
        case .enabled:
            // Helper sudah running, tidak perlu apa-apa
            break
        case .requiresApproval:
            // User perlu approve di System Settings > Privacy & Security
            showHelperApprovalNotification()
        case .notFound:
            // Pertama kali install — tampilkan prompt
            // Tidak auto-install karena butuh user consent eksplisit
            break
        case .notRegistered:
            // Helper belum di-register
            break
        @unknown default:
            break
        }
    }

    private func showHelperApprovalNotification() {
        // TODO: Tampilkan banner atau buka Settings panel
        // Untuk sekarang, log saja
        print("[AppDelegate] Helper memerlukan approval di System Settings > Privacy & Security > Background Items")
    }

    // MARK: - System Notifications

    private func setupSystemNotifications() {
        // Monitor saat baterai sangat rendah via NSWorkspace notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handlePowerChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handlePowerChange(_ notification: Notification) {
        // Re-apply charge limit setelah wake dari sleep (jika aktif)
        // ViewModel akan handle ini via ChargeLimitManager
    }

    // MARK: - Window Management

    @objc func openDashboard() {
        // Buka dashboard window
        // SwiftUI Window group di-trigger via openWindow environment value
        // Dari AppDelegate, kita bisa trigger via NSApp
        for window in NSApp.windows {
            if window.identifier?.rawValue == "dashboard" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
    }
}
