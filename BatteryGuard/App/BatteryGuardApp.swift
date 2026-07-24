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

/// Label di status bar (kiri dari popover)
/// Tampilkan icon + persentase, dengan mode compact/expanded
private struct MenuBarLabel: View {
    @ObservedObject var viewModel: SystemStatsViewModel
    @ObservedObject var prefs: PreferencesStore

    var body: some View {
        Text("↓ \(viewModel.networkStats.downloadFormatted)  ↑ \(viewModel.networkStats.uploadFormatted)")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            // Monospaced digit agar lebar teks stabil
            .monospacedDigit()
    }
}
