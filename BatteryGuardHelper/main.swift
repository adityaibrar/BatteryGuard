// main.swift
// BatteryGuardHelper — Entry point privileged daemon
//
// Daemon ini berjalan sebagai root, dikelola oleh launchd via SMAppService.
// Tugas utama: menjadi XPC listener untuk menerima perintah dari Main App.

import Foundation

// MARK: - XPC Listener Delegate

/// Menerima dan memvalidasi koneksi XPC dari Main App
final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Validasi koneksi yang masuk — hanya terima dari bundle ID yang dikenal
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        NSLog("[Helper] Koneksi XPC baru diterima (PID: %d)", connection.processIdentifier)

        // Konfigurasi interface yang diekspor ke client (Main App)
        connection.exportedInterface = makeBatteryGuardXPCInterface()
        connection.exportedObject    = HelperTool()

        // Handler saat koneksi putus (normal saat Main App quit)
        connection.invalidationHandler = {
            NSLog("[Helper] Koneksi XPC diputus (invalidated)")
        }
        connection.interruptionHandler = {
            NSLog("[Helper] Koneksi XPC terinterupsi (interrupted)")
        }

        connection.resume()
        NSLog("[Helper] ✅ Koneksi XPC diterima dan aktif")
        return true
    }
}

// MARK: - Main Run Loop

NSLog("[Helper] BatteryGuardHelper v%@ dimulai (PID: %d)",
      HelperTool.version, ProcessInfo.processInfo.processIdentifier)

let delegate = HelperDelegate()
// Gunakan Mach service name yang sama seperti yang didaftarkan di launchd plist
let listener = NSXPCListener(machServiceName: "com.ibrardev.Ozone.Helper")
listener.delegate = delegate

// Resume listener dan masuk ke run loop — daemon harus terus berjalan
listener.resume()
NSLog("[Helper] XPC Listener aktif, menunggu koneksi...")
RunLoop.main.run()
