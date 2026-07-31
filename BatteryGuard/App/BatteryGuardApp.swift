// BatteryGuardApp.swift
// BatteryGuard — App entry point
// NSStatusItem + popover dikelola oleh AppDelegate (AppKit)
// SwiftUI scenes hanya untuk Dashboard window dan Settings

import SwiftUI
import ServiceManagement

@main
struct BatteryGuardApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {

        // MARK: - Dashboard Window
        Window("BatteryGuard", id: "dashboard") {
            DashboardView()
                .environmentObject(appDelegate.viewModel)
                .environmentObject(appDelegate.prefs)
                .environmentObject(appDelegate.helperInstaller)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)

        // MARK: - Settings
        Settings {
            SettingsView()
                .environmentObject(appDelegate.prefs)
                .environmentObject(appDelegate.helperInstaller)
                .environmentObject(appDelegate.viewModel)
        }
    }
}
