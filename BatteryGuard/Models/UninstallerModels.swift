// UninstallerModels.swift
// BatteryGuard — Domain model untuk fitur App Uninstaller
// Murni Swift structs tanpa dependensi UI atau framework eksternal

import Foundation
import AppKit

// MARK: - App File Category

/// Kategori lokasi file yang berkaitan dengan sebuah aplikasi di macOS
enum AppFileCategory: String, CaseIterable, Identifiable {
    case application     = "Application"
    case preferences     = "Preferences"
    case appSupport      = "Application Support"
    case caches          = "Caches"
    case logs            = "Logs"
    case containers      = "Containers"
    case groupContainers = "Group Containers"
    case launchAgents    = "Launch Agents"
    case launchDaemons   = "Launch Daemons"
    case other           = "Other"

    var id: String { rawValue }

    /// SF Symbol icon untuk tiap kategori
    var systemImage: String {
        switch self {
        case .application:     return "app.badge"
        case .preferences:     return "slider.horizontal.3"
        case .appSupport:      return "internaldrive"
        case .caches:          return "clock.arrow.circlepath"
        case .logs:            return "doc.text.below.ecg"
        case .containers:      return "shippingbox"
        case .groupContainers: return "shippingbox.fill"
        case .launchAgents:    return "bolt.horizontal"
        case .launchDaemons:   return "gearshape.2"
        case .other:           return "doc"
        }
    }

    /// Urutan tampil di UI
    var sortOrder: Int {
        switch self {
        case .application:     return 0
        case .preferences:     return 1
        case .appSupport:      return 2
        case .caches:          return 3
        case .logs:            return 4
        case .containers:      return 5
        case .groupContainers: return 6
        case .launchAgents:    return 7
        case .launchDaemons:   return 8
        case .other:           return 9
        }
    }
}

// MARK: - App File

/// Representasi satu file/folder yang berkaitan dengan sebuah aplikasi
struct AppFile: Identifiable {
    let id = UUID()

    /// Path absolut file/folder
    let url: URL

    /// Kategori lokasi file
    let category: AppFileCategory

    /// Ukuran dalam bytes (dihitung rekursif untuk folder)
    let sizeBytes: Int64

    /// Apakah file ini dipilih untuk dihapus (default: true)
    var isSelected: Bool = true

    // MARK: Computed

    var name: String { url.lastPathComponent }

    /// Path yang ditampilkan secara relatif (tilde untuk home dir)
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home)
            ? "~" + url.path.dropFirst(home.count)
            : url.path
    }

    /// Parent directory path untuk tampilan sub-label
    var parentDisplayPath: String {
        let parentURL = url.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return parentURL.path.hasPrefix(home)
            ? "~" + parentURL.path.dropFirst(home.count)
            : parentURL.path
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - App Info

/// Metadata lengkap dari aplikasi yang di-drop oleh user
struct AppInfo {
    /// Path ke .app bundle
    let url: URL

    /// Bundle identifier (contoh: com.philandro.anydesk)
    let bundleIdentifier: String

    /// Nama tampilan (contoh: AnyDesk)
    let displayName: String

    /// Icon aplikasi
    let icon: NSImage

    /// Ukuran .app bundle dalam bytes
    let bundleSizeBytes: Int64

    var formattedBundleSize: String {
        ByteCountFormatter.string(fromByteCount: bundleSizeBytes, countStyle: .file)
    }
}
