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
            HStack(spacing: 16) {
                // MARK: Sparkline chart (Left)
                if history.downloadPoints.count > 1 {
                    let now = history.downloadPoints.last?.timestamp ?? Date()
                    let startDate = now.addingTimeInterval(-60)
                    
                    Chart {
                        // Download (Cyan, Area + Line)
                        ForEach(history.downloadPoints) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.value)
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [.cyan.opacity(0.4), .cyan.opacity(0.01)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.value)
                            )
                            .foregroundStyle(.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        
                        // Upload (Red, Area + Line, inverted)
                        ForEach(history.uploadPoints) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", -point.value)
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [.red.opacity(0.01), .red.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            ))

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", -point.value)
                            )
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartXScale(domain: startDate...now)
                    // Let Y-Scale be automatic so it symmetric or accommodates the max/min
                    .chartYScale(domain: .automatic)
                    .frame(height: 70)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 70)
                        .overlay(
                            Text("Collecting data...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        )
                }

                Divider()
                    .frame(height: 70)

                // MARK: Right Panel (Stats)
                VStack(spacing: 8) {
                    HStack {
                        Text("Interface:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.networkStats.primaryInterface == "—" ? "None" : viewModel.networkStats.primaryInterface)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Data received/sec:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.networkStats.downloadFormatted)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Data sent/sec:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.networkStats.uploadFormatted)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
                .frame(width: 190) // Fixed width to align nicely like a table
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
