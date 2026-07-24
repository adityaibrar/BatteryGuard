// BatteryTemperatureCard.swift
// Card 6: Suhu baterai dari IOKit AppleSmartBattery
//
// Akurasi:
// ✅ Battery temp: IOKit AppleSmartBattery.Temperature ÷ 100 → Celsius akurat
// ℹ️  CPU temp: Tidak tersedia tanpa root di Apple Silicon (M-series)
//     AppleARMPMUTempSensor memerlukan private IOHIDEvent entitlement

import SwiftUI

struct BatteryTemperatureCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var batteryTemp: TemperatureReading? {
        viewModel.temperatures.batteryTemperature
    }

    var body: some View {
        DashboardCardView(title: "Battery Temperature", icon: "thermometer.medium", accentColor: tempColor) {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: Current temperature — large display
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(batteryTemp.map { String(format: "%.1f", $0.celsius) } ?? "--")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(tempColor)
                    Text("°C")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let temp = batteryTemp {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f°F", temp.fahrenheit))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tempLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(tempColor)
                        }
                    }
                }

                // MARK: Temperature gauge
                if let temp = batteryTemp {
                    TemperatureGaugeView(celsius: temp.celsius, range: 20...60)
                }

                Divider()

                // MARK: Info rows
                VStack(spacing: 6) {
                    CardInfoRow(
                        label: "Source",
                        value: "AppleSmartBattery (IOKit)",
                        valueColor: .secondary
                    )

                    // Status kesehatan suhu
                    if let celsius = batteryTemp?.celsius {
                        CardInfoRow(
                            label: "Battery Thermal",
                            value: thermalStatus(celsius),
                            valueColor: tempColor
                        )
                    }

                    // CPU temp — jujur tentang keterbatasan
                    HStack(alignment: .top) {
                        Text("CPU Temperature")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 120, alignment: .leading)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text("Requires root (Apple Silicon)")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func thermalStatus(_ celsius: Double) -> String {
        switch celsius {
        case ..<35: return "Optimal"
        case 35..<45: return "Normal"
        case 45..<55: return "Warm — monitor usage"
        default: return "Hot — reduce load"
        }
    }
}

// MARK: - Temperature Gauge

struct TemperatureGaugeView: View {
    let celsius: Double
    let range: ClosedRange<Double>

    private var normalized: Double {
        min(1.0, max(0.0, (celsius - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track gradient
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

                // Current position indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 3, height: 14)
                    .offset(x: max(0, min(geo.size.width - 3, geo.size.width * normalized)))
                    .shadow(radius: 2)
                    .animation(.easeInOut, value: celsius)

                // Range labels overlay
                HStack {
                    Text("20°")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Spacer()
                    Text("60°")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .offset(y: 10)
            }
        }
        .frame(height: 24)
    }
}
