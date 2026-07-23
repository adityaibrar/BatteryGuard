// SystemStatsViewModel.swift
// BatteryGuard — Aggregate ViewModel dari semua monitor
// Satu sumber data untuk seluruh UI (MenuBar + Dashboard)

import Foundation
import Combine

// MARK: - SystemStatsViewModel

/// @MainActor karena semua @Published harus di-update di main thread untuk SwiftUI
@MainActor
final class SystemStatsViewModel: ObservableObject {

    // MARK: - Battery

    /// Status baterai real-time
    @Published var batteryStatus: BatteryStatus = .placeholder
    @Published var batterySpecs: BatterySpecs = .empty
    @Published var batteryHealth: BatteryHealth = .empty
    @Published var adapterInfo: AdapterInfo = .disconnected
    @Published var powerFlow: PowerFlow = .empty

    // MARK: - System

    @Published var ramStats: RAMStats = .zero
    @Published var networkStats: NetworkStats = .zero
    @Published var temperatures: SystemTemperatures = .empty

    // MARK: - Charge Limit

    @Published var chargeLimitState: ChargeLimitState = .default
    @Published var isApplyingLimit: Bool = false
    @Published var chargeLimitError: String?

    // MARK: - Computed: Menu Bar

    /// Label persentase baterai untuk menu bar (misal "80%")
    var batteryPercentLabel: String { "\(batteryStatus.percentage)%" }

    /// SF Symbol icon berdasarkan status baterai
    var batteryIconName: String {
        let p = batteryStatus.percentage
        if batteryStatus.isCharging {
            return "battery.100.bolt"
        }
        switch p {
        case 80...100: return "battery.100"
        case 60...79:  return "battery.75"
        case 40...59:  return "battery.50"
        case 20...39:  return "battery.25"
        default:       return "battery.0"
        }
    }

    /// Warna icon baterai
    var batteryIconColor: Color {
        if chargeLimitState.isEnabled && batteryStatus.chargeLimitReached {
            return .orange
        }
        switch batteryStatus.percentage {
        case 20...: return .green
        case 10..<20: return .yellow
        default: return .red
        }
    }

    /// Format time remaining: "1h 23m" atau "Charging" atau "—"
    var timeRemainingLabel: String {
        guard let mins = powerFlow.timeRemainingMinutes else { return "—" }
        if mins < 0 { return batteryStatus.isCharging ? "Charging..." : "Calculating..." }
        let h = Int(mins) / 60
        let m = Int(mins) % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    // MARK: - Dependencies

    private let batteryMonitor: BatteryMonitor
    private let ramMonitor: RAMMonitor
    private let networkMonitor: NetworkSpeedMonitor
    private let tempMonitor: TemperatureMonitor
    let chargeLimitManager: ChargeLimitManager
    let prefs: PreferencesStore
    let cycleHistory: CycleHistoryStore

    // MARK: - Combine Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(
        batteryMonitor: BatteryMonitor = BatteryMonitor(),
        ramMonitor: RAMMonitor = RAMMonitor(),
        networkMonitor: NetworkSpeedMonitor = NetworkSpeedMonitor(),
        tempMonitor: TemperatureMonitor = TemperatureMonitor(),
        chargeLimitManager: ChargeLimitManager = ChargeLimitManager(),
        prefs: PreferencesStore = .shared,
        cycleHistory: CycleHistoryStore = .shared
    ) {
        self.batteryMonitor = batteryMonitor
        self.ramMonitor = ramMonitor
        self.networkMonitor = networkMonitor
        self.tempMonitor = tempMonitor
        self.chargeLimitManager = chargeLimitManager
        self.prefs = prefs
        self.cycleHistory = cycleHistory

        setupBindings()
    }

    // MARK: - Start All Monitors

    func startAll() {
        batteryMonitor.startMonitoring()
        ramMonitor.startMonitoring()
        networkMonitor.startMonitoring()

        // Temperature: selalu start — battery temp tersedia tanpa root via IOKit
        tempMonitor.startMonitoring()

        chargeLimitManager.verifyHelperConnection()
    }

    func stopAll() {
        batteryMonitor.stopMonitoring()
        ramMonitor.stopMonitoring()
        networkMonitor.stopMonitoring()
        tempMonitor.stopMonitoring()
    }

    // MARK: - Charge Limit Actions

    func setChargeLimit(_ percent: Int) {
        chargeLimitManager.setChargeLimit(percent)
        chargeLimitState = chargeLimitManager.state
    }

    func toggleChargeLimit() {
        chargeLimitManager.toggleEnabled()
        chargeLimitState = chargeLimitManager.state
    }

    // MARK: - Combine Bindings

    private func setupBindings() {
        // Battery status → update chargeLimitReached
        batteryMonitor.$status
            .sink { [weak self] status in
                guard let self = self else { return }
                var updatedStatus = status
                updatedStatus.chargeLimitReached = self.chargeLimitManager.checkLimitReached(
                    currentPercent: status.percentage
                )
                self.batteryStatus = updatedStatus

                // Auto-record cycle count saat ada update
                if let cycles = self.batteryHealth.cycleCount {
                    self.cycleHistory.recordCycleCount(cycles)
                }
            }
            .store(in: &cancellables)

        batteryMonitor.$specs
            .assign(to: &$batterySpecs)

        batteryMonitor.$health
            .assign(to: &$batteryHealth)

        batteryMonitor.$adapterInfo
            .assign(to: &$adapterInfo)

        batteryMonitor.$powerFlow
            .assign(to: &$powerFlow)

        // RAM
        ramMonitor.$ramStats
            .assign(to: &$ramStats)

        // Network
        networkMonitor.$networkStats
            .assign(to: &$networkStats)

        // Temperature
        tempMonitor.$temperatures
            .assign(to: &$temperatures)

        // Charge limit state
        chargeLimitManager.$state
            .assign(to: &$chargeLimitState)

        chargeLimitManager.$isApplying
            .assign(to: &$isApplyingLimit)

        chargeLimitManager.$lastError
            .assign(to: &$chargeLimitError)
    }
}

// MARK: - Color extension (avoid SwiftUI import di non-View layer)

import SwiftUI
extension Color {
    // Re-expose untuk ViewModel usage
}
