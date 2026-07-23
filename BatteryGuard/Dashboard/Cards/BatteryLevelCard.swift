// BatteryLevelCard.swift
// Card 4: Battery level real-time dengan area chart (Swift Charts)

import SwiftUI
import Charts

// MARK: - Battery Level History (simple in-memory buffer)

/// Buffer sederhana untuk chart — simpan max 60 titik (1 menit kalau polling 1 detik)
class BatteryLevelHistory: ObservableObject {
    struct DataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let percentage: Int
    }

    @Published var points: [DataPoint] = []
    private let maxPoints = 60

    func add(_ percentage: Int) {
        let point = DataPoint(timestamp: Date(), percentage: percentage)
        points.append(point)
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }
}

// MARK: - BatteryLevelCard

struct BatteryLevelCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @StateObject private var history = BatteryLevelHistory()

    var body: some View {
        DashboardCardView(title: "Battery Level", icon: "battery.100.bolt", accentColor: levelColor) {
            VStack(alignment: .leading, spacing: 12) {
                // Current percentage — large display
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.batteryStatus.percentage)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(levelColor)
                    Text("%")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Charging badge
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

                // Area Chart
                if history.points.count > 1 {
                    Chart(history.points) { point in
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Level", point.percentage)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [levelColor.opacity(0.4), levelColor.opacity(0.05)],
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
                    .chartXAxis(.hidden)
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
                    .frame(height: 80)
                    .animation(.easeInOut, value: history.points.count)
                } else {
                    // Placeholder chart
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 80)
                        .overlay(
                            Text("Collecting data...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
        .onReceive(viewModel.$batteryStatus) { status in
            history.add(status.percentage)
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
