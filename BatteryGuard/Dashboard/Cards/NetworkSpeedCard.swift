// NetworkSpeedCard.swift
// Card: Upload/Download speed real-time — sama dengan Activity Monitor

import SwiftUI
import Charts

// MARK: - NetworkSpeedCard

struct NetworkSpeedCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    /// Buffer chart sederhana in-memory (1 menit, 60 titik)
    @StateObject private var history = NetworkSpeedHistory()

    var body: some View {
        DashboardCardView(
            title: "Network",
            icon: "network",
            accentColor: .cyan
        ) {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: Download + Upload current speed
                HStack(spacing: 16) {
                    // Download
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text("Download")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.networkStats.downloadFormatted)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                            .contentTransition(.numericText())
                    }

                    Divider().frame(height: 32)

                    // Upload
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Upload")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.networkStats.uploadFormatted)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                    }

                    Spacer()
                }

                // MARK: Sparkline chart (1 menit terakhir)
                if history.downloadPoints.count > 1 {
                    Chart {
                        // Download (Positive Y)
                        ForEach(history.downloadPoints) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.value)
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [.blue.opacity(0.4), .blue.opacity(0.01)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.value)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        
                        // Upload (Negative Y)
                        ForEach(history.uploadPoints) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", -point.value) // Negative for mirror effect
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [.green.opacity(0.01), .green.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            ))

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", -point.value) // Negative for mirror effect
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: true))
                    .frame(height: 50)
                    .animation(.easeInOut(duration: 0.3), value: history.downloadPoints.count)

                    // Legend
                    HStack(spacing: 12) {
                        Label("↓ Download", systemImage: "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                        Label("↑ Upload", systemImage: "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Last 60s")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 50)
                        .overlay(
                            Text("Collecting data...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        )
                }

                Divider()

                // MARK: Interface info
                CardInfoRow(
                    label: "Interface",
                    value: viewModel.networkStats.primaryInterface == "—"
                        ? "No activity"
                        : viewModel.networkStats.primaryInterface
                )
            }
        }
        .onReceive(viewModel.$networkStats) { stats in
            history.add(
                download: stats.downloadBytesPerSec,
                upload: stats.uploadBytesPerSec
            )
        }
    }
}

// MARK: - NetworkSpeedHistory

/// Buffer in-memory 60 detik untuk sparkline chart
private class NetworkSpeedHistory: ObservableObject {
    struct Point: Identifiable {
        let id = UUID()
        let timestamp: Date
        let value: Double // bytes per second
    }

    @Published var downloadPoints: [Point] = []
    @Published var uploadPoints: [Point] = []
    private let maxPoints = 60

    func add(download: Double, upload: Double) {
        let now = Date()
        downloadPoints.append(Point(timestamp: now, value: download))
        uploadPoints.append(Point(timestamp: now, value: upload))
        if downloadPoints.count > maxPoints { downloadPoints.removeFirst() }
        if uploadPoints.count > maxPoints  { uploadPoints.removeFirst() }
    }
}
