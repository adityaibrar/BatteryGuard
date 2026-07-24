// SettingsView.swift
// BatteryGuard — Preferences panel (dibuka via Cmd+, atau gear icon)

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var prefs: PreferencesStore
    @EnvironmentObject var helperInstaller: HelperInstaller
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var body: some View {
        TabView {
            // MARK: General
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            // MARK: Menu Bar
            MenuBarSettingsTab()
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }

            // MARK: Helper
            HelperSettingsTab()
                .tabItem {
                    Label("Helper", systemImage: "wrench.and.screwdriver")
                }

            // MARK: About
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 480, height: 360)
        .environmentObject(prefs)
        .environmentObject(helperInstaller)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {
    @EnvironmentObject var prefs: PreferencesStore

    var body: some View {
        Form {
            Section("Charge Limiter") {
                Toggle("Enable Charge Limit on Launch", isOn: $prefs.isChargeLimitEnabled)
                HStack {
                    Text("Default Limit")
                    Spacer()
                    Stepper("\(prefs.chargeLimit)%", value: $prefs.chargeLimit, in: 20...100, step: 5)
                }
            }

            Section("Notifications") {
                Toggle("Notify when limit reached", isOn: $prefs.notifyOnLimitReached)
                Toggle("Notify on low battery", isOn: $prefs.notifyOnLowBattery)
                HStack {
                    Text("Low Battery Threshold")
                    Spacer()
                    Stepper("\(prefs.lowBatteryThreshold)%", value: $prefs.lowBatteryThreshold, in: 5...30, step: 5)
                }
            }

            Section("Heat Protection") {
                Toggle("Enable Heat Protection", isOn: $prefs.isHeatProtectionEnabled)
                HStack {
                    Text("Temperature Threshold")
                    Spacer()
                    Stepper(String(format: "%.0f°C", prefs.heatProtectionThreshold),
                            value: $prefs.heatProtectionThreshold,
                            in: 35...60, step: 1)
                }
                .disabled(!prefs.isHeatProtectionEnabled)
            }

            Section("Polling Intervals") {
                HStack {
                    Text("Battery Polling")
                    Spacer()
                    Picker("", selection: $prefs.batteryPollingInterval) {
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("5s").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                HStack {
                    Text("System (RAM/Network)")
                    Spacer()
                    Picker("", selection: $prefs.systemPollingInterval) {
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu Bar Settings Tab

private struct MenuBarSettingsTab: View {
    @EnvironmentObject var prefs: PreferencesStore

    var body: some View {
        Form {
            Section("Display Options") {
                Toggle("Show Battery Percentage", isOn: $prefs.showBatteryPercent)
                Toggle("Show Network Speed", isOn: $prefs.showNetworkSpeed)
                Toggle("Show RAM Usage", isOn: $prefs.showRAMUsage)
                Toggle("Show Temperature", isOn: $prefs.showTemperature)
                Toggle("Compact Mode", isOn: $prefs.isCompactMenuBar)
            }

            Section("Temperature Monitoring") {
                Toggle("Enable Temperature Monitoring", isOn: $prefs.temperatureMonitoringEnabled)
                Text("CPU temperature requires additional permissions. Battery temperature is always available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if prefs.temperatureMonitoringEnabled {
                    HStack {
                        Text("Polling Interval")
                        Spacer()
                        Picker("", selection: $prefs.tempPollingInterval) {
                            Text("3s").tag(3.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Helper Settings Tab

private struct HelperSettingsTab: View {
    @EnvironmentObject var helperInstaller: HelperInstaller

    var body: some View {
        Form {
            Section("Privileged Helper") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(statusColor)
                        .fontWeight(.medium)
                }

                HStack {
                    Button("Install / Update Helper") {
                        helperInstaller.install()
                    }
                    .disabled(helperInstaller.isInstalled)

                    Button("Uninstall Helper") {
                        helperInstaller.uninstall()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!helperInstaller.isInstalled)
                }

                Text("The helper tool runs as a privileged daemon to apply charge limits. It must be installed once and requires your approval in System Settings → Privacy & Security → Background Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = helperInstaller.lastError {
                Section("Last Error") {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            helperInstaller.checkStatus()
        }
    }

    private var statusText: String {
        switch helperInstaller.installStatus {
        case .checking: return "Memeriksa..."
        case .running: return "Aktif & Berjalan"
        case .enabled: return "Aktif & Berjalan"
        case .notRunning: return "Belum Terinstall"
        }
    }

    private var statusColor: Color {
        switch helperInstaller.installStatus {
        case .running, .enabled: return .green
        case .checking: return .secondary
        case .notRunning: return .red
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "battery.75.bolt")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("BatteryGuard")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version 1.0.0 (Fase 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Open source battery charge limiter\nfor Apple Silicon Macs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Text("Built with SwiftUI + IOKit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
