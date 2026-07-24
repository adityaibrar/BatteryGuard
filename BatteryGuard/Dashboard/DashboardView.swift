// DashboardView.swift
// BatteryGuard — Root dashboard window dengan NavigationSplitView + LazyVGrid

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @EnvironmentObject var prefs: PreferencesStore
    @EnvironmentObject var helperInstaller: HelperInstaller

    @State private var sidebarSelection: DashboardSection? = .dashboard

    // Adaptive grid: 2 kolom, minimal 300pt
    private let gridColumns = [
        GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)
    ]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            detailContent
                .navigationTitle(sidebarSelection?.rawValue ?? "Dashboard")
                .toolbar {
                    toolbarContent
                }
        }
        .onAppear {
            viewModel.startAll()
            helperInstaller.checkStatus()
        }
        .onDisappear {
            // Jangan stop monitors saat dashboard ditutup — tetap jalan di background
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch sidebarSelection {
        case .dashboard, .none:
            mainDashboardGrid
        case .chargeControl:
            chargeControlView
        case .sleepBehavior:
            placeholderView("Sleep Behavior", icon: "moon.zzz", description: "Konfigurasi sleep behavior — akan diimplementasikan di fase berikutnya.")
        case .energyUse:
            EnergyAppsCard()
                .padding()
                .frame(maxWidth: 500)
        case .schedule:
            placeholderView("Schedule", icon: "calendar.badge.clock", description: "Schedule charging — akan diimplementasikan di Fase 6.")
        case .shortcuts:
            placeholderView("Shortcuts", icon: "keyboard", description: "Keyboard shortcuts — akan diimplementasikan di fase berikutnya.")
        case .appearance:
            placeholderView("Appearance", icon: "paintpalette", description: "Tema dan tampilan — akan diimplementasikan di fase berikutnya.")
        }
    }

    // MARK: - Main Dashboard Grid (10 Cards)

    private var mainDashboardGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                BatterySpecsCard()
                BatteryHealthCard()
                PowerAdapterCard()
                BatteryLevelCard()
                BatteryCyclesCard()
                BatteryTemperatureCard()
                PowerConsumptionCard()
                PowerFlowCard()
                NetworkSpeedCard()
                EnergyAppsCard()
                CalibrationCard()
            }
            .padding(20)
        }
    }

    // MARK: - Charge Control View

    private var chargeControlView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Helper status banner
                if !helperInstaller.isInstalled {
                    HelperInstallBanner()
                        .environmentObject(helperInstaller)
                }

                // Charge limit control
                VStack(alignment: .leading, spacing: 16) {
                    Text("Charge Limit")
                        .font(.title2)
                        .fontWeight(.semibold)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Enable Charge Limit", isOn: Binding(
                                get: { viewModel.chargeLimitState.isEnabled },
                                set: { _ in viewModel.toggleChargeLimit() }
                            ))
                            .toggleStyle(.switch)

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Limit: \(viewModel.chargeLimitState.limitPercent)%")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("Recommended: 80%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.chargeLimitState.limitPercent) },
                                        set: { viewModel.setChargeLimit(Int($0)) }
                                    ),
                                    in: 20...100,
                                    step: 5
                                )
                                .disabled(!viewModel.chargeLimitState.isEnabled)

                                HStack {
                                    Text("20%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("100%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(4)
                    }

                    // Error display
                    if let error = viewModel.chargeLimitError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Placeholder View

    private func placeholderView(_ title: String, icon: String, description: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                // Refresh all monitors
                viewModel.startAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }

        ToolbarItem(placement: .automatic) {
            if viewModel.isApplyingLimit {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Helper Install Banner

struct HelperInstallBanner: View {
    @EnvironmentObject var helperInstaller: HelperInstaller
    @State private var showCopied = false

    private let installCommand = "sudo bash \"/Users/IbrarDev/Development/Projects/macos/BatteryGuard/install_helper.sh\""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Helper Belum Aktif")
                        .fontWeight(.semibold)
                    Text("Charge limiting memerlukan BatteryGuard Helper (daemon) yang berjalan sebagai root.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Cara Install (sekali saja):")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopied = false
                        }
                    } label: {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(showCopied ? .green : .secondary)
                }

                Text("1. Salin perintah di atas\n2. Buka Terminal (Cmd+Space → ketik Terminal)\n3. Paste dan tekan Enter\n4. Masukkan password Mac Anda\n5. Setelah selesai, klik tombol Refresh di bawah")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Buka Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                .buttonStyle(.bordered)

                Button("Refresh Status") {
                    helperInstaller.checkStatus()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

