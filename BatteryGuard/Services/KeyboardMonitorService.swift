// KeyboardMonitorService.swift
// BatteryGuard — Service utama untuk Keyboard Key Press Counter
//
// ARSITEKTUR & CARA KERJA:
// - Menggunakan IOHIDManager (IOKit) untuk intercept keyboard events di level HID
// - IOHIDManager memberikan callback PER-DEVICE sehingga bisa membedakan keyboard
//   internal Mac vs keyboard eksternal (USB/Bluetooth)
// - Semua key ditrack termasuk modifier keys (⌘, ⇧, ⌥, ⌃, ⇪)
// - Data persisted akumulatif ke JSON via KeyboardStatsStore
//
// PERMISSION: Input Monitoring (Privacy & Security → Input Monitoring)
// Berbeda dari Accessibility — spesifik untuk keyboard monitoring via IOHIDManager.
// Dicek dengan CGPreflightListenEventAccess() & IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).

import Foundation
import IOKit.hid
import Combine
import CoreGraphics
import Cocoa

// MARK: - KeyboardMonitorService

final class KeyboardMonitorService: ObservableObject {

    static let shared = KeyboardMonitorService()

    // MARK: - Published State

    /// Apakah IOHIDManager sedang aktif memonitor input
    @Published private(set) var isActive: Bool = false

    /// Apakah Input Monitoring permission sudah diberikan user
    @Published private(set) var hasInputMonitoringPermission: Bool = false

    /// Semua keyboard yang saat ini terkoneksi (internal + eksternal)
    @Published private(set) var connectedKeyboards: [KeyboardDevice] = []

    /// Device yang dipilih user untuk ditampilkan di UI (nil = default ke first device)
    @Published var selectedDeviceID: String? = nil

    // MARK: - Private State

    private var hidManager: IOHIDManager?
    private let store = KeyboardStatsStore.shared
    private let prefs = PreferencesStore.shared
    private var cancellables = Set<AnyCancellable>()

    /// Timer periodik untuk auto-save data ke disk (setiap 30 detik)
    private var saveTimer: Timer?

    /// Timer periodik untuk memantau status izin
    private var permissionTimer: Timer?

    private init() {
        refreshPermissionStatus()
        setupPermissionWatcher()
        setupPreferenceObserver()
    }

    deinit {
        permissionTimer?.invalidate()
        saveTimer?.invalidate()
        stop()
    }

    // MARK: - Permission

