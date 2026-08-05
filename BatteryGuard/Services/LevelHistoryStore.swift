// LevelHistoryStore.swift
// BatteryGuard — Persistensi battery level history (24 jam)
// Menyimpan satu entry per 5 menit untuk efisiensi, auto-prune data > 24 jam

import Foundation

// MARK: - Level Entry

/// Satu titik data level baterai yang di-persist
struct LevelEntry: Codable, Identifiable, Equatable {
    // Key format: "yyyy-MM-dd HH:mm" dalam resolusi 5 menit (menit di-round ke 5)
    var id: String { key }
    var key: String
    var timestamp: Date
    var percentage: Int
}

// MARK: - LevelHistoryStore

/// Menyimpan histori level baterai ke JSON di Application Support
/// Satu entri per 5 menit, prune otomatis data lebih dari 24 jam
final class LevelHistoryStore: ObservableObject {

    static let shared = LevelHistoryStore()

    // MARK: - Private

    private let filename = "level_history.json"
    private var entries: [LevelEntry] = []
    private let queue = DispatchQueue(label: "com.ibrardev.Ozone.LevelHistory", qos: .utility)

    private var lastRecordedKey: String = ""

    private var fileURL: URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let ozoneDir = appSupport?.appendingPathComponent("Ozone")
        if let dir = ozoneDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return ozoneDir?.appendingPathComponent(filename)
    }

    @Published var points: [LevelEntry] = []

    private init() {
        loadFromDisk()
        pruneOlderThan24Hours()
    }

    // MARK: - Public API

    /// Record battery level — hanya simpan jika slot 5 menit berbeda dari yang terakhir
    func record(_ percentage: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let key = self.currentKey()
            // Skip jika key sama dengan yang terakhir (belum masuk slot 5 menit berikutnya)
            guard key != self.lastRecordedKey else { return }

            self.lastRecordedKey = key

            // Update entry jika key sudah ada (update nilai), atau insert baru
            self.entries.removeAll { $0.key == key }

            let entry = LevelEntry(key: key, timestamp: Date(), percentage: percentage)
            self.entries.append(entry)
            self.entries.sort { $0.key < $1.key }

            // Auto-prune
            self.pruneOlderThan24HoursInternal()

            self.saveToDisk()

            // Publish snapshot ke main thread
            let snapshot = self.entries
            DispatchQueue.main.async {
                self.points = snapshot
            }
        }
    }

    /// Ambil semua data 24 jam terakhir (sudah di-sort ascending)
    func historyForLast24Hours() -> [LevelEntry] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return entries.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Prune

    func pruneOlderThan24Hours() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pruneOlderThan24HoursInternal()
            self.saveToDisk()
            let snapshot = self.entries
            DispatchQueue.main.async {
                self.points = snapshot
            }
        }
    }

    private func pruneOlderThan24HoursInternal() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        entries.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([LevelEntry].self, from: data)
        else { return }

        entries = loaded.sorted { $0.key < $1.key }

        // Sync ke @Published (init dipanggil dari main queue)
        DispatchQueue.main.async { [weak self] in
            self?.points = self?.entries ?? []
        }
    }

    private func saveToDisk() {
        guard let url = fileURL else { return }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Key Generation

    /// Key format: "yyyy-MM-dd HH:mm" dengan menit di-round ke kelipatan 5
    private func currentKey() -> String {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date()
        )
        if let minute = components.minute {
            components.minute = (minute / 5) * 5
        }
        components.second = 0
        let roundedDate = Calendar.current.date(from: components) ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: roundedDate)
    }
}
