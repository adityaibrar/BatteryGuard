// BatteryHealthCard.swift
// Card 2: Kesehatan baterai — menggunakan NominalChargeCapacity (= macOS System Information)

import SwiftUI

struct BatteryHealthCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var health: BatteryHealth { viewModel.batteryHealth }

    /// healthPercent sudah otomatis gunakan NominalChargeCapacity jika tersedia
    /// = NominalChargeCapacity / DesignCapacity × 100 (sama dengan System Information)
    private var primaryHealthPercent: Double? {
        health.healthPercent
    }

    var body: some View {
        DashboardCardView(title: "Battery Health", icon: "heart.fill", accentColor: healthColor) {
            VStack(spacing: 10) {
                // MARK: Health percentage — big number
                if let primaryPct = primaryHealthPercent {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", primaryPct))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(healthColor)
                        }

                        Spacer()

                        // Circular progress indicator
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: primaryPct / 100.0)
                                .stroke(healthColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: primaryPct)
                        }
                        .frame(width: 52, height: 52)
                    }
                }

                Divider()

                VStack(spacing: 6) {
                    // NominalChargeCapacity — nilai yang sama dengan macOS System Information
                    CardInfoRow(
                        label: "Max Capacity",
                        value: health.nominalChargeCapacity.map { "\($0) mAh" }
                            ?? health.maxCapacity.map { "\($0) mAh" }
                            ?? "—"
                    )
                    CardInfoRow(
                        label: "Design Capacity",
                        value: health.designCapacity.map { "\($0) mAh" } ?? "—"
                    )
                    CardInfoRow(
                        label: "Cycle Count",
                        value: health.cycleCount.map { "\($0)" } ?? "—",
                        isMonospaced: true
                    )
                    CardInfoRow(
                        label: "Condition",
                        value: health.condition ?? "—",
                        valueColor: conditionColor
                    )
                    // Raw capacity sebagai referensi (biasanya berbeda karena Apple calibration)
                    if let raw = health.maxCapacity,
                       let nominal = health.nominalChargeCapacity,
                       raw != nominal {
                        CardInfoRow(
                            label: "Raw Capacity",
                            value: "\(raw) mAh",
                            valueColor: .secondary
                        )
                    }
                }
            }
        }
    }

    private var healthColor: Color {
        guard let h = primaryHealthPercent else { return .secondary }
        switch h {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    private var conditionColor: Color {
        switch health.condition?.lowercased() {
        case "good": return .green
        case "fair": return .orange
        case "poor": return .red
        default: return .secondary
        }
    }
}
