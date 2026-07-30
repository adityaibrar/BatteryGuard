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
                // MARK: Sparkline chart (Left) - Dua chart terpisah
                VStack(spacing: 2) {
                    if history.downloadPoints.count > 1 {
                        let now = history.downloadPoints.last?.timestamp ?? Date()
                        let startDate = history.downloadPoints.first?.timestamp ?? now.addingTimeInterval(-60)
                        let maxDownload = history.downloadPoints.map(\.value).max() ?? 1

                        // --- Chart Download (Atas, Cyan/Biru) ---
                        ZStack(alignment: .topLeading) {
                            Chart {
                                ForEach(history.downloadPoints) { point in
                                    AreaMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Download", point.value)
                                    )
                                    .foregroundStyle(LinearGradient(
                                        colors: [.cyan.opacity(0.5), .cyan.opacity(0.05)],
                                        startPoint: .top, endPoint: .bottom
                                    ))

                                    LineMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Download", point.value)
                                    )
                                    .foregroundStyle(.cyan)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .chartXScale(domain: startDate...now)
                            .chartYScale(domain: 0...(maxDownload * 1.2))
                            .frame(height: 50)

                            Text("↓")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.cyan.opacity(0.8))
                                .padding([.top, .leading], 3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)

                        // Garis pemisah tipis di tengah
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)

                        // --- Chart Upload (Bawah, Merah) ---
                        let maxUpload = history.uploadPoints.map(\.value).max() ?? 1

                        ZStack(alignment: .bottomLeading) {
                            Chart {
                                ForEach(history.uploadPoints) { point in
                                    AreaMark(
                                        x: .value("Time", point.timestamp),
                                        yStart: .value("Base", maxUpload * 1.2),
                                        yEnd: .value("Upload", maxUpload * 1.2 - point.value)
                                    )
                                    .foregroundStyle(LinearGradient(
                                        colors: [.red.opacity(0.05), .red.opacity(0.5)],
                                        startPoint: .top, endPoint: .bottom
                                    ))

                                    LineMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Upload", maxUpload * 1.2 - point.value)
                                    )
                                    .foregroundStyle(.red)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .chartXScale(domain: startDate...now)
                            .chartYScale(domain: 0...(maxUpload * 1.2))
                            .frame(height: 50)

                            Text("↑")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red.opacity(0.8))
                                .padding([.bottom, .leading], 3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(maxWidth: .infinity, minHeight: 103, maxHeight: 103)
                            .overlay(
                                Text("Collecting data...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 103)

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

    init() {
        // Pre-fill dengan 60 titik nol (1 detik per titik, dari 60 detik lalu s/d sekarang)
        // Agar chart langsung terisi full dari kiri sejak pertama kali ditampilkan,
        // tanpa perlu menunggu 60 detik data real terkumpul.
        let now = Date()
        for i in 0..<maxPoints {
            let t = now.addingTimeInterval(Double(i - maxPoints))
            let zero = Point(timestamp: t, value: 0)
            downloadPoints.append(zero)
            uploadPoints.append(zero)
        }
    }

    func add(download: Double, upload: Double) {
        let now = Date()
        downloadPoints.append(Point(timestamp: now, value: download))
        uploadPoints.append(Point(timestamp: now, value: upload))
        if downloadPoints.count > maxPoints { downloadPoints.removeFirst() }
        if uploadPoints.count > maxPoints  { uploadPoints.removeFirst() }
    }
}

