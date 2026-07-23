// BatteryHealthCard.swift
// Card 2: Kesehatan baterai — capacity, cycle count, condition

import SwiftUI

struct BatteryHealthCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var health: BatteryHealth { viewModel.batteryHealth }

    var body: some View {
        DashboardCardView(title: "Battery Health", icon: "heart.fill", accentColor: healthColor) {
            VStack(spacing: 10) {
                // Health percentage — big number
                if let healthPercent = health.healthPercent {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", healthPercent))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(healthColor)
                        }

                        Spacer()

                        // Circular progress indicator
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: healthPercent / 100.0)
                                .stroke(healthColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: healthPercent)
                        }
                        .frame(width: 52, height: 52)
                    }
                }

                Divider()

                VStack(spacing: 6) {
                    CardInfoRow(
                        label: "Max Capacity",
                        value: health.maxCapacity.map { "\($0) mAh" } ?? "—"
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
                    if let maxPct = health.maxCapacityPercent {
                        CardInfoRow(
                            label: "macOS Assessment",
                            value: "\(maxPct)% Max Capacity",
                            valueColor: maxPct >= 80 ? .green : .orange
                        )
                    }
                }
            }
        }
    }

    private var healthColor: Color {
        guard let h = health.healthPercent else { return .secondary }
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
