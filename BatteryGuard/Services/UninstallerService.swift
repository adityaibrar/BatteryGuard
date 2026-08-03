// UninstallerService.swift
// BatteryGuard — Service layer untuk scan & hapus file aplikasi
// Pure logic tanpa dependensi UI — bisa di-unit test secara independen

import Foundation
import AppKit

// MARK: - UninstallerService

/// Service yang menangani semua operasi I/O untuk fitur Uninstaller.
/// - Membaca metadata dari .app bundle
/// - Mencari file terkait di berbagai lokasi Library
/// - Memindahkan file terpilih ke Trash
actor UninstallerService {

    static let shared = UninstallerService()
    private init() {}

    // MARK: - Load App Metadata

    /// Baca metadata dari URL .app bundle yang di-drop user.
    /// - Returns: `AppInfo` jika valid .app bundle, `nil` jika bukan app atau tidak bisa dibaca.
    func loadApp(from url: URL) async -> AppInfo? {
        guard url.pathExtension.lowercased() == "app" else { return nil }

        let fm = FileManager.default

        // Baca bundle info
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return nil }

        // Nama tampilan — prioritaskan CFBundleDisplayName lalu CFBundleName lalu nama file
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        // Icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)

        // Ukuran bundle (rekursif)
        let bundleSize = directorySize(at: url, fm: fm)

        return AppInfo(
            url: url,
            bundleIdentifier: bundleId,
            displayName: displayName,
            icon: icon,
            bundleSizeBytes: bundleSize
        )
    }

    // MARK: - Scan Related Files

    /// Scan semua lokasi standar macOS untuk mencari file yang berkaitan
    /// dengan aplikasi berdasarkan bundle identifier dan nama app.
    /// - Returns: Array `AppFile` yang ditemukan, diurutkan per kategori.
    func scanRelatedFiles(for app: AppInfo) async -> [AppFile] {
        let fm = FileManager.default
        var results: [AppFile] = []

        // Selalu masukkan .app bundle itu sendiri sebagai item pertama
        let bundleFile = AppFile(
            url: app.url,
            category: .application,
            sizeBytes: app.bundleSizeBytes
        )
        results.append(bundleFile)

        // Token pencarian:
        // 1. Full bundle ID: "com.philandro.anydesk"
        // 2. Nama app lowercase: "anydesk"
        // 3. Bundle ID prefix (dua komponen pertama): "com.philandro"
        let bundleId = app.bundleIdentifier.lowercased()
        let appName  = app.displayName.lowercased()
        // Ekstrak 2 komponen pertama dari bundle ID sebagai prefix yang lebih luas
        let bundlePrefix: String = {
            let parts = bundleId.split(separator: ".")
            guard parts.count >= 2 else { return bundleId }
            return "\(parts[0]).\(parts[1])"
        }()

        let searchTokens = [bundleId, appName, bundlePrefix]

        // Kumpulan lokasi yang akan discan beserta kategorinya
        let scanLocations: [(category: AppFileCategory, paths: [String])] = buildScanLocations()

        for location in scanLocations {
            for basePath in location.paths {
                let baseURL = URL(fileURLWithPath: basePath)

                // Skip jika direktori tidak ada
                guard fm.fileExists(atPath: basePath) else { continue }

                // Cari file/folder yang namanya mengandung salah satu token
                let found = findMatchingItems(
                    in: baseURL,
                    tokens: searchTokens,
                    category: location.category,
                    fm: fm
                )
                results.append(contentsOf: found)
            }
        }

        // Deduplicate berdasarkan path (bisa overlap antar scan locations)
        var seen = Set<String>()
        let deduplicated = results.filter { file in
            let key = file.url.path
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // Urutkan: application dulu, lalu berdasarkan sortOrder kategori
        return deduplicated.sorted { a, b in
            a.category.sortOrder < b.category.sortOrder
        }
    }

    // MARK: - Move to Trash

    /// Pindahkan file yang dipilih ke Trash.
    ///
    /// Strategi dua lapis:
    /// 1. Coba `FileManager.trashItem` (cepat, tanpa dialog)
    /// 2. Jika gagal karena permission → fallback ke Finder via `osascript`
    ///    yang akan trigger dialog izin macOS secara otomatis.
    ///
    /// - Returns: Tuple `(succeeded, failed)` berisi URL yang berhasil/gagal dihapus.
    func moveToTrash(_ files: [AppFile]) async -> (succeeded: [URL], failed: [URL]) {
        var succeeded: [URL] = []
        var failed:    [URL] = []
        var needsElevated: [URL] = []

        // ── Pass 1: FileManager (untuk file user-accessible) ──────────────────
        for file in files {
            do {
                var resultURL: NSURL?
                try FileManager.default.trashItem(at: file.url, resultingItemURL: &resultURL)
                succeeded.append(file.url)
            } catch let error as NSError where isPermissionError(error) {
                // Permission denied → antri untuk elevated pass
                needsElevated.append(file.url)
            } catch {
                print("[UninstallerService] Gagal trash \(file.url.path): \(error)")
                failed.append(file.url)
            }
        }

        // ── Pass 2: Finder via osascript (untuk /Applications/, /Library/, dll.) ─
        if !needsElevated.isEmpty {
            let (elSucceeded, elFailed) = await trashViaFinder(urls: needsElevated)
            succeeded.append(contentsOf: elSucceeded)
            failed.append(contentsOf: elFailed)
        }

        return (succeeded, failed)
    }

    // MARK: - Elevated Trash via Finder (osascript)

    /// Gunakan Finder untuk memindahkan file ke Trash.
    /// Finder memiliki akses yang lebih luas dan akan meminta izin ke user
    /// via dialog macOS standar jika diperlukan (contoh: `/Applications/`, `/Library/`).
    private func trashViaFinder(urls: [URL]) async -> (succeeded: [URL], failed: [URL]) {
        var succeeded: [URL] = []
        var failed:    [URL] = []

        for url in urls {
            // Build AppleScript: tell Finder to move file to trash
            // Menggunakan POSIX file path untuk kompatibilitas penuh
            let escapedPath = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let script = """
            tell application "Finder"
                move POSIX file "\(escapedPath)" to trash
            end tell
            """

            let result = await runOsascript(script)

            if result {
                print("[UninstallerService] Berhasil trash via Finder: \(url.lastPathComponent)")
                succeeded.append(url)
            } else {
                // Coba fallback kedua: shell rm dengan sudo via osascript
                let shellResult = await trashViaShell(url: url)
                if shellResult {
                    succeeded.append(url)
                } else {
                    print("[UninstallerService] Semua metode gagal untuk: \(url.path)")
                    failed.append(url)
                }
            }
        }

        return (succeeded, failed)
    }

    /// Jalankan AppleScript menggunakan `osascript` process.
    /// Berjalan secara async tanpa blocking main thread.
    private func runOsascript(_ script: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            // Suppress stderr output
            process.standardError  = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Fallback terakhir: hapus via `rm` menggunakan AppleScript `do shell script`
    /// dengan `with administrator privileges` yang akan prompt password jika perlu.
    private func trashViaShell(url: URL) async -> Bool {
        let escapedPath = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "'\\''")

        let script = """
        do shell script "rm -rf '\(escapedPath)'" with administrator privileges
        """

        return await runOsascript(script)
    }

    /// Cek apakah error adalah permission denied (NSCocoaErrorDomain Code=513
    /// atau NSOSStatusErrorDomain Code=-5000 / -5001).
    private func isPermissionError(_ error: NSError) -> Bool {
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, 513):   return true  // Operation not permitted
        case (NSCocoaErrorDomain, 512):   return true  // File not found after permission
        case (NSPOSIXErrorDomain, 1):     return true  // EPERM
        case (NSPOSIXErrorDomain, 13):    return true  // EACCES
        default:
            // Cek underlying error
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                return isPermissionError(underlying)
            }
            return false
        }
    }

    // MARK: - Private Helpers

    /// Daftar lokasi standar macOS yang akan di-scan
    private func buildScanLocations() -> [(category: AppFileCategory, paths: [String])] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        return [
            (.preferences,     ["\(home)/Library/Preferences"]),
            (.appSupport,      [
                "\(home)/Library/Application Support",
                "/Library/Application Support"
            ]),
            (.caches,          [
                "\(home)/Library/Caches",
                "/Library/Caches"
            ]),
            (.logs,            [
                "\(home)/Library/Logs",
                "/Library/Logs"
            ]),
            (.containers,      ["\(home)/Library/Containers"]),
            (.groupContainers, ["\(home)/Library/Group Containers"]),
            (.launchAgents,    [
                "\(home)/Library/LaunchAgents",
                "/Library/LaunchAgents"
            ]),
            (.launchDaemons,   ["/Library/LaunchDaemons"]),
        ]
    }

    /// Scan shallow (satu level) di direktori `baseURL`,
    /// kembalikan item yang namanya match dengan salah satu token.
    private func findMatchingItems(
        in baseURL: URL,
        tokens: [String],
        category: AppFileCategory,
        fm: FileManager
    ) -> [AppFile] {
        var found: [AppFile] = []

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        for itemURL in contents {
            let name = itemURL.lastPathComponent.lowercased()

            // Cek apakah nama item mengandung salah satu token
            let isMatch = tokens.contains { token in
                name.contains(token)
            }

            guard isMatch else { continue }

            // Hitung ukuran
            var isDir: ObjCBool = false
            fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)
            let size: Int64 = isDir.boolValue
                ? directorySize(at: itemURL, fm: fm)
                : fileSize(at: itemURL, fm: fm)

            found.append(AppFile(
                url: itemURL,
                category: category,
                sizeBytes: size
            ))
        }

        return found
    }

    /// Hitung ukuran total direktori secara rekursif
    private func directorySize(at url: URL, fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  attrs.isRegularFile == true,
                  let size = attrs.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// Baca ukuran file tunggal
    private func fileSize(at url: URL, fm: FileManager) -> Int64 {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }
}
