// MixerRoutingSupport.swift
// BatteryGuard — Koordinasi Token Build Engine & Logic Routing Audio

import Foundation

/// Mengatur token build engine asynchronous untuk menghindari race condition saat volume diubah cepat.
struct MixerEngineBuilds {
    private var tokens: [String: Int] = [:]
    private var nextToken = 1

    var isEmpty: Bool { tokens.isEmpty }

    /// Mengklaim token build baru untuk app id. Mengembalikan nil jika sedang ada build in-flight.
    mutating func begin(_ id: String) -> Int? {
        guard tokens[id] == nil else { return nil }
        let token = nextToken
        nextToken += 1
        tokens[id] = token
        return token
    }

    /// Memeriksa apakah token masih valid untuk id tersebut
    func isCurrent(_ id: String, token: Int) -> Bool {
        tokens[id] == token
    }

    /// Menyelesaikan build token untuk id
    mutating func finish(_ id: String, token: Int) {
        guard tokens[id] == token else { return }
        tokens.removeValue(forKey: id)
    }

    /// Menginvalitasi semua token yang sedang berjalan (misal saat output device berubah)
    mutating func invalidateAll() {
        tokens.removeAll()
    }
}

enum MixerRoutingSupport {
    /// Pengecekan apakah volume berada di nilai default 100% (passthrough)
    static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1.0) < 0.005
    }

    static func isUnity(_ volume: Float) -> Bool {
        abs(volume - 1.0) < 0.005
    }

    /// Daftar bundle prefix DAW / Pro Audio yang tidak boleh di-tap (agar clock & latency driver tidak terganggu)
    private static let proAudioBundlePrefixes = [
        "com.apple.logic",       // Logic Pro
        "com.apple.garageband",
        "com.apple.mainstage",
        "com.ableton.",          // Live
        "com.avid.",             // Pro Tools
        "com.cockos.reaper",
        "com.steinberg.",        // Cubase, Nuendo
        "com.presonus.",         // Studio One
        "com.bitwig.",
        "com.image-line.",       // FL Studio
        "com.motu.",             // Digital Performer
    ]

    /// Menentukan apakah aplikasi harus dilewati dari pembuatan process tap
    static func bypassesProcessTap(bundleIdentifier: String?, name: String) -> Bool {
        let bundle = (bundleIdentifier ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()

        if bundle == "us.zoom.xos" || bundle.hasPrefix("us.zoom.") {
            return true
        }

        if proAudioBundlePrefixes.contains(where: { bundle.hasPrefix($0) }) {
            return true
        }

        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedName == "zoom"
            || normalizedName == "zoom.us"
            || normalizedName == "zoom workplace"
    }
}
