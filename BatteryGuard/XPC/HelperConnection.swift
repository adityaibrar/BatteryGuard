// HelperConnection.swift
// BatteryGuard — XPC Connection manager di Main App side
// Mengelola lifecycle NSXPCConnection ke BatteryGuardHelper

import Foundation
import ServiceManagement

// MARK: - Helper Connection Error

enum HelperConnectionError: LocalizedError {
    case helperNotInstalled
    case connectionFailed(String)
    case operationFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            return "BatteryGuard Helper belum ter-install. Buka Settings untuk install."
        case .connectionFailed(let msg):
            return "Gagal koneksi ke helper: \(msg)"
        case .operationFailed(let msg):
            return "Operasi gagal: \(msg)"
        case .timeout:
            return "Koneksi ke helper timeout."
        }
    }
}

// MARK: - Helper Installer

/// Mengelola status instalasi BatteryGuard Helper daemon.
///
/// Untuk dev build (ad-hoc signed), instalasi helper dilakukan via script:
///   sudo bash install_helper.sh
///
/// isInstalled dicek langsung via launchctl, bukan SMAppService
/// karena SMAppService membutuhkan sertifikat Apple Developer berbayar.
final class HelperInstaller: ObservableObject {

    @Published var installStatus: HelperInstallStatus = .checking
    @Published var lastError: Error?

    enum HelperInstallStatus {
        case checking
        case running       // launchctl: daemon aktif
        case notRunning    // launchctl: daemon tidak aktif / belum install
        case enabled       // SMAppService: registered (untuk signed build)

        var isRunning: Bool {
            self == .running || self == .enabled
        }
    }

    // Cek apakah daemon berjalan via launchctl print
    func checkStatus() {
        DispatchQueue.global(qos: .utility).async {
            let running = self.isDaemonRunning()
            DispatchQueue.main.async {
                self.installStatus = running ? .running : .notRunning
            }
        }
    }

    private func isDaemonRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/com.ibrardev.BatteryGuard.Helper"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Coba install via SMAppService (hanya works untuk signed build dengan Developer cert)
    /// Untuk dev build: user harus jalankan install_helper.sh
    func install() {
        let service = SMAppService.daemon(plistName: "com.ibrardev.BatteryGuard.Helper.plist")
        do {
            try service.register()
            NSLog("[HelperInstaller] SMAppService register success")
            DispatchQueue.main.async { self.installStatus = .running }
        } catch {
            NSLog("[HelperInstaller] SMAppService failed (expected for unsigned build): \(error)")
            // Tampilkan instruksi install manual
            DispatchQueue.main.async {
                self.lastError = NSError(
                    domain: "HelperInstaller",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Untuk mengaktifkan helper, jalankan perintah berikut di Terminal:\n\nsudo bash \"/Users/IbrarDev/Development/Projects/macos/BatteryGuard/install_helper.sh\""]
                )
            }
        }
    }

    func uninstall() {
        let script = "launchctl bootout system/com.ibrardev.BatteryGuard.Helper && rm -f /Library/LaunchDaemons/com.ibrardev.BatteryGuard.Helper.plist && rm -f /Library/PrivilegedHelperTools/com.ibrardev.BatteryGuard.Helper"
        let appleScript = """
        do shell script "\(script)" with administrator privileges
        """
        var err: NSDictionary?
        NSAppleScript(source: appleScript)?.executeAndReturnError(&err)
        DispatchQueue.main.async { self.installStatus = .notRunning }
    }

    var isInstalled: Bool {
        installStatus.isRunning
    }
}


// MARK: - XPC Connection Manager

/// Thread-safe wrapper untuk NSXPCConnection ke BatteryGuardHelper
final class HelperConnection {

    static let shared = HelperConnection()

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private init() {}

    // MARK: - Connection Management

    /// Dapatkan atau buat koneksi ke helper
    private func getConnection() throws -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let existing = connection {
            return existing
        }

        let newConnection = NSXPCConnection(machServiceName: "com.ibrardev.BatteryGuard.Helper")
        newConnection.remoteObjectInterface = makeBatteryGuardXPCInterface()

        // Handle koneksi yang putus
        newConnection.invalidationHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    /// Disconnect dari helper
    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Public API (async/await wrappers)

    /// Terapkan charge limit
    func applyChargeLimit(_ limit: Int) async throws {
        let conn = try getConnection()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: HelperConnectionError.connectionFailed(error.localizedDescription))
            }) as? BatteryGuardXPCProtocol else {
                continuation.resume(throwing: HelperConnectionError.connectionFailed("Cannot create proxy"))
                return
            }

            proxy.applyChargeLimit(limit) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.operationFailed(
                        errorMessage ?? "Unknown error"
                    ))
                }
            }
        }
    }

    /// Enable/disable discharge mode
    func setDischargeMode(_ enabled: Bool) async throws {
        let conn = try getConnection()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: HelperConnectionError.connectionFailed(error.localizedDescription))
            }) as? BatteryGuardXPCProtocol else {
                continuation.resume(throwing: HelperConnectionError.connectionFailed("Cannot create proxy"))
                return
            }

            proxy.setDischargeModeEnabled(enabled) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.operationFailed(
                        errorMessage ?? "Unknown error"
                    ))
                }
            }
        }
    }

    /// Disable charge limit
    func disableChargeLimit() async throws {
        let conn = try getConnection()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: HelperConnectionError.connectionFailed(error.localizedDescription))
            }) as? BatteryGuardXPCProtocol else {
                continuation.resume(throwing: HelperConnectionError.connectionFailed("Cannot create proxy"))
                return
            }

            proxy.disableChargeLimit { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.operationFailed(
                        errorMessage ?? "Unknown error"
                    ))
                }
            }
        }
    }

    /// Ambil versi helper
    func getHelperVersion() async throws -> String {
        let conn = try getConnection()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: HelperConnectionError.connectionFailed(error.localizedDescription))
            }) as? BatteryGuardXPCProtocol else {
                continuation.resume(throwing: HelperConnectionError.connectionFailed("Cannot create proxy"))
                return
            }

            proxy.getHelperVersion { version in
                continuation.resume(returning: version)
            }
        }
    }
}
