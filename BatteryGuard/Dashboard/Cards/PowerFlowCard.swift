// PowerFlowCard.swift
// Card 8: Visual aliran daya — charger → baterai → sistem

import SwiftUI

struct PowerFlowCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    @State private var animationOffset: CGFloat = 0

    private var isCharging: Bool { viewModel.batteryStatus.isCharging }
    private var isPluggedIn: Bool { viewModel.batteryStatus.isPluggedIn }

    var body: some View {
        DashboardCardView(title: "Power Flow", icon: "arrow.trianglehead.2.clockwise.rotate.90", accentColor: flowColor) {
            VStack(spacing: 16) {
                // Flow diagram
                HStack(spacing: 0) {
                    // Charger node
                    PowerFlowNode(
                        icon: isPluggedIn ? "powerplug.fill" : "powerplug",
                        label: "Adapter",
                        sublabel: viewModel.adapterInfo.wattage.map { "\(Int($0))W" } ?? "—",
                        color: isPluggedIn ? .indigo : .secondary,
                        isActive: isPluggedIn
                    )

                    // Flow arrow: Adapter → Battery
                    FlowArrow(
                        isActive: isCharging,
                        direction: .right,
                        color: .green
                    )

                    // Battery node
                    PowerFlowNode(
                        icon: viewModel.batteryIconName,
                        label: "Battery",
                        sublabel: "\(viewModel.batteryStatus.percentage)%",
                        color: viewModel.batteryStatus.isCharging ? .green : .primary,
                        isActive: true
                    )

                    // Flow arrow: Battery → System
                    FlowArrow(
                        isActive: !isCharging,
                        direction: .right,
                        color: .orange
                    )

                    // System node
                    PowerFlowNode(
                        icon: "desktopcomputer",
                        label: "System",
                        sublabel: viewModel.powerFlow.instantWattage.map {
                            String(format: "%.1fW", $0)
                        } ?? "—",
                        color: .blue,
                        isActive: true
                    )
                }

                // Status label
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .animation(.easeInOut, value: statusLabel)
            }
        }
    }

    private var statusLabel: String {
        if isCharging {
            return "Charging from adapter to battery"
        } else if isPluggedIn {
            return "Running on adapter, battery not charging"
        } else {
            return "Running on battery power"
        }
    }

    private var flowColor: Color {
        isCharging ? .green : (isPluggedIn ? .indigo : .orange)
    }
}

// MARK: - Power Flow Node

struct PowerFlowNode: View {
    let icon: String
    let label: String
    let sublabel: String
    var color: Color = .primary
    var isActive: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isActive ? color : .secondary)
            }

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(sublabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(isActive ? 1.0 : 0.5)
    }
}

// MARK: - Flow Arrow

struct FlowArrow: View {
    let isActive: Bool
    let direction: Direction
    let color: Color

    enum Direction { case right, left }

    @State private var animating = false

    var body: some View {
        Image(systemName: direction == .right ? "chevron.right" : "chevron.left")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isActive ? color : .secondary.opacity(0.3))
            .scaleEffect(animating && isActive ? 1.1 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: animating
            )
            .onAppear { animating = true }
            .frame(width: 20)
    }
}
