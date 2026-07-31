// AppDelegate.swift
// BatteryGuard — Application lifecycle + NSStatusItem (AppKit)
// Menggunakan NSStatusItem langsung agar bisa render 2-baris layout
// yang tidak bisa dilakukan oleh SwiftUI MenuBarExtra label.

import AppKit
import SwiftUI
import ServiceManagement

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Shared State
    // Di-init di sini agar bisa dipakai oleh NSStatusItem + SwiftUI scenes

    let viewModel     = SystemStatsViewModel()
    let prefs         = PreferencesStore.shared
    let helperInstaller = HelperInstaller()

    // MARK: - Status Bar (AppKit)

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkAndInstallHelper()
        setupSystemNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Helper daemon tetap berjalan setelah app quit (by design)
    }

    /// Jangan quit saat semua window ditutup — ini menu bar app,
    /// harus tetap hidup di background
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDashboard() }
        return true
    }

    // MARK: - NSStatusItem Setup

    private func setupStatusItem() {
        // 1. Buat status item dengan panjang fixed
        statusItem = NSStatusBar.system.statusItem(withLength: 315)

        // 2. Buat SwiftUI view untuk label — 2-baris compact
        let labelView = MenuBarStatusLabel(viewModel: viewModel, prefs: prefs)
        let hosting   = NSHostingView(rootView: labelView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // 3. Embed hosting view di dalam button status item
        //    Button handle klik via target/action (cara modern, non-deprecated)
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(handleStatusClick)
        button.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        // 4. Setup popover
        setupPopover()
    }

    private func setupPopover() {
        let content = MenuBarView()
            .environmentObject(viewModel)
            .environmentObject(prefs)
            .environmentObject(helperInstaller)

        let controller    = NSHostingController(rootView: content)
        let pop           = NSPopover()
        pop.contentViewController = controller
        pop.contentSize   = NSSize(width: 300, height: 420)
        pop.behavior      = .transient
        pop.animates      = true
        self.popover      = pop
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        guard let pop = popover, let button = statusItem?.button else { return }
        if pop.isShown {
            pop.performClose(sender)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Helper Installation

    private func checkAndInstallHelper() {
        let service = SMAppService.daemon(plistName: "com.ibrardev.BatteryGuard.Helper.plist")
        switch service.status {
        case .enabled:       break
        case .requiresApproval: showHelperApprovalNotification()
        case .notFound:      break
        case .notRegistered: break
        @unknown default:    break
        }
    }

    private func showHelperApprovalNotification() {
        print("[AppDelegate] Helper memerlukan approval di System Settings > Privacy & Security > Background Items")
    }

    // MARK: - System Notifications

    private func setupSystemNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handlePowerChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handlePowerChange(_ notification: Notification) {
        // Re-apply charge limit setelah wake dari sleep
    }

    // MARK: - Window Management

    @objc func openDashboard() {
        for window in NSApp.windows {
            if window.identifier?.rawValue == "dashboard" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
    }
}

// MARK: - MenuBarStatusLabel
// SwiftUI view untuk label NSStatusItem — layout 2 baris stacked

struct MenuBarStatusLabel: View {
    @ObservedObject var viewModel: SystemStatsViewModel
    @ObservedObject var prefs: PreferencesStore

    var body: some View {
        // spacing 10 agar tiap item tidak berdempetan
        HStack(spacing: 10) {

            // Network Speed — kolom fixed 58pt supaya nilai yg berubah
            // tidak menggeser item lain (monospaced font membantu stabilitas)
            if prefs.showNetworkSpeed {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 2) {
                        Text("↑")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.green)
                        Text(compactSpeed(viewModel.networkStats.uploadBytesPerSec))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                    HStack(spacing: 2) {
                        Text("↓")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(compactSpeed(viewModel.networkStats.downloadBytesPerSec))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(width: 72, alignment: .trailing) // fixed — tidak bergerak saat nilai berubah
            }

            // GPU % — fixed 45pt
            if prefs.showGPUUsage {
                StatusChip(label: "GPU",
                           value: viewModel.gpuStats.shortFormatted,
                           color: gpuColor)
                    .frame(width: 45, alignment: .center)
            }

            // RAM % — fixed 45pt
            if prefs.showRAMUsage {
                StatusChip(label: "RAM",
                           value: String(format: "%.0f%%", viewModel.ramStats.usagePercent),
                           color: ramColor)
                    .frame(width: 45, alignment: .center)
            }

            // CPU % — fixed 45pt
            if prefs.showCPUUsage {
                StatusChip(label: "CPU",
                           value: viewModel.cpuStats.shortFormatted,
                           color: cpuColor)
                    .frame(width: 45, alignment: .center)
            }

            // Suhu
            if prefs.showTemperature {
                let temp = viewModel.temperatures.cpuTemperature
                        ?? viewModel.temperatures.batteryTemperature
                if let temp {
                    Text(temp.shortFormatted)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tempColor(temp.celsius))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Helpers

    /// Format kecepatan dengan satuan jelas: "352 KB/s", "1.2 MB/s", "0 KB/s"
    private func compactSpeed(_ bps: Double) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
        if bps >= 1_000     { return String(format: "%.0f KB/s", bps / 1_000) }
        return "0 KB/s"
    }

    private var gpuColor: Color {
        guard let u = viewModel.gpuStats.usagePercent else { return .primary }
        return u < 50 ? .primary : u < 80 ? .orange : .red
    }

    private var ramColor: Color {
        let u = viewModel.ramStats.usagePercent
        return u < 70 ? .primary : u < 85 ? .orange : .red
    }

    private var cpuColor: Color {
        let u = viewModel.cpuStats.totalUsagePercent
        return u < 50 ? .primary : u < 80 ? .orange : .red
    }

    private func tempColor(_ c: Double) -> Color {
        c < 60 ? .primary : c < 80 ? .orange : .red
    }
}

// MARK: - StatusChip
// 2-baris: label kecil 30% di atas, nilai besar 70% di bawah

struct StatusChip: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Label — ~30% tinggi (font 7pt)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
            // Nilai — ~70% tinggi (font 13pt)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
