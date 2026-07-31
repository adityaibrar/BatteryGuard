// BatteryGuardApp.swift
// BatteryGuard — App entry point

import SwiftUI
import ServiceManagement

@main
struct BatteryGuardApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Shared ViewModel di-inject via Environment ke seluruh app
    @StateObject private var viewModel = SystemStatsViewModel()
    @StateObject private var prefs = PreferencesStore.shared
    @StateObject private var helperInstaller = HelperInstaller()

    var body: some Scene {

        // MARK: - Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
                .environmentObject(prefs)
                .environmentObject(helperInstaller)
        } label: {
            MenuBarLabel(viewModel: viewModel, prefs: prefs)
        }
        .menuBarExtraStyle(.window)

        // MARK: - Dashboard Window
        Window("BatteryGuard", id: "dashboard") {
            DashboardView()
                .environmentObject(viewModel)
                .environmentObject(prefs)
                .environmentObject(helperInstaller)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)

        // MARK: - Settings
        Settings {
            SettingsView()
                .environmentObject(prefs)
                .environmentObject(helperInstaller)
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Menu Bar Label

/// Label di status bar (icon klik untuk buka popover)
/// Layout compact: [↑↓ speed] [GPU] [RAM] [CPU] [suhu]
/// Menyerupai iStat Menus style — dense & informative
private struct MenuBarLabel: View {
    @ObservedObject var viewModel: SystemStatsViewModel
    @ObservedObject var prefs: PreferencesStore

    var body: some View {
        HStack(spacing: 6) {

            // MARK: Network Speed (stacked 2 baris)
            if prefs.showNetworkSpeed {
                VStack(alignment: .trailing, spacing: 0) {
                    // Upload row
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.green)
                        Text(viewModel.networkStats.uploadFormatted)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                    // Download row
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(viewModel.networkStats.downloadFormatted)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }

            // MARK: GPU %
            if prefs.showGPUUsage {
                CompactMetricChip(
                    label: "GPU",
                    value: viewModel.gpuStats.shortFormatted,
                    color: gpuColor
                )
            }

            // MARK: RAM %
            if prefs.showRAMUsage {
                CompactMetricChip(
                    label: "RAM",
                    value: String(format: "%.0f%%", viewModel.ramStats.usagePercent),
                    color: ramColor
                )
            }

            // MARK: CPU %
            if prefs.showCPUUsage {
                CompactMetricChip(
                    label: "CPU",
                    value: viewModel.cpuStats.shortFormatted,
                    color: cpuColor
                )
            }

            // MARK: Suhu
            if prefs.showTemperature {
                let temp = viewModel.temperatures.cpuTemperature ?? viewModel.temperatures.batteryTemperature
                if let temp {
                    Text(temp.shortFormatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(tempColor(temp.celsius))
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Color Helpers

    private var gpuColor: Color {
        guard let usage = viewModel.gpuStats.usagePercent else { return .primary }
        switch usage {
        case ..<50: return .primary
        case 50..<80: return .orange
        default: return .red
        }
    }

    private var ramColor: Color {
        switch viewModel.ramStats.usagePercent {
        case ..<70: return .primary
        case 70..<85: return .orange
        default: return .red
        }
    }

    private var cpuColor: Color {
        switch viewModel.cpuStats.totalUsagePercent {
        case ..<50: return .primary
        case 50..<80: return .orange
        default: return .red
        }
    }

    private func tempColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return .primary
        case 60..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - CompactMetricChip

/// Chip kecil untuk satu metrik: [LABEL] [nilai]
/// Contoh: "GPU 44%", "RAM 61%", "CPU 17%"
private struct CompactMetricChip: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

