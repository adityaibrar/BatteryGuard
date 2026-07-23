// EnergyAppsCard.swift
// Card 9: Aplikasi yang menggunakan energi signifikan
// Data dari NSWorkspace — untuk data lebih akurat butuh powermetrics (sudo)

import SwiftUI
import AppKit

// MARK: - App Energy Info

struct AppEnergyInfo: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let icon: NSImage?
    let energyImpact: String // "High", "Medium", "Low" atau nilai numerik jika tersedia
}

// MARK: - EnergyAppsCard

struct EnergyAppsCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @State private var energyApps: [AppEnergyInfo] = []
    @State private var isLoading = true

    var body: some View {
        DashboardCardView(
            title: "Energy Use",
            icon: "bolt.fill",
            accentColor: .orange,
            isLoading: isLoading
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if energyApps.isEmpty && !isLoading {
                    // Empty state
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "bolt.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No significant energy users")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    // App list
                    ForEach(energyApps.prefix(5)) { app in
                        AppEnergyRow(app: app)
                        if app.id != energyApps.prefix(5).last?.id {
                            Divider()
                        }
                    }

                    // Disclaimer
                    Text("Source: NSWorkspace running apps. Enable powermetrics in Settings for accurate data.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
        .task {
            await loadEnergyData()
        }
    }

    /// Ambil running apps dari NSWorkspace
    /// Ini adalah data yang tersedia tanpa privilege tambahan
    private func loadEnergyData() async {
        isLoading = true
        defer { isLoading = false }

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.isActive != false }
            .prefix(10)
            .map { app -> AppEnergyInfo in
                AppEnergyInfo(
                    name: app.localizedName ?? "Unknown",
                    bundleID: app.bundleIdentifier ?? "",
                    icon: app.icon,
                    energyImpact: "—" // Butuh powermetrics untuk nilai actual
                )
            }

        energyApps = Array(apps)
    }
}

// MARK: - App Energy Row

struct AppEnergyRow: View {
    let app: AppEnergyInfo

    var body: some View {
        HStack(spacing: 8) {
            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "app")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }

            // App name
            Text(app.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            // Energy impact
            Text(app.energyImpact)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
