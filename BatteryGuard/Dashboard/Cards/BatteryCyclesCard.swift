// BatteryCyclesCard.swift
// Card 5: Histori cycle count dari JSON persistence + line chart

import SwiftUI
import Charts

struct BatteryCyclesCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    /// Ambil histori 90 hari
    private var history: [CycleCountEntry] {
        CycleHistoryStore.shared.historyForLast(90)
    }

    var body: some View {
        DashboardCardView(title: "Battery Cycles", icon: "arrow.trianglehead.2.clockwise", accentColor: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                // Current cycle count
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.batteryHealth.cycleCount.map { "\($0)" } ?? "—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                    Text("cycles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Last 90 days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Line Chart
                if history.count > 1 {
                    Chart(history) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Cycles", entry.cycleCount)
                        )
                        .foregroundStyle(.purple)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .symbol(Circle().strokeBorder(lineWidth: 1))
                        .symbolSize(20)

                        AreaMark(
                            x: .value("Date", entry.date),
                            y: .value("Cycles", entry.cycleCount)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple.opacity(0.25), .purple.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 30)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                            AxisValueLabel()
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 80)
                } else {
                    // Not enough data
                    VStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("History builds over time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Check back tomorrow for your first data point")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                }
            }
        }
    }
}
