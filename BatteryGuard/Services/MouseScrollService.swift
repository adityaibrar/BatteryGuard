// MouseScrollService.swift
// BatteryGuard — Pemisahan scroll direction: mouse = normal, trackpad = natural.
//
// CARA KERJA:
// - CGEventTap mencegat semua scroll wheel events secara real-time
// - kCGScrollWheelEventIsContinuous == 0 → event diskrit dari mouse fisik → arah dibalik
// - kCGScrollWheelEventIsContinuous == 1 → event kontinu dari trackpad   → dibiarkan
//
// RESOURCE USAGE: sangat minimal — callback hanya dipanggil saat ada scroll event,
// tidak ada polling, tidak ada timer, tidak ada background thread.
//
// PERMISSION: Membutuhkan Accessibility access
//             (System Settings → Privacy & Security → Accessibility)

import Foundation
import Cocoa

// MARK: - File-private C-compatible Callback

/// Top-level function diperlukan agar bisa digunakan sebagai @convention(c) callback
/// oleh CGEventTap. Tidak bisa menggunakan closure yang capture self.
private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent?,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let event = event else { return nil }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

    // kCGScrollWheelEventIsContinuous:
    //   0 = scroll diskrit dari MOUSE FISIK (scroll wheel klik per klik)
    //   1 = scroll kontinu dari TRACKPAD atau momentum scrolling
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)

    guard isContinuous == 0 else {
        // Trackpad scroll → pass through tanpa modifikasi
        // Natural scrolling tetap berlaku sesuai system setting
        return Unmanaged.passUnretained(event)
    }

    // Mouse scroll → balik arah semua axis (Y = vertikal, X = horizontal)
    let d1  = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let d2  = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let pd1 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
    let pd2 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
    let fd1 = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fd2 = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1,        value: -d1)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2,        value: -d2)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1,    value: -pd1)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2,    value: -pd2)
    event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fd1)
    event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fd2)

    return Unmanaged.passUnretained(event)
}

// MARK: - MouseScrollService

/// Service untuk memisahkan perilaku scroll antara mouse fisik dan trackpad.
///
/// Alur:
/// - `start()` → aktifkan CGEventTap (saat toggle ON / app launch)
/// - `stop()`  → matikan CGEventTap (saat toggle OFF / app terminate)
final class MouseScrollService: ObservableObject {

    static let shared = MouseScrollService()

    // MARK: - Published State (untuk SwiftUI binding)

    /// Apakah CGEventTap sedang aktif mencegat scroll events
    @Published private(set) var isActive: Bool = false

    /// Apakah Accessibility permission sudah diberikan oleh user
    @Published private(set) var hasAccessibilityPermission: Bool = false

    // MARK: - Private

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let prefs = PreferencesStore.shared

    private init() {
        refreshPermissionStatus()
    }

    // MARK: - Accessibility Permission

    /// Cek status permission tanpa menampilkan prompt
    func refreshPermissionStatus() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    /// Tampilkan prompt System Settings untuk meminta Accessibility permission
    func requestAccessibilityPermission() {
        // Prompt macOS bawaan agar user klik "Open System Settings"
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Re-cek setelah delay singkat — user mungkin langsung grant dari prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshPermissionStatus()
            // Jika permission sudah diberikan dan toggle ON, langsung start
            if self?.hasAccessibilityPermission == true && self?.prefs.mouseAutoScrollEnabled == true {
                self?.start()
            }
        }
    }

    // MARK: - Start / Stop Event Tap

    /// Aktifkan event tap untuk intercept scroll events.
    /// - Parameter userInitiated: `true` jika dipanggil dari aksi user (toggle ON).
    ///   Saat `true` dan permission belum ada → otomatis tampilkan system prompt.
    ///   Saat `false` (launch) → gagal senyap tanpa mengganggu user.
    /// Idempotent — aman dipanggil berulang kali.
    func start(userInitiated: Bool = false) {
        guard prefs.mouseAutoScrollEnabled else { return }
        guard !isActive else { return }

        refreshPermissionStatus()
        guard hasAccessibilityPermission else {
            if userInitiated {
                // User sengaja mengaktifkan → tampilkan prompt permission macOS
                requestAccessibilityPermission()
            } else {
                // Dipanggil dari launch → log saja, jangan ganggu user
                print("[MouseScrollService] ℹ️ Toggle ON tapi Accessibility permission belum diberikan. Buka Settings → Mouse untuk mengaktifkan.")
            }
            return
        }

        // Buat event tap untuk scroll wheel saja
        let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: scrollTapCallback,
            userInfo: nil
        ) else {
            print("[MouseScrollService] ❌ Gagal membuat CGEventTap. Pastikan Accessibility access aktif.")
            return
        }

        // Daftarkan ke main run loop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap     = tap
        self.runLoopSource = source
        isActive = true
        print("[MouseScrollService] ✅ Aktif — scroll mouse dibalik, trackpad natural scrolling tetap.")
    }

    /// Hentikan event tap dan lepas resource.
    /// Idempotent — aman dipanggil berulang kali.
    func stop() {
        guard let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap     = nil
        runLoopSource = nil
        isActive = false
        print("[MouseScrollService] 🛑 Dihentikan.")
    }
}
