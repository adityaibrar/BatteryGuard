// CalibrationCard.swift
// Card 10: Kalibrasi baterai — last calibration + trigger tombol

import SwiftUI

struct CalibrationCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @EnvironmentObject var prefs: PreferencesStore
    @State private var showCalibrationConfirm = false

    var body: some View {
        DashboardCardView(title: "Calibration", icon: "dial.medium.fill", accentColor: .teal) {
            VStack(alignment: .leading, spacing: 12) {
                // Last calibration
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Calibration")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastDate = prefs.lastCalibrationDate {
                        Text(lastDate, style: .date)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)

                        Text(lastDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never calibrated")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // What is calibration?
                Text("Calibration helps macOS accurately estimate battery life by running a full charge → discharge → charge cycle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Start Calibration button
                Button {
                    showCalibrationConfirm = true
                } label: {
                    Label("Start Calibration", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
                .controlSize(.regular)
                .disabled(true) // Disabled sampai Fase 8 diimplementasikan

                Text("Calibration mode akan tersedia di Fase 8")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .alert("Start Calibration?", isPresented: $showCalibrationConfirm) {
            Button("Start", role: .destructive) {
                startCalibration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Calibration akan menguras baterai hingga habis, lalu mengisi penuh. Pastikan MacBook terhubung ke power sebelum memulai.")
        }
    }

    private func startCalibration() {
        // TODO: Implementasikan Calibration Mode (Fase 8)
        // - Disable charge limit sementara
        // - Monitor hingga baterai 100%
        // - Kemudian discharge mode hingga baterai ~5%
        // - Re-enable charging hingga 100%
        // - Update lastCalibrationDate
        prefs.lastCalibrationDate = Date()
    }
}
