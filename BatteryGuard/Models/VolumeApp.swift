// VolumeApp.swift
// BatteryGuard — Model data untuk aplikasi di Volume Mixer

import AppKit
import CoreAudio

// MARK: - VolumeApp

/// Representasi sebuah aplikasi yang sedang aktif menggunakan audio output.
///
/// Desain mengikuti vorssaint-utils (MixerApp):
/// - `audioObjects` menyimpan AudioObjectID langsung dari HAL (bukan PID)
/// - `isMuted` adalah computed property dari `volume < 0.005`
/// - Satu sumber kebenaran untuk volume/mute state
struct VolumeApp: Identifiable, Equatable {
    let id: pid_t               // Process ID utama (owner app)
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?

    /// AudioObjectID dari HAL untuk proses-proses yang menghasilkan audio.
    /// DISIMPAN LANGSUNG dari kAudioHardwarePropertyProcessObjectList
    /// (bukan dikonversi dari PID setiap kali). Ini adalah nilai yang
    /// diberikan ke CATapDescription.
    var audioObjects: [AudioObjectID]

    /// Volume 0.0–2.0.
    /// - 0.0     = mute (computed `isMuted = true`)
    /// - 0.0–1.0 = reduksi
    /// - 1.0     = 100% passthrough (engine tidak aktif)
    /// - 1.0–2.0 = boost
    var volume: Float

    /// True jika saat ini sedang menghasilkan suara aktif
    var isPlayingAudio: Bool

    static func == (lhs: VolumeApp, rhs: VolumeApp) -> Bool {
        lhs.id == rhs.id &&
        lhs.volume == rhs.volume &&
        lhs.audioObjects == rhs.audioObjects &&
        lhs.isPlayingAudio == rhs.isPlayingAudio
    }
}

// MARK: - VolumeApp + Helpers

extension VolumeApp {
    var volumePercent: Int { Int(volume * 100) }
    var volumeLabel: String { "\(volumePercent)%" }
    var isBoosted: Bool { volume > 1.005 }

    /// Mute = volume mendekati 0 (satu sumber kebenaran)
    var isMuted: Bool { volume < 0.005 }
    var isEffectivelyMuted: Bool { isMuted }
}
