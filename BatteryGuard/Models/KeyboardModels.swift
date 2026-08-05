// KeyboardModels.swift
// BatteryGuard — Data models untuk Keyboard Key Press Counter

import Foundation

// MARK: - KeyboardDevice

/// Representasi satu perangkat keyboard fisik yang terdeteksi via IOHIDManager
struct KeyboardDevice: Identifiable, Hashable, Codable {

    /// Format: "vendorID_productID_locationID" — unik per perangkat fisik
    let id: String

    /// Nama human-readable dari IOKit (contoh: "Apple Internal Keyboard / Trackpad")
    let name: String

    let vendorID: Int
    let productID: Int
    let locationID: Int

    // MARK: - Computed

    /// Heuristik sederhana: internal keyboard Apple biasanya namanya mengandung "Internal"
    var isInternal: Bool {
        let lower = name.lowercased()
        return lower.contains("internal") || lower.contains("built-in") || lower.contains("apple internal")
    }

    /// Nama ringkas untuk ditampilkan di UI
    var displayName: String {
        if isInternal { return "Internal Keyboard" }
        // Potong nama yang terlalu panjang
        if name.count > 40 { return String(name.prefix(37)) + "..." }
        return name
    }

    /// SF Symbol yang mewakili jenis keyboard ini
    var icon: String {
        isInternal ? "keyboard" : "keyboard.badge.ellipsis"
    }

    /// Warna aksen untuk card di UI
    var accentColorName: String {
        isInternal ? "purple" : "indigo"
    }
}

// MARK: - KeyPressEntry

/// Satu entri key beserta jumlah press — digunakan untuk top-list & heatmap
struct KeyPressEntry: Identifiable, Comparable {

    /// Key label sebagai ID (contoh: "A", "Space", "⌘", "F1")
    let id: String

    var label: String
    var count: Int

    /// Descending sort (key paling sering di index 0)
    static func < (lhs: KeyPressEntry, rhs: KeyPressEntry) -> Bool {
        lhs.count > rhs.count
    }
}

// MARK: - HID Key Label Mapping

/// Static mapping dari HID Usage code (keyboard/keypad page) ke label human-readable.
/// Mencakup SEMUA jenis key: huruf, angka, simbol, modifier, special, arrow, function, numpad.
enum HIDKeyLabel {

    /// Kembalikan label string untuk HID usage code (Int), atau nil jika tidak dikenal
    static func label(for usage: Int) -> String? {
        guard usage >= 0 else { return nil }
        return labelMap[UInt32(usage)]
    }

    /// Kembalikan label string untuk HID usage code (UInt32), atau nil jika tidak dikenal
    static func label(for usage: UInt32) -> String? {
        return labelMap[usage]
    }

    /// Alias convenience
    static func from(usage: Int) -> String? {
        label(for: usage)
    }

    static func from(usage: UInt32) -> String? {
        label(for: usage)
    }

    // swiftlint:disable:next function_body_length
    static let labelMap: [UInt32: String] = [
        // ── Letters A–Z ─────────────────────────────────────────────────────────
        0x04: "A",  0x05: "B",  0x06: "C",  0x07: "D",
        0x08: "E",  0x09: "F",  0x0A: "G",  0x0B: "H",
        0x0C: "I",  0x0D: "J",  0x0E: "K",  0x0F: "L",
        0x10: "M",  0x11: "N",  0x12: "O",  0x13: "P",
        0x14: "Q",  0x15: "R",  0x16: "S",  0x17: "T",
        0x18: "U",  0x19: "V",  0x1A: "W",  0x1B: "X",
        0x1C: "Y",  0x1D: "Z",

        // ── Numbers 1–9, 0 ──────────────────────────────────────────────────────
        0x1E: "1",  0x1F: "2",  0x20: "3",  0x21: "4",  0x22: "5",
        0x23: "6",  0x24: "7",  0x25: "8",  0x26: "9",  0x27: "0",

        // ── Special / Whitespace / Control ───────────────────────────────────────
        0x28: "Return",   0x29: "Esc",     0x2A: "Delete",  0x2B: "Tab",
        0x2C: "Space",

        // ── Symbols (US Layout) ──────────────────────────────────────────────────
        0x2D: "-",   0x2E: "=",   0x2F: "[",   0x30: "]",
        0x31: "\\",  0x32: "#",   0x33: ";",   0x34: "'",
        0x35: "`",   0x36: ",",   0x37: ".",   0x38: "/",

        // ── Caps Lock ────────────────────────────────────────────────────────────
        0x39: "⇪",

        // ── Function Keys F1–F12 ─────────────────────────────────────────────────
        0x3A: "F1",  0x3B: "F2",  0x3C: "F3",  0x3D: "F4",
        0x3E: "F5",  0x3F: "F6",  0x40: "F7",  0x41: "F8",
        0x42: "F9",  0x43: "F10", 0x44: "F11", 0x45: "F12",

        // ── Navigation / System Keys ────────────────────────────────────────────
        0x46: "PrtSc",  0x47: "ScrLk",  0x48: "Pause",
        0x49: "Ins",    0x4A: "Home",   0x4B: "PgUp",
        0x4C: "⌦",      0x4D: "End",    0x4E: "PgDn",

        // ── Arrow Keys ───────────────────────────────────────────────────────────
        0x4F: "→",  0x50: "←",  0x51: "↓",  0x52: "↑",

        // ── Numpad ───────────────────────────────────────────────────────────────
        0x53: "NmLk",    0x54: "Num/",   0x55: "Num*",
        0x56: "Num-",    0x57: "Num+",   0x58: "NumEnter",
        0x59: "Num1",    0x5A: "Num2",   0x5B: "Num3",
        0x5C: "Num4",    0x5D: "Num5",   0x5E: "Num6",
        0x5F: "Num7",    0x60: "Num8",   0x61: "Num9",
        0x62: "Num0",    0x63: "Num.",

        // ── Extended Function Keys F13–F24 ───────────────────────────────────────
        0x68: "F13", 0x69: "F14", 0x6A: "F15", 0x6B: "F16",
        0x6C: "F17", 0x6D: "F18", 0x6E: "F19", 0x6F: "F20",
        0x70: "F21", 0x71: "F22", 0x72: "F23", 0x73: "F24",

        // ── Modifier Keys (Left & Right disatukan per simbol) ────────────────────
        // Left
        0xE0: "⌃",   // Left Control
        0xE1: "⇧",   // Left Shift
        0xE2: "⌥",   // Left Option / Alt
        0xE3: "⌘",   // Left Command / GUI

        // Right (gunakan label yang sama agar tergabung di heatmap)
        0xE4: "⌃",   // Right Control
        0xE5: "⇧",   // Right Shift
        0xE6: "⌥",   // Right Option / Alt
        0xE7: "⌘",   // Right Command / GUI
    ]
}
