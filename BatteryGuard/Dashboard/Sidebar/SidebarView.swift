// SidebarView.swift
// BatteryGuard — Navigasi sidebar kiri dashboard

import SwiftUI

// MARK: - Sidebar Navigation Items

enum DashboardSection: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case dashboard = "Dashboard"
    case chargeControl = "Charge Control"
    case sleepBehavior = "Sleep Behavior"
    case energyUse = "Energy Use"
    case schedule = "Schedule"
    case shortcuts = "Shortcuts"
    case appearance = "Appearance"

    var icon: String {
        switch self {
        case .dashboard:      return "gauge.with.dots.needle.bottom.50percent"
        case .chargeControl:  return "bolt.badge.clock"
        case .sleepBehavior:  return "moon.zzz"
        case .energyUse:      return "bolt.fill"
        case .schedule:       return "calendar.badge.clock"
        case .shortcuts:      return "keyboard"
        case .appearance:     return "paintpalette"
        }
    }

    var color: Color {
        switch self {
        case .dashboard:      return .blue
        case .chargeControl:  return .green
        case .sleepBehavior:  return .indigo
        case .energyUse:      return .orange
        case .schedule:       return .teal
        case .shortcuts:      return .purple
        case .appearance:     return .pink
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
