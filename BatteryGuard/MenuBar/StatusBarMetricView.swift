// StatusBarMetricView.swift
// BatteryGuard — Komponen reusable untuk satu metrik di menu bar

import SwiftUI

// MARK: - StatusBarMetricView

/// Tampilkan satu metrik secara horizontal di menu bar
/// Contoh: [icon] [value] [unit]
struct StatusBarMetricView: View {

    let icon: String         // SF Symbol name
    let value: String        // Nilai utama (misal "42.3")
    let unit: String         // Unit (misal "°C", "MB/s", "%")
    var color: Color = .primary
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)

            if !isCompact {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Compact: hanya tampilkan value tanpa unit
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 3)
    }
}

// MARK: - Network Speed Dual View

/// Tampilkan download + upload dalam satu baris
struct NetworkSpeedMetricView: View {
    let downloadFormatted: String
    let uploadFormatted: String
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            // Download
            HStack(spacing: 1) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
                Text(downloadFormatted)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }

            if !isCompact {
                // Upload
                HStack(spacing: 1) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                    Text(uploadFormatted)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Status Bar Metric") {
    HStack(spacing: 8) {
        StatusBarMetricView(icon: "battery.75", value: "75", unit: "%", color: .green)
        StatusBarMetricView(icon: "thermometer.medium", value: "42", unit: "°C", color: .orange)
        StatusBarMetricView(icon: "memorychip", value: "12.4", unit: "GB")
        NetworkSpeedMetricView(downloadFormatted: "1.2 MB/s", uploadFormatted: "234 KB/s")
    }
    .padding()
    .frame(height: 40)
    .background(.regularMaterial)
}
