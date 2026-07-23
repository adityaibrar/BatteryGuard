// ChargeLimitManager.swift
// BatteryGuard — State management untuk charge limit + komunikasi ke helper

import Foundation
import Combine

// MARK: - ChargeLimitManager

/// Mengelola state charge limit dan berkomunikasi dengan HelperTool via XPC
final class ChargeLimitManager: ObservableObject {

    // MARK: - Published State

    @Published var state: ChargeLimitState = .default
    @Published var isApplying: Bool = false
    @Published var lastError: String?
    @Published var helperVersion: String?

    // MARK: - Dependencies

    private let connection: HelperConnection
    private let prefs: PreferencesStore

    // MARK: - Init

    init(
        connection: HelperConnection = .shared,
        prefs: PreferencesStore = .shared
    ) {
        self.connection = connection
        self.prefs = prefs

        // Load state dari preferences
        state = ChargeLimitState(
            limitPercent: prefs.chargeLimit,
            isEnabled: prefs.isChargeLimitEnabled,
            dischargeModeEnabled: prefs.isDischargeModeEnabled
        )
    }

    // MARK: - Set Charge Limit

    /// Set limit charging (20-100%) dan apply ke helper
    func setChargeLimit(_ percent: Int) {
        let clamped = max(20, min(100, percent))
        state.limitPercent = clamped
        prefs.chargeLimit = clamped

        if state.isEnabled {
            applyCurrentState()
        }
    }

    // MARK: - Toggle Enable

    /// Enable/disable charge limiter
    func toggleEnabled() {
        state.isEnabled.toggle()
        prefs.isChargeLimitEnabled = state.isEnabled

        if state.isEnabled {
            applyCurrentState()
        } else {
            disableLimit()
        }
    }

    func setEnabled(_ enabled: Bool) {
        state.isEnabled = enabled
        prefs.isChargeLimitEnabled = enabled

        if enabled {
            applyCurrentState()
        } else {
            disableLimit()
        }
    }

    // MARK: - Discharge Mode

    /// Toggle discharge mode
    func toggleDischargeMode() {
        state.dischargeModeEnabled.toggle()
        prefs.isDischargeModeEnabled = state.dischargeModeEnabled
        applyDischargeMode()
    }

    // MARK: - Update from BatteryMonitor

    /// Di-panggil oleh SystemStatsViewModel saat battery status berubah
    /// Cek apakah baterai sudah mencapai limit
    func checkLimitReached(currentPercent: Int) -> Bool {
        guard state.isEnabled else { return false }
        return currentPercent >= state.limitPercent
    }

    // MARK: - Verify Helper Connection

    func verifyHelperConnection() {
        Task {
            do {
                let version = try await connection.getHelperVersion()
                helperVersion = version
                lastError = nil
            } catch {
                helperVersion = nil
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Private

    private func applyCurrentState() {
        Task {
            isApplying = true
            defer { isApplying = false }

            do {
                try await connection.applyChargeLimit(state.limitPercent)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func disableLimit() {
        Task {
            isApplying = true
            defer { isApplying = false }

            do {
                try await connection.disableChargeLimit()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func applyDischargeMode() {
        Task {
            do {
                try await connection.setDischargeMode(state.dischargeModeEnabled)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
