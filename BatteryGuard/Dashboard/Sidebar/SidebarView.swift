// SidebarView.swift
// BatteryGuard — Navigasi sidebar kiri dashboard

import SwiftUI

// MARK: - Sidebar Navigation Items

enum DashboardSection: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case dashboard = "Dashboard"
    case chargeControl = "Charge Control"
    case energyUse = "Energy Use"
    case log = "Log"
    case uninstaller = "Uninstaller"

    var icon: String {
        switch self {
        case .dashboard:      return "gauge.with.dots.needle.bottom.50percent"
        case .chargeControl:  return "bolt.badge.clock"
        case .energyUse:      return "bolt.fill"
        case .log:            return "terminal"
        case .uninstaller:    return "trash"
        }
    }

    var color: Color {
        switch self {
        case .dashboard:      return .blue
        case .chargeControl:  return .green
        case .energyUse:      return .orange
        case .log:            return .purple
        case .uninstaller:    return .red
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selection: DashboardSection?

    var body: some View {
        List(DashboardSection.allCases, selection: $selection) { section in
            Label {
                Text(section.rawValue)
            } icon: {
                Image(systemName: section.icon)
                    .foregroundStyle(section.color)
            }
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("BatteryGuard")
        .frame(minWidth: 180)
    }
}
