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

/// Label di status bar — single-row compact layout
/// Format: [↑upload ↓download] [GPU xx%] [RAM xx%] [CPU xx%] [xx°]
private struct MenuBarLabel: View {
    @ObservedObject var viewModel: SystemStatsViewModel
    @ObservedObject var prefs: PreferencesStore

    var body: some View {
        HStack(spacing: 5) {

            // MARK: Network Speed — 2 baris stacked, font sangat kecil
            if prefs.showNetworkSpeed {
                VStack(alignment: .leading, spacing: -1) {
                    // Upload
                    HStack(spacing: 1) {
                        Text("↑")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.green)
                        Text(compactSpeed(viewModel.networkStats.uploadBytesPerSec))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                    // Download
                    HStack(spacing: 1) {
                        Text("↓")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(compactSpeed(viewModel.networkStats.downloadBytesPerSec))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(height: 22)
            }

            // MARK: GPU %
            if prefs.showGPUUsage {
                MetricLabel(
                    label: "GPU",
                    value: viewModel.gpuStats.shortFormatted,
                    color: gpuColor
                )
            }

            // MARK: RAM %
            if prefs.showRAMUsage {
                MetricLabel(
                    label: "RAM",
                    value: String(format: "%.0f%%", viewModel.ramStats.usagePercent),
                    color: ramColor
                )
            }

            // MARK: CPU %
            if prefs.showCPUUsage {
                MetricLabel(
                    label: "CPU",
                    value: viewModel.cpuStats.shortFormatted,
                    color: cpuColor
                )
            }

            // MARK: Suhu
            if prefs.showTemperature {
                let temp = viewModel.temperatures.cpuTemperature
                    ?? viewModel.temperatures.batteryTemperature
                if let temp {
                    Text(temp.shortFormatted)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tempColor(temp.celsius))
                        .monospacedDigit()
                }
            }
        }
        // Pastikan HStack tidak di-clip oleh menu bar
        .fixedSize()
    }

    // MARK: - Format Helpers

    /// Format kecepatan compact: "352K", "1.2M", "0" — tanpa satuan panjang
    private func compactSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0fK", bytesPerSec / 1_000)
        } else if bytesPerSec > 0 {
            return String(format: "%.0fB", bytesPerSec)
        }
        return "0K"
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

// MARK: - MetricLabel

/// Label metrik: [NAMA kecil abu] [nilai putih bold]
/// Contoh: "GPU 44%", "RAM 61%", "CPU 17%"
private struct MetricLabel: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}


