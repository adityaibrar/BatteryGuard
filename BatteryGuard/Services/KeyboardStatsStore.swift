// KeyboardStatsStore.swift
// BatteryGuard — Persistence layer untuk keyboard key press statistics
// Data disimpan akumulatif ke JSON file di Application Support, tidak pernah hilang
// kecuali user sengaja reset.

import Foundation

// MARK: - KeyboardStatsStore

final class KeyboardStatsStore {

    static let shared = KeyboardStatsStore()

    // MARK: - Codable Data Structure

    /// Statistik satu perangkat keyboard
    struct DeviceStats: Codable {
        var deviceName: String
        var isInternal: Bool
        /// keyLabel → total press count (akumulatif sepanjang waktu)
        var keyCounts: [String: Int]
        var lastUpdated: Date
        var firstSeen: Date

        /// Total semua keypress pada device ini
        var totalPresses: Int {
            keyCounts.values.reduce(0, +)
        }
    }

    // MARK: - Private State

    /// deviceID → DeviceStats
    private(set) var data: [String: DeviceStats] = [:]

    /// Antrian serial untuk operasi disk (mencegah race condition)
    private let queue = DispatchQueue(label: "com.ibrardev.Ozone.KeyboardStatsStore", qos: .utility)

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ozoneDir = appSupport.appendingPathComponent("Ozone", isDirectory: true)
        let oldDir = appSupport.appendingPathComponent("BatteryGuard", isDirectory: true)

        // Buat direktori jika belum ada
        try? FileManager.default.createDirectory(at: ozoneDir, withIntermediateDirectories: true)

        let newFile = ozoneDir.appendingPathComponent("keyboard_stats.json")
        let oldFile = oldDir.appendingPathComponent("keyboard_stats.json")

        // Migrasi data lama dari BatteryGuard jika file baru belum ada
        if !FileManager.default.fileExists(atPath: newFile.path),
           FileManager.default.fileExists(atPath: oldFile.path) {
            try? FileManager.default.copyItem(at: oldFile, to: newFile)
        }

        return newFile
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        load()
    }

    // MARK: - Load

    func load() {
        queue.async { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }

            do {
                let raw = try Data(contentsOf: self.fileURL)
                let decoded = try self.decoder.decode([String: DeviceStats].self, from: raw)
                DispatchQueue.main.async {
                    self.data = decoded
                }
                print("[KeyboardStatsStore] ✅ Data loaded — \(decoded.count) device(s), file: \(self.fileURL.lastPathComponent)")
            } catch {
                print("[KeyboardStatsStore] ⚠️ Gagal load data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Save (debounced via async queue)

    func save() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let encoded = try self.encoder.encode(self.data)
                try encoded.write(to: self.fileURL, options: .atomic)
                print("[KeyboardStatsStore] 💾 Data saved — \(self.data.count) device(s)")
            } catch {
                print("[KeyboardStatsStore] ❌ Gagal save data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Write Operations

    /// Catat 1 penekanan tombol untuk device & key tertentu (dipanggil dari IOHIDManager callback)
    func increment(deviceID: String, deviceName: String, isInternal: Bool, keyLabel: String) {
        // Operasi dilakukan di main thread karena dipanggil dari service setelah dispatch ke main
        if data[deviceID] == nil {
            data[deviceID] = DeviceStats(
                deviceName: deviceName,
                isInternal: isInternal,
                keyCounts: [:],
                lastUpdated: Date(),
                firstSeen: Date()
            )
        }

        data[deviceID]?.keyCounts[keyLabel, default: 0] += 1
        data[deviceID]?.lastUpdated = Date()
    }

    /// Simpan data ke disk (dipanggil berkala atau saat app tutup)
    func persist() {
        save()
    }

    /// Reset counter satu device (data device lain tidak terpengaruh)
    func reset(deviceID: String) {
        data[deviceID]?.keyCounts = [:]
        data[deviceID]?.lastUpdated = Date()
        save()
        print("[KeyboardStatsStore] 🗑 Reset device: \(deviceID)")
    }

    /// Reset semua data semua device
    func resetAll() {
        for key in data.keys {
            data[key]?.keyCounts = [:]
            data[key]?.lastUpdated = Date()
        }
        save()
        print("[KeyboardStatsStore] 🗑 Reset semua device")
    }

    // MARK: - Read Helpers

    /// Total semua keypress pada device tertentu
    func totalPresses(for deviceID: String) -> Int {
        data[deviceID]?.totalPresses ?? 0
    }

    /// Jumlah unique key yang pernah ditekan pada device tertentu
    func uniqueKeyCount(for deviceID: String) -> Int {
        data[deviceID]?.keyCounts.filter { $0.value > 0 }.count ?? 0
    }

    /// Key yang paling sering ditekan pada device tertentu
    func topKey(for deviceID: String) -> KeyPressEntry? {
        topKeys(for: deviceID, limit: 1).first
    }

    /// Top N keys terurut descending (paling sering di index 0)
    func topKeys(for deviceID: String, limit: Int = 10) -> [KeyPressEntry] {
        guard let counts = data[deviceID]?.keyCounts else { return [] }
        return counts
            .filter { $0.value > 0 }
            .map { KeyPressEntry(id: $0.key, label: $0.key, count: $0.value) }
            .sorted()
            .prefix(limit)
            .map { $0 }
    }

    /// Semua key entries terurut descending (untuk full list / heatmap)
    func allKeys(for deviceID: String) -> [KeyPressEntry] {
        guard let counts = data[deviceID]?.keyCounts else { return [] }
        return counts
            .filter { $0.value > 0 }
            .map { KeyPressEntry(id: $0.key, label: $0.key, count: $0.value) }
            .sorted()
    }

    /// Press count untuk key tertentu pada device tertentu
    func count(for keyLabel: String, deviceID: String) -> Int {
        data[deviceID]?.keyCounts[keyLabel] ?? 0
    }

    /// Nama device untuk ditampilkan
    func deviceName(for deviceID: String) -> String {
        data[deviceID]?.deviceName ?? deviceID
    }
}
