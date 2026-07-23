// PowerConsumptionCard.swift
// Card 7: Power draw real-time + estimasi waktu tersisa

import SwiftUI

struct PowerConsumptionCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var body: some View {
        DashboardCardView(title: "Power Consumption", icon: "bolt.circle.fill", accentColor: .yellow) {
            VStack(alignment: .leading, spacing: 12) {
                // Power draw
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.powerFlow.instantWattage.map {
                        String(format: "%.1f", $0)
                    } ?? "--")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(wattageColor)
                    Text("W")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Direction indicator
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(
                            viewModel.batteryStatus.isCharging ? "Charging" : "Discharging",
                            systemImage: viewModel.batteryStatus.isCharging ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(viewModel.batteryStatus.isCharging ? .green : .orange)
                    }
                }

                Divider()

                VStack(spacing: 6) {
                    // Amperage
                    CardInfoRow(
                        label: "Current",
                        value: viewModel.powerFlow.amperage.map {
                            String(format: "%.3f A", abs($0))
                        } ?? "—",
                        isMonospaced: true
                    )

                    // Voltage
                    CardInfoRow(
                        label: "Voltage",
                        value: viewModel.powerFlow.voltage.map {
                            String(format: "%.2f V", $0)
                        } ?? "—",
                        isMonospaced: true
                    )

                    // Time remaining
                    CardInfoRow(
                        label: viewModel.batteryStatus.isCharging ? "Time to Full" : "Time Remaining",
                        value: viewModel.timeRemainingLabel,
                        valueColor: .secondary
                    )
                }
            }
        }
    }

    private var wattageColor: Color {
        guard let w = viewModel.powerFlow.instantWattage else { return .secondary }
        if viewModel.batteryStatus.isCharging { return .green }
        switch w {
        case ..<5: return .green
        case 5..<15: return .yellow
        default: return .orange
        }
    }
}
