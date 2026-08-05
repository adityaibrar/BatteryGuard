// CycleHistoryStore.swift
// BatteryGuard — Persistensi histori cycle count untuk chart Battery Cycles

import Foundation

// MARK: - Cycle Count Entry

/// Satu entri histori: tanggal + cycle count
struct CycleCountEntry: Codable, Identifiable, Equatable {
    var id: String { dateKey }
    /// Key format: "yyyy-MM-dd"
    var dateKey: String
    /// Cycle count yang tercatat pada hari itu
    var cycleCount: Int
    /// Timestamp actual pencatatan
    var recordedAt: Date

    var date: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateKey) ?? recordedAt
    }
}

// MARK: - CycleHistoryStore

/// Menyimpan histori cycle count ke JSON di Application Support
/// Satu entri per hari (dedup otomatis)
final class CycleHistoryStore {

    static let shared = CycleHistoryStore()

    // MARK: - Private

    private let filename = "cycle_history.json"
    private var entries: [CycleCountEntry] = []
    private let queue = DispatchQueue(label: "com.ibrardev.Ozone.CycleHistory", qos: .utility)

    private var fileURL: URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let ozoneDir = appSupport?.appendingPathComponent("Ozone")
        if let dir = ozoneDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return ozoneDir?.appendingPathComponent(filename)
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Rekam cycle count untuk hari ini (dedup: satu per hari)
    func recordCycleCount(_ count: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let todayKey = self.todayKey()

            // Hapus entri lama untuk hari ini jika ada
            self.entries.removeAll { $0.dateKey == todayKey }

            let entry = CycleCountEntry(
                dateKey: todayKey,
                cycleCount: count,
                recordedAt: Date()
            )
            self.entries.append(entry)
            self.entries.sort { $0.dateKey < $1.dateKey }

            self.saveToDisk()
        }
    }

    /// Ambil histori untuk N hari terakhir
    func historyForLast(_ days: Int) -> [CycleCountEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffKey = dateToKey(cutoff)
        return entries.filter { $0.dateKey >= cutoffKey }
    }

    /// Semua entri yang tersimpan
    var allEntries: [CycleCountEntry] { entries }

    /// Hapus histori lebih dari N hari (cleanup otomatis)
    func pruneOlderThan(_ days: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let cutoffKey = self.dateToKey(cutoff)
            self.entries.removeAll { $0.dateKey < cutoffKey }
            self.saveToDisk()
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([CycleCountEntry].self, from: data)
        else { return }

        entries = loaded.sorted { $0.dateKey < $1.dateKey }
    }

    private func saveToDisk() {
        guard let url = fileURL else { return }

        // Buat direktori jika belum ada
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Date Helpers

    private func todayKey() -> String {
        dateToKey(Date())
    }

    private func dateToKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
