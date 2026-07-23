// DashboardCardView.swift
// BatteryGuard — Reusable card container untuk dashboard grid

import SwiftUI

// MARK: - DashboardCardView

/// Container card yang konsisten untuk semua 10 card dashboard
struct DashboardCardView<Content: View>: View {

    let title: String
    let icon: String
    var accentColor: Color = .blue
    var isLoading: Bool = false
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Card Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }

            Divider()

            // MARK: Card Content
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Info Row

/// Satu baris info key-value di dalam card
struct CardInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            Spacer()

            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Preview

#Preview("Dashboard Card") {
    DashboardCardView(title: "Battery Specs", icon: "cpu", accentColor: .blue) {
        VStack(spacing: 6) {
            CardInfoRow(label: "Design Capacity", value: "6068 mAh")
            CardInfoRow(label: "Serial Number", value: "ABC123DEF456", isMonospaced: true)
            CardInfoRow(label: "Manufacturer", value: "Apple Inc.")
        }
    }
    .frame(width: 300)
    .padding()
}
