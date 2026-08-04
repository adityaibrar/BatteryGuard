// BoostLimiter.swift
// BatteryGuard — Peak Limiter Real-Time untuk Volume Boost (> 100%)

import Foundation

/// Menjaga sinyal audio yang di-boost (> 100%) tetap berada dalam rentang aman [-1.0, 1.0]
/// tanpa menyebabkan clipping/distorsi kasar.
///
/// Menggunakan instant attack dan exponential decay untuk dynamic range compression transparan.
/// Menghitung koefisien release dinamis berdasarkan sample rate output device.
/// Berjalan pada audio thread real-time (zero memory allocation & zero locking).
struct BoostLimiter {
    /// Ceiling batas output maksimum (~ -0.5 dB FS)
    static let ceiling: Float = 0.944

    /// Durasi recovery gain setelah melewati peak (160ms)
    static let releaseMilliseconds: Double = 160

    /// Menghitung faktor peluruhan per sample berdasarkan sample rate output device
    static func release(sampleRate: Double) -> Float {
        let rate = sampleRate.isFinite && sampleRate >= 8000 ? sampleRate : 48000
        return Float(exp(-1000.0 / (rate * releaseMilliseconds)))
    }

    private var envelope: Float = 0

    /// Memproses array sampel Float secara in-place
    mutating func process(_ samples: UnsafeMutablePointer<Float>,
                          frames: Int,
                          channels: Int,
                          release: Float) {
        guard frames > 0, channels > 0 else { return }
        var envelope = self.envelope
        let ceiling = Self.ceiling
        var base = 0
        for _ in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let magnitude = abs(samples[base + channel])
                if magnitude > peak { peak = magnitude }
            }
            // Instant attack, exponential decay
            envelope = peak > envelope ? peak : peak + (envelope - peak) * release
            if envelope > ceiling {
                let gain = ceiling / envelope
                for channel in 0..<channels {
                    samples[base + channel] *= gain
                }
            }
            base += channels
        }
        self.envelope = envelope
    }
}
