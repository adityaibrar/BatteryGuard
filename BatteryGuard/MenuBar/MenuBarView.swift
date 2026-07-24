// MenuBarView.swift
// BatteryGuard — Konten popover MenuBarExtra
// Tampil saat user klik icon di status bar

import SwiftUI

// MARK: - MenuBarView

struct MenuBarView: View {

    @EnvironmentObject var viewModel: SystemStatsViewModel
    @EnvironmentObject var prefs: PreferencesStore
    @EnvironmentObject var helperInstaller: HelperInstaller
    @Environment(\.openWindow) private var openWindow

    /// Nilai sementara slider — bebas per-1%, XPC hanya dipanggil saat drag selesai (onEditingChanged)
    @State private var tempLimit: Double = 80

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header — Metrics Strip
            metricsStrip
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // MARK: Battery Status
            batterySection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // MARK: Charge Control
            chargeControlSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // MARK: Helper Status (jika ada error)
            if let error = viewModel.chargeLimitError {
                Divider()
                helperErrorBanner(error)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Divider()

            // MARK: Footer Actions
            footerActions
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .onAppear {
            // Sync tempLimit saat popover dibuka
            tempLimit = Double(viewModel.chargeLimitState.limitPercent)
        }
        .onChange(of: viewModel.chargeLimitState.limitPercent) { newVal in
            // Sync jika limit berubah dari luar (misal Settings)
            tempLimit = Double(newVal)
        }
    } // end body

    // MARK: - Metrics Strip

    private var metricsStrip: some View {
        HStack(spacing: 8) {
            // Battery %
            StatusBarMetricView(
                icon: viewModel.batteryIconName,
                value: "\(viewModel.batteryStatus.percentage)",
                unit: "%",
                color: batteryColor
            )

            if prefs.showNetworkSpeed {
                Divider().frame(height: 16)
                NetworkSpeedMetricView(
                    downloadFormatted: viewModel.networkStats.downloadFormatted,
                    uploadFormatted: viewModel.networkStats.uploadFormatted,
                    isCompact: prefs.isCompactMenuBar
                )
            }

            if prefs.showTemperature && viewModel.temperatures.cpuTemperature != nil {
                Divider().frame(height: 16)
                StatusBarMetricView(
                    icon: "thermometer.medium",
                    value: viewModel.temperatures.cpuTempFormatted,
                    unit: "",
                    color: tempColor
                )
            }

            if prefs.showRAMUsage {
                Divider().frame(height: 16)
                StatusBarMetricView(
                    icon: "memorychip",
                    value: String(format: "%.0f%%", viewModel.ramStats.usagePercent),
                    unit: "",
                    color: ramColor
                )
            }

            Spacer()
        }
    }

    // MARK: - Battery Section

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Status row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(batteryStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Large percentage display
                Text("\(viewModel.batteryStatus.percentage)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(batteryColor)
            }

            // Battery level bar
            BatteryProgressBar(
                percentage: viewModel.batteryStatus.percentage,
                limit: viewModel.chargeLimitState.isEnabled ? viewModel.chargeLimitState.limitPercent : nil,
                isCharging: viewModel.batteryStatus.isCharging
            )
            .frame(height: 8)

            // Time remaining
            if let mins = viewModel.powerFlow.timeRemainingMinutes, mins > 0 {
                HStack {
                    Image(systemName: viewModel.batteryStatus.isCharging ? "bolt.fill" : "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.timeRemainingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                    // Power draw
                    if let watt = viewModel.powerFlow.instantWattage {
                        Text(String(format: "%.1f W", watt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Charge Control Section

    private var chargeControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header dengan toggle
            HStack {
                Label("Charge Limit", systemImage: "bolt.badge.clock")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.chargeLimitState.isEnabled },
                    set: { _ in viewModel.toggleChargeLimit() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Slider
            if viewModel.chargeLimitState.isEnabled {
                VStack(spacing: 6) {
                    HStack {
                        Text("Limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(tempLimit))%")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.chargeLimitState.isEnabled ? .primary : .secondary)
                            .contentTransition(.numericText())
                    }

                    Slider(
                        value: $tempLimit,
                        in: 20...100
                    ) { _ in
                        viewModel.setChargeLimit(Int(tempLimit))
                    }
                    .disabled(!viewModel.chargeLimitState.isEnabled)
                    .tint(sliderColor)

                    // Range hint
                    HStack {
                        Text("20%")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Recommended: 80%")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("100%")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Applying indicator
            if viewModel.isApplyingLimit {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Applying...").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Error Banner

    private func helperErrorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack {
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed Colors & Text

    private var batteryColor: Color {
        if viewModel.chargeLimitState.isEnabled && viewModel.batteryStatus.chargeLimitReached {
            return .orange
        }
        switch viewModel.batteryStatus.percentage {
        case 20...: return .green
        case 10..<20: return .yellow
        default: return .red
        }
    }

    private var sliderColor: Color {
        switch Int(tempLimit) {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    private var tempColor: Color {
        guard let temp = viewModel.temperatures.cpuTemperature?.celsius else { return .primary }
        switch temp {
        case ..<60: return .green
        case 60..<80: return .orange
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

    private var batteryStatusText: String {
        if viewModel.chargeLimitState.isEnabled && viewModel.batteryStatus.chargeLimitReached {
            return "Limit reached (\(viewModel.chargeLimitState.limitPercent)%)"
        }
        if viewModel.batteryStatus.isCharging {
            return "Charging\(viewModel.adapterInfo.wattage.map { " · \(Int($0))W" } ?? "")"
        }
        if viewModel.batteryStatus.isPluggedIn {
            return "Plugged in, not charging"
        }
        return "On Battery"
    }
}

// MARK: - Battery Progress Bar

struct BatteryProgressBar: View {
    let percentage: Int
    let limit: Int?
    let isCharging: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: geo.size.width * CGFloat(percentage) / 100, height: 8)
                    .animation(.easeInOut(duration: 0.5), value: percentage)

                // Limit indicator
                if let limit = limit {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 2, height: 12)
                        .offset(x: geo.size.width * CGFloat(limit) / 100 - 1, y: -2)
                }
            }
        }
    }

    private var fillColor: Color {
        if isCharging { return .green }
        switch percentage {
        case 20...: return .green
        case 10..<20: return .yellow
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview("Menu Bar Popover") {
    MenuBarView()
        .environmentObject(SystemStatsViewModel())
        .environmentObject(PreferencesStore.shared)
        .environmentObject(HelperInstaller())
}
