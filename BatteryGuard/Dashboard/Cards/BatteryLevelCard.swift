// BatteryLevelCard.swift
// Card 4: Battery level real-time dengan area chart 24 jam (Swift Charts)

import SwiftUI
import Charts

// MARK: - BatteryLevelCard

struct BatteryLevelCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    /// Gunakan LevelHistoryStore.shared sebagai sumber data persisten
    @ObservedObject private var store = LevelHistoryStore.shared

    var body: some View {
        DashboardCardView(title: "Battery Level", icon: "battery.100.bolt", accentColor: levelColor) {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: Current percentage — large display
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.batteryStatus.percentage)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(levelColor)
                    Text("%")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Status badge
                    if viewModel.batteryStatus.isCharging {
                        Label("Charging", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green)
                            .clipShape(Capsule())
                    } else if viewModel.batteryStatus.isPluggedIn {
                        Label("Plugged In", systemImage: "powerplug")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: 24-hour Area Chart
                let chartPoints = store.points
                if chartPoints.count > 1 {
                    Chart(chartPoints) { point in
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Level", point.percentage)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [levelColor.opacity(0.4), levelColor.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Level", point.percentage)
                        )
                        .foregroundStyle(levelColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.secondary.opacity(0.2))
                            AxisValueLabel(format: .dateTime.hour())
                                .foregroundStyle(Color.secondary)
                                .font(.system(size: 9))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)%")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 90)
                    .animation(.easeInOut, value: chartPoints.count)

                    // Range label
                    HStack {
                        Text("Last 24 hours")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(chartPoints.count) data points")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Placeholder: belum ada cukup data
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 90)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("Collecting data... (updates every 5 min)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        )
                }
            }
        }
        // Record setiap kali batteryStatus berubah — store handle dedup 5-menit sendiri
        .onReceive(viewModel.$batteryStatus) { status in
            store.record(status.percentage)
        }
    }

    private var levelColor: Color {
        switch viewModel.batteryStatus.percentage {
        case 20...: return .green
        case 10..<20: return .yellow
        default: return .red
        }
    }
}
