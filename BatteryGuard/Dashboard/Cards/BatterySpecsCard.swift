// BatterySpecsCard.swift
// Card 1: Informasi statis baterai dari IOKit

import SwiftUI

struct BatterySpecsCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var specs: BatterySpecs { viewModel.batterySpecs }

    var body: some View {
        DashboardCardView(title: "Battery Specs", icon: "cpu", accentColor: .blue) {
            VStack(spacing: 6) {
                CardInfoRow(
                    label: "Design Capacity",
                    value: specs.designCapacity.map { "\($0) mAh" } ?? "—"
                )
                CardInfoRow(
                    label: "Serial Number",
                    value: specs.serialNumber ?? "—",
                    isMonospaced: true
                )
                CardInfoRow(
                    label: "Manufacturer",
                    value: specs.manufacturer ?? "Apple Inc."
                )
                CardInfoRow(
                    label: "Device Name",
                    value: specs.deviceName ?? "—"
                )
                CardInfoRow(
                    label: "Manufacture Date",
                    value: specs.manufactureDate.map {
                        DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
                    } ?? "—"
                )
            }
        }
    }
}