    /// Memeriksa status izin Input Monitoring / ListenEvent di macOS
    static func checkInputMonitoringAccess() -> Bool {
        if #available(macOS 10.15, *) {
            if CGPreflightListenEventAccess() {
                return true
            }
        }
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        return status == kIOHIDAccessTypeGranted
    }

    /// Cek status Input Monitoring permission tanpa menampilkan prompt
    func refreshPermissionStatus() {
        let granted = Self.checkInputMonitoringAccess()
        DispatchQueue.main.async {
            self.hasInputMonitoringPermission = granted
            if granted && self.prefs.keyboardMonitorEnabled && !self.isActive {
                self.start()
            }
        }
    }

    /// Tampilkan dialog system permission, daftarkan aplikasi ke TCC, dan buka System Settings
    func requestInputMonitoringPermission() {
        // 1. Panggil CGRequestListenEventAccess (macOS 10.15+)
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }

        // 2. Panggil IOHIDRequestAccess untuk ListenEvent
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        // 3. Buat probe CGEventTap untuk memaksa WindowServer/TCC mendaftarkan bundle ID aplikasi ke daftar Input Monitoring
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let probeTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        if let probeTap = probeTap {
            CFMachPortInvalidate(probeTap)
        }

        // 4. Buka jendela System Settings -> Input Monitoring
        openSystemSettingsInputMonitoring()

        // 5. Polling untuk mendeteksi saat user memberikan izin di System Settings
        for delay in [1.0, 2.0, 3.5, 5.0, 7.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshPermissionStatus()
            }
        }
    }

    /// Tampilkan file BatteryGuard.app di Finder untuk memudahkan drag & drop atau add manual jika di build via Xcode
    func revealInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// Buka System Settings langsung ke Privacy & Security -> Input Monitoring
    func openSystemSettingsInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            if !NSWorkspace.shared.open(url) {
                if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(fallback)
                }
            }
        }
    }

    /// Restart BatteryGuard agar macOS memuat credential TCC yang baru diberikan pengguna
    func relaunchApplication() {
        store.persist()
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Permission Watcher Setup

    private func setupPermissionWatcher() {
        // 1. Observer saat aplikasi kembali aktif dari System Settings
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshPermissionStatus()
                if self.hasInputMonitoringPermission && self.prefs.keyboardMonitorEnabled && !self.isActive {
                    self.start()
                }
            }
            .store(in: &cancellables)

        // 2. Periodic watcher ringan tiap 1.5 detik jika permission belum aktif atau service belum jalan
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Self.checkInputMonitoringAccess()
            if self.hasInputMonitoringPermission != granted {
                self.refreshPermissionStatus()
            }
            if granted && self.prefs.keyboardMonitorEnabled && !self.isActive {
                self.start()
            }
        }
    }

    // MARK: - Preference Observer

    private func setupPreferenceObserver() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.prefs.keyboardMonitorEnabled {
                    if !self.isActive && self.hasInputMonitoringPermission {
                        self.start()
                    }
                } else {
                    if self.isActive { self.stop() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Start / Stop

    func start(userInitiated: Bool = false) {
        guard prefs.keyboardMonitorEnabled else { return }
        guard !isActive else { return }

        // Verifikasi permission sebelum mulai
        let granted = Self.checkInputMonitoringAccess()
        DispatchQueue.main.async { self.hasInputMonitoringPermission = granted }

        guard granted else {
            if userInitiated {
                requestInputMonitoringPermission()
            } else {
                print("[KeyboardMonitorService] ℹ️ Menunggu Input Monitoring permission...")
            }
            return
        }

        // Buat IOHIDManager
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Filter: hanya Keyboard/Keypad HID devices
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // ── Callback: device baru terkoneksi ──────────────────────────────────
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                let svc = Unmanaged<KeyboardMonitorService>.fromOpaque(context).takeUnretainedValue()
                svc.handleDeviceConnected(device: device)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        // ── Callback: device dicabut / dilepas ────────────────────────────────
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                let svc = Unmanaged<KeyboardMonitorService>.fromOpaque(context).takeUnretainedValue()
                svc.handleDeviceRemoved(device: device)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        // ── Callback: input value (key press / release) ───────────────────────
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, sender, value in
                guard let context else { return }
                let svc = Unmanaged<KeyboardMonitorService>.fromOpaque(context).takeUnretainedValue()
                svc.handleInputValue(sender: sender, value: value)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        // Schedule pada main run loop agar callback terpanggil di main thread
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Buka manager
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            print("[KeyboardMonitorService] ❌ Gagal membuka IOHIDManager: \(result)")
            DispatchQueue.main.async { self.isActive = false }
            return
        }

        // Temukan device yang sudah terhubung saat ini
        discoverConnectedKeyboards(from: manager)

        DispatchQueue.main.async { self.isActive = true }

        // Auto-save setiap 30 detik agar data tidak hilang jika app crash
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.store.persist()
        }

        print("[KeyboardMonitorService] ✅ Aktif — monitoring semua keyboard termasuk modifier keys.")
    }

    func stop() {
        saveTimer?.invalidate()
        saveTimer = nil

        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil

        // Simpan data ke disk saat stop
        store.persist()

        DispatchQueue.main.async {
            self.isActive = false
            self.connectedKeyboards = []
        }
        print("[KeyboardMonitorService] 🛑 Dihentikan — data disimpan.")
    }

    // MARK: - Initial Device Discovery

    private func discoverConnectedKeyboards(from manager: IOHIDManager) {
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for device in deviceSet {
            handleDeviceConnected(device: device)
        }
    }

    // MARK: - Device Lifecycle Callbacks

    func handleDeviceConnected(device: IOHIDDevice) {
        let keyboard = buildKeyboardDevice(from: device)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.connectedKeyboards.contains(where: { $0.id == keyboard.id }) {
                self.connectedKeyboards.append(keyboard)
                print("[KeyboardMonitorService] ⌨️ Keyboard terhubung: \(keyboard.displayName) (id: \(keyboard.id))")
            }
            if self.selectedDeviceID == nil {
                self.selectedDeviceID = keyboard.id
            }
        }
    }

    func handleDeviceRemoved(device: IOHIDDevice) {
        let deviceID = buildDeviceID(from: device)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectedKeyboards.removeAll { $0.id == deviceID }
            print("[KeyboardMonitorService] 🔌 Keyboard dicabut (id: \(deviceID))")
            if self.selectedDeviceID == deviceID {
                self.selectedDeviceID = self.connectedKeyboards.first?.id
            }
        }
    }

    // MARK: - Input Value Handling

    func handleInputValue(sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intVal = IOHIDValueGetIntegerValue(value)

        // Hanya proses Keyboard / Keypad Usage Page (0x07)
        guard usagePage == kHIDPage_KeyboardOrKeypad else { return }

        // Hanya proses penekanan (intVal == 1 untuk key down / press)
        guard intVal == 1 else { return }

        // Abaikan usage 0 (Undefined) atau range error
        guard usage > 0, usage < 0xFF else { return }

        // Lookup label tombol
        guard let keyLabel = HIDKeyLabel.from(usage: usage) else { return }

        // Tentukan device ID & nama
        let deviceID: String
        let deviceName: String
        let isInternal: Bool

        if let sender = sender {
            let hidDevice = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            deviceID = buildDeviceID(from: hidDevice)
            deviceName = getDeviceName(from: hidDevice)
            isInternal = deviceName.lowercased().contains("internal") || deviceName.lowercased().contains("apple")
        } else {
            // Fallback: gunakan device pertama yang terkoneksi
            let first = connectedKeyboards.first
            deviceID = first?.id ?? "unknown"
            deviceName = first?.name ?? "Unknown Keyboard"
            isInternal = first?.isInternal ?? false
        }

        // Update store (harus di main thread karena store.data tidak thread-safe)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.store.increment(
                deviceID: deviceID,
                deviceName: deviceName,
                isInternal: isInternal,
                keyLabel: keyLabel
            )
            // Trigger SwiftUI update
            self.objectWillChange.send()
        }
    }

    // MARK: - Reset Methods

    func reset(deviceID: String) {
        store.reset(deviceID: deviceID)
        objectWillChange.send()
    }

    func resetAll() {
        store.resetAll()
        objectWillChange.send()
    }

    // MARK: - IOHIDDevice Helpers

    private func buildDeviceID(from device: IOHIDDevice) -> String {
        let vendor  = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey  as CFString) as? Int) ?? 0
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int) ?? 0
        return "\(vendor)_\(product)_\(location)"
    }

    private func getDeviceName(from device: IOHIDDevice) -> String {
        (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Unknown Keyboard"
    }

    private func buildKeyboardDevice(from device: IOHIDDevice) -> KeyboardDevice {
        let vendor  = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey  as CFString) as? Int) ?? 0
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int) ?? 0
        let name    = (IOHIDDeviceGetProperty(device, kIOHIDProductKey   as CFString) as? String) ?? "Apple Internal Keyboard"
        let id      = "\(vendor)_\(product)_\(location)"

        return KeyboardDevice(
            id: id,
            name: name,
            vendorID: vendor,
            productID: product,
            locationID: location
        )
    }

    // MARK: - Convenience Accessors (dipakai di View)

    /// Semua device yang dikenal (terkoneksi fisik + riwayat di penyimpanan)
    var allKnownDevices: [KeyboardDevice] {
        var devices = connectedKeyboards
        for (id, stat) in store.data {
            if !devices.contains(where: { $0.id == id }) {
                devices.append(KeyboardDevice(
                    id: id,
                    name: stat.deviceName,
                    vendorID: 0,
                    productID: 0,
                    locationID: 0
                ))
            }
        }
        if devices.isEmpty {
            devices.append(KeyboardDevice(
                id: "internal_keyboard",
                name: "Apple Internal Keyboard",
                vendorID: 0,
                productID: 0,
                locationID: 0
            ))
        }
        return devices
    }

    /// ID perangkat yang aktif dipilih (fallback ke default jika belum diset)
    var effectiveSelectedDeviceID: String {
        if let id = selectedDeviceID, allKnownDevices.contains(where: { $0.id == id }) {
            return id
        }
        return allKnownDevices.first?.id ?? "internal_keyboard"
    }

    /// Key counts untuk device yang sedang dipilih
    var currentKeyCounts: [String: Int] {
        let deviceID = effectiveSelectedDeviceID
        return store.data[deviceID]?.keyCounts ?? [:]
    }

    /// Total press untuk device yang sedang dipilih
    var currentTotalPresses: Int {
        let deviceID = effectiveSelectedDeviceID
        return store.totalPresses(for: deviceID)
    }

    /// Top N keys untuk device yang sedang dipilih
    func currentTopKeys(limit: Int = 10) -> [KeyPressEntry] {
        let deviceID = effectiveSelectedDeviceID
        return store.topKeys(for: deviceID, limit: limit)
    }

    /// Count untuk key tertentu pada device yang sedang dipilih
    func count(for keyLabel: String) -> Int {
        let deviceID = effectiveSelectedDeviceID
        return store.count(for: keyLabel, deviceID: deviceID)
    }

    /// Jumlah unique keys pada device yang sedang dipilih
    var currentUniqueKeyCount: Int {
        let deviceID = effectiveSelectedDeviceID
        return store.uniqueKeyCount(for: deviceID)
    }
}
