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

/// Mengelola instalasi Privileged Helper via SMAppService (macOS 13+)
final class HelperInstaller: ObservableObject {

    @Published var installStatus: SMAppService.Status = .notRegistered
    @Published var lastError: Error?

    private let service = SMAppService.daemon(plistName: "com.ibrardev.BatteryGuard.Helper.plist")

    func checkStatus() {
        installStatus = service.status
    }

    func install() {
        do {
            try service.register()
            installStatus = service.status
        } catch {
            lastError = error
            installStatus = service.status
        }
    }

    func uninstall() {
        Task {
            do {
                try await service.unregister()
                await MainActor.run { installStatus = service.status }
            } catch {
                await MainActor.run { lastError = error }
            }
        }
    }

    var isInstalled: Bool {
        installStatus == .enabled
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
