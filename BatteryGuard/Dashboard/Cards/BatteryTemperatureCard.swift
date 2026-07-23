// BatteryTemperatureCard.swift
// Card 6: Suhu baterai dari IOKit AppleSmartBattery

import SwiftUI

struct BatteryTemperatureCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var batteryTemp: TemperatureReading? {
        viewModel.temperatures.batteryTemperature
    }

    var body: some View {
        DashboardCardView(title: "Battery Temperature", icon: "thermometer.medium", accentColor: tempColor) {
            VStack(alignment: .leading, spacing: 12) {
                // Current temperature
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(batteryTemp.map { String(format: "%.1f", $0.celsius) } ?? "--")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(tempColor)
                    Text("°C")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let temp = batteryTemp {
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.1f°F", temp.fahrenheit))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tempLabel)
                                .font(.caption)
                                .foregroundStyle(tempColor)
                        }
                    }
                }

                // Temperature gauge
                if let temp = batteryTemp {
                    TemperatureGaugeView(celsius: temp.celsius, range: 20...60)
                }

                // CPU temperature (jika tersedia)
                if let cpuTemp = viewModel.temperatures.cpuTemperature {
                    Divider()
                    CardInfoRow(
                        label: "CPU Temperature",
                        value: cpuTemp.formattedCelsius,
                        valueColor: cpuTempColor(cpuTemp.celsius)
                    )
                } else {
                    Divider()
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("CPU temp requires monitoring enabled in Settings")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var tempColor: Color {
        guard let celsius = batteryTemp?.celsius else { return .secondary }
        switch celsius {
        case ..<35: return .blue
        case 35..<45: return .green
        case 45..<55: return .orange
        default: return .red
        }
    }

    private var tempLabel: String {
        guard let celsius = batteryTemp?.celsius else { return "" }
        switch celsius {
        case ..<35: return "Cool"
        case 35..<45: return "Normal"
        case 45..<55: return "Warm"
        default: return "Hot"
        }
    }

    private func cpuTempColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - Temperature Gauge

struct TemperatureGaugeView: View {
    let celsius: Double
    let range: ClosedRange<Double>

    private var normalized: Double {
        (celsius - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .green, .yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(0.3)
                    .frame(height: 6)

                // Indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 3, height: 14)
                    .offset(x: max(0, min(geo.size.width - 3, geo.size.width * normalized)))
                    .shadow(radius: 2)
                    .animation(.easeInOut, value: celsius)
            }
        }
        .frame(height: 14)
    }
}
