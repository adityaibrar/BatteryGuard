// UninstallerViewModel.swift
// BatteryGuard — ViewModel untuk fitur App Uninstaller

import Foundation
import AppKit
import SwiftUI

// MARK: - Uninstall Summary

/// Ringkasan hasil uninstall yang ditampilkan di halaman sukses
struct UninstallSummary {
    let appName: String
    let appIcon: NSImage
    let deletedCount: Int
    let deletedSizeFormatted: String
    let failedCount: Int
}

// MARK: - UninstallerViewModel

@MainActor
final class UninstallerViewModel: ObservableObject {

    // MARK: Published State

    /// Info app yang sedang di-uninstall (nil = belum ada app di-drop)
    @Published var appInfo: AppInfo?

    /// Daftar file terkait yang ditemukan
    @Published var files: [AppFile] = []

    /// Sedang dalam proses scan
    @Published var isScanning: Bool = false

    /// Sedang dalam proses memindahkan ke Trash
    @Published var isMovingToTrash: Bool = false

    /// Drag is currently hovering over drop zone
    @Published var isDraggingOver: Bool = false

    /// Tampilkan halaman sukses setelah uninstall selesai
    @Published var isShowingSuccess: Bool = false

    /// Ringkasan hasil uninstall (diisi saat isShowingSuccess = true)
    @Published var uninstallSummary: UninstallSummary?

    /// Pesan error untuk ditampilkan ke user
    @Published var errorMessage: String?

    // MARK: Computed Properties

    /// File yang dipilih oleh user
    var selectedFiles: [AppFile] {
        files.filter { $0.isSelected }
    }

    var selectedCount: Int { selectedFiles.count }
    var totalCount: Int { files.count }

    /// Total ukuran file yang dipilih dalam bytes
    var selectedTotalSizeBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedTotalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: selectedTotalSizeBytes, countStyle: .file)
    }

    /// Footer label: "2 of 3 selected"
    var selectionLabel: String {
        "\(selectedCount) of \(totalCount) selected"
    }

    /// Grouping file per kategori untuk ditampilkan di List dengan section
    var filesByCategory: [(category: AppFileCategory, files: [AppFile])] {
        let grouped = Dictionary(grouping: files, by: { $0.category })
        return AppFileCategory.allCases
            .compactMap { category -> (AppFileCategory, [AppFile])? in
                guard let items = grouped[category], !items.isEmpty else { return nil }
                return (category, items)
            }
            .sorted { $0.0.sortOrder < $1.0.sortOrder }
    }

    // MARK: - Drop Handler

    /// Dipanggil saat user men-drop file ke drop zone.
    /// Validasi bahwa drop adalah .app bundle lalu mulai scan.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Minta URL dari provider
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { [weak self] item, error in
                guard let self = self else { return }
                var url: URL?

                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let loadedURL = item as? URL {
                    url = loadedURL
                }

                guard let validURL = url else { return }

                Task { @MainActor in
                    await self.loadAndScan(url: validURL)
                }
            }
            return true
        }
        return false
    }

    /// Dipanggil saat user drop URL langsung (dari onDrop dengan .fileURL)
    func handleDropURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            await loadAndScan(url: url)
        }
    }

    // MARK: - Toggle Selection

    /// Toggle pilihan satu file berdasarkan ID
    func toggleFile(id: UUID) {
        guard let idx = files.firstIndex(where: { $0.id == id }) else { return }
        files[idx].isSelected.toggle()
    }

    /// Pilih semua file
    func selectAll() {
        for idx in files.indices {
            files[idx].isSelected = true
        }
    }

    /// Hapus semua pilihan (deselect semua)
    func deselectAll() {
        for idx in files.indices {
            files[idx].isSelected = false
        }
    }

    // MARK: - Move to Trash

    func moveSelectedToTrash() {
        guard !selectedFiles.isEmpty else { return }
        let toDelete = selectedFiles

        // Simpan data sebelum operasi (akan hilang saat reset)
        let currentApp   = self.appInfo
        let totalSize    = self.selectedTotalSizeFormatted
        let selectedCount = self.selectedCount

        isMovingToTrash = true
        errorMessage    = nil

        Task {
            let result = await UninstallerService.shared.moveToTrash(toDelete)

            self.isMovingToTrash = false

            if !result.succeeded.isEmpty {
                // Ada yang berhasil (full atau partial) → tampilkan halaman sukses
                self.uninstallSummary = UninstallSummary(
                    appName: currentApp?.displayName ?? "Aplikasi",
                    appIcon: currentApp?.icon ?? NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)!,
                    deletedCount: result.succeeded.count,
                    deletedSizeFormatted: totalSize,
                    failedCount: result.failed.count
                )
                // Bersihkan list & info app (tapi JANGAN reset sukses state)
                self.appInfo = nil
                self.files   = []
                self.errorMessage = nil
                self.isDraggingOver = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isShowingSuccess = true
                }
            } else {
                // Semua gagal → tampilkan error, tetap di halaman file list
                self.errorMessage = "Semua file gagal dihapus. Pastikan tidak ada proses yang sedang berjalan."
            }
        }
    }

    // MARK: - Reset

    /// Kembalikan ke state awal (drop zone kosong)
    func reset() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowingSuccess  = false
        }
        uninstallSummary  = nil
        appInfo           = nil
        files             = []
        errorMessage      = nil
        isDraggingOver    = false
    }

    // MARK: - Private

    private func loadAndScan(url: URL) async {
        // Validasi ekstensi
        guard url.pathExtension.lowercased() == "app" else {
            errorMessage = "Drop sebuah file .app ke area ini."
            return
        }

        isScanning    = true
        errorMessage  = nil
        appInfo       = nil
        files         = []

        // Load metadata
        guard let info = await UninstallerService.shared.loadApp(from: url) else {
            isScanning   = false
            errorMessage = "Tidak bisa membaca informasi aplikasi. Pastikan file adalah .app yang valid."
            return
        }

        appInfo = info

        // Scan file terkait
        let found = await UninstallerService.shared.scanRelatedFiles(for: info)
        files     = found
        isScanning = false
    }
}
