// SMCController.swift
// BatteryGuardHelper — SMC wrapper + software-based charge limiter
//
// MEKANISME CHARGE LIMITING DI APPLE SILICON (M-series):
//
// Apple Silicon TIDAK mendukung threshold persentase bebas via SMC seperti Intel (BCLM).
// Cara yang dipakai AlDente dan tool-tool sejenis:
//
//   1. Monitor battery percentage secara periodik via IOKit AppleSmartBattery
//   2. Saat battery% >= limit → tulis SMC key "CH0B" = 0x02 (inhibit charging)
//   3. Saat battery% < limit - hysteresis → tulis SMC key "CH0B" = 0x00 (allow charging)
//
// CH0B (Charge Hold 0 Bitmap):
//   0x00 = charging ALLOWED (normal)
//   0x02 = charging INHIBITED (stop charging, tapi Mac tetap pakai daya dari charger)
//
// Ini adalah software approach — helper harus terus berjalan sebagai daemon.
// Jika Mac dimatikan, limit tidak akan aktif hingga daemon start kembali.

import Foundation
import IOKit

// MARK: - Type Aliases (sesuai AppleSMC.kext internal)

typealias FourCharCode = UInt32
typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

// MARK: - SMCParamStruct
// Harus persis 80 bytes — constraint dari driver AppleSMC.kext

struct SMCParamStruct {
    enum Selector: UInt8 {
        case kSMCHandleYPCEvent  = 2
        case kSMCReadKey         = 5
        case kSMCWriteKey        = 6
        case kSMCGetKeyFromIndex = 8
        case kSMCGetKeyInfo      = 9
    }
    enum Result: UInt8 {
        case kSMCSuccess     = 0
        case kSMCError       = 1
        case kSMCKeyNotFound = 132
    }
    struct SMCVersion {
        var major: CUnsignedChar    = 0
        var minor: CUnsignedChar    = 0
        var build: CUnsignedChar    = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    struct SMCPLimitData {
        var version: UInt16   = 0
        var length: UInt16    = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    struct SMCKeyInfoData {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32        = 0
        var dataAttributes: UInt8   = 0
    }
    var key: UInt32         = 0
    var vers                = SMCVersion()
    var pLimitData          = SMCPLimitData()
    var keyInfo             = SMCKeyInfoData()
    var padding: UInt16     = 0
    var result: UInt8       = 0
    var status: UInt8       = 0
    var data8: UInt8        = 0
    var data32: UInt32      = 0
    var bytes: SMCBytes     = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

// MARK: - FourCharCode Helpers

private func fourCC(_ str: String) -> FourCharCode {
    assert(str.count == 4)
    return str.utf8.reduce(0) { $0 << 8 | UInt32($1) }
}

private func fourCCToString(_ code: FourCharCode) -> String {
    [24, 16, 8, 0].compactMap { shift -> Character? in
        UnicodeScalar((code >> shift) & 0xff).map { Character($0) }
    }.reduce("") { $0 + String($1) }
}

// MARK: - SMCController

/// Thread-safe, low-level wrapper untuk AppleSMC.kext via IOKit.
/// Setiap operasi buka koneksi, baca/tulis, lalu tutup agar tidak ada resource leak.
final class SMCController {

    enum SMCError: LocalizedError {
        case driverNotFound
        case failedToOpen
        case keyNotFound(String)
        case notPrivileged
        case failed(kIOReturn: kern_return_t, smcResult: UInt8)

        var errorDescription: String? {
            switch self {
            case .driverNotFound:   return "AppleSMC driver tidak ditemukan"
            case .failedToOpen:     return "Gagal membuka koneksi ke AppleSMC"
            case .keyNotFound(let k): return "SMC key '\(k)' tidak ada di Mac ini"
            case .notPrivileged:    return "Butuh root privileges untuk akses SMC"
            case .failed(let r, let s): return "SMC error (kIOReturn=0x\(String(r, radix: 16)), result=\(s))"
            }
        }
    }

    private var connection: io_connect_t = 0

    // MARK: Lifecycle

    func open() throws {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        let ret = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard ret == kIOReturnSuccess else { throw SMCError.failedToOpen }
    }

    func close() {
        IOServiceClose(connection)
        connection = 0
    }

    // MARK: Read / Write

    func readByte(_ key: String) throws -> UInt8 {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCParamStruct.Selector.kSMCReadKey.rawValue
        let out = try call(&input)
        return out.bytes.0
    }

    func writeByte(_ key: String, value: UInt8) throws {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.bytes.0 = value
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue
        _ = try call(&input)
        NSLog("[SMC] Wrote 0x%02X → key '%@'", value, key)
    }

    // MARK: Private

    private func keyInfo(_ key: String) throws -> SMCParamStruct.SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue
        return try call(&input).keyInfo
    }

    private func call(_ input: inout SMCParamStruct,
                      selector: SMCParamStruct.Selector = .kSMCHandleYPCEvent) throws -> SMCParamStruct {
        assert(MemoryLayout<SMCParamStruct>.stride == 80,
               "SMCParamStruct harus 80 bytes! Actual: \(MemoryLayout<SMCParamStruct>.stride)")
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let ret = IOConnectCallStructMethod(connection, UInt32(selector.rawValue),
                                           &input, MemoryLayout<SMCParamStruct>.stride,
                                           &output, &outSize)
        switch (ret, output.result) {
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCSuccess.rawValue):
            return output
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCKeyNotFound.rawValue):
            throw SMCError.keyNotFound(fourCCToString(input.key))
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.failed(kIOReturn: ret, smcResult: output.result)
        }
    }
}

// MARK: - BatteryReader

/// Membaca persentase baterai saat ini langsung dari IOKit AppleSmartBattery.
/// Menggunakan CurrentCapacity (0–100 pada Apple Silicon) — sama seperti yang macOS tampilkan.
final class BatteryReader {
    static func currentPercentage() -> Int? {
        return readBatteryProperty("CurrentCapacity") as? Int
    }

    static func isCharging() -> Bool {
        return readBatteryProperty("IsCharging") as? Bool ?? false
    }

    /// Helper: baca satu property dari AppleSmartBattery via IOKit
    private static func readBatteryProperty(_ key: String) -> AnyObject? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        // IORegistryEntryCreateCFProperty — lebih efisien, baca satu key saja
        return IORegistryEntryCreateCFProperty(service, key as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

// MARK: - ChargeMonitor (core charge limiter logic)

/// Implementasi software charge limiter menggunakan pendekatan yang sama dengan AlDente.
///
/// ## Cara Kerja
/// 1. Polling battery % setiap `pollInterval` detik
/// 2. Jika battery% >= limit → tulis `CH0B = 0x02` (inhibit charging)
/// 3. Jika battery% <= limit - hysteresis → tulis `CH0B = 0x00` (allow charging)
///
/// Hysteresis mencegah toggling terlalu cepat saat baterai tepat di angka limit.
/// Default hysteresis = 2% (stop di 75%, start lagi di 73%).
final class ChargeMonitor {

    // MARK: - Constants

    /// SMC key untuk mengendalikan charging pada Apple Silicon
    /// CH0B = Charge Hold 0 Bitmap
    ///   0x00 = allow charging (normal)
    ///   0x02 = inhibit charging (stop arus ke baterai, tapi Mac tetap pakai charger)
    private static let chargeInhibitKey = "CH0B"
    private static let chargeInhibitOn: UInt8  = 0x02
    private static let chargeInhibitOff: UInt8 = 0x00

    // MARK: - State

    private let smc = SMCController()
    private var timer: DispatchSourceTimer?
    private var currentLimit: Int = 100
    private var isInhibiting: Bool = false

    /// Berapa persen di bawah limit sebelum charging diizinkan kembali
    /// Default 2% → set 75% berarti charging berhenti di 75%, start lagi di 73%
    var hysteresis: Int = 2

    /// Interval polling dalam detik — 5 detik agar responsif saat charging cepat
    var pollInterval: TimeInterval = 5

    // MARK: - Public API

    /// Mulai monitoring dan terapkan limit
    func startMonitoring(limit: Int) {
        currentLimit = limit
        isInhibiting = false

        NSLog("[ChargeMonitor] Start monitoring — limit: %d%%, hysteresis: %d%%, poll: %.0fs",
              limit, hysteresis, pollInterval)

        // Langsung cek kondisi sekarang tanpa menunggu interval
        checkAndEnforce()

        // Setup periodic timer di background queue
        let queue = DispatchQueue(label: "com.ibrardev.BatteryGuard.chargeMonitor",
                                  qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.checkAndEnforce() }
        t.resume()
        timer = t
    }

    /// Update limit tanpa restart monitoring
    func updateLimit(_ limit: Int) {
        NSLog("[ChargeMonitor] Limit diubah: %d%% → %d%%", currentLimit, limit)
        currentLimit = limit
        // Langsung enforce dengan limit baru
        checkAndEnforce()
    }

    /// Hentikan monitoring dan izinkan charging normal
    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        // Pastikan charging diizinkan kembali setelah stop
        setChargeInhibit(false)
        isInhibiting = false
        NSLog("[ChargeMonitor] Monitoring dihentikan, charging diizinkan kembali")
    }

    // MARK: - Core Logic

    private func checkAndEnforce() {
        guard let currentPct = BatteryReader.currentPercentage() else {
            NSLog("[ChargeMonitor] ⚠️ Tidak bisa baca battery percentage, skip cycle")
            return
        }

        let charging = BatteryReader.isCharging()
        NSLog("[ChargeMonitor] Poll: battery=%d%%, limit=%d%%, inhibiting=%@, charging=%@",
              currentPct, currentLimit, isInhibiting ? "YES" : "NO", charging ? "YES" : "NO")

        if currentPct >= currentLimit {
            // Baterai mencapai atau melewati limit — STOP charging
            if !isInhibiting {
                NSLog("[ChargeMonitor] 🛑 Battery %d%% >= limit %d%% → INHIBIT charging",
                      currentPct, currentLimit)
            }
            // Selalu tulis ulang inhibit (idempotent) untuk memastikan tidak ada drift
            setChargeInhibit(true)
            isInhibiting = true

        } else if currentPct <= (currentLimit - hysteresis) && isInhibiting {
            // Baterai sudah turun di bawah (limit - hysteresis) — ALLOW charging kembali
            NSLog("[ChargeMonitor] ✅ Battery %d%% <= %d%% (limit-hysteresis) → ALLOW charging",
                  currentPct, currentLimit - hysteresis)
            setChargeInhibit(false)
            isInhibiting = false
        }
        // Jika di antara keduanya → tidak ubah state (hysteresis zone)
    }

    private func setChargeInhibit(_ inhibit: Bool) {
        let value: UInt8 = inhibit ? Self.chargeInhibitOn : Self.chargeInhibitOff
        do {
            try smc.open()
            defer { smc.close() }
            try smc.writeByte(Self.chargeInhibitKey, value: value)

            // Verifikasi: baca balik CH0B untuk konfirmasi berhasil
            if let readback = try? smc.readByte(Self.chargeInhibitKey) {
                NSLog("[ChargeMonitor] CH0B write=0x%02X, readback=0x%02X (%@)",
                      value, readback, inhibit ? "INHIBIT" : "ALLOW")
                if readback != value {
                    NSLog("[ChargeMonitor] ⚠️ CH0B readback mismatch! Ditulis 0x%02X tapi terbaca 0x%02X",
                          value, readback)
                }
            } else {
                NSLog("[ChargeMonitor] CH0B = 0x%02X (%@) — readback tidak tersedia",
                      value, inhibit ? "INHIBIT" : "ALLOW")
            }
        } catch SMCController.SMCError.keyNotFound {
            // CH0B tidak ada — mungkin Mac yang sangat baru atau Intel
            // Coba fallback ke CHWA untuk Apple Silicon
            NSLog("[ChargeMonitor] ⚠️ CH0B tidak ditemukan, coba CHWA fallback")
            tryChwaFallback(inhibit: inhibit)
        } catch SMCController.SMCError.notPrivileged {
            NSLog("[ChargeMonitor] ❌ NOT PRIVILEGED — helper tidak berjalan sebagai root!")
        } catch {
            NSLog("[ChargeMonitor] ❌ Gagal set CH0B: %@", error.localizedDescription)
        }
    }

    private func tryChwaFallback(inhibit: Bool) {
        do {
            try smc.open()
            defer { smc.close() }
            // CHWA: 1 = enable ~80% limit, 0 = disable limit
            try smc.writeByte("CHWA", value: inhibit ? 1 : 0)
            NSLog("[ChargeMonitor] CHWA fallback: %d", inhibit ? 1 : 0)
        } catch {
            NSLog("[ChargeMonitor] ❌ CHWA fallback juga gagal: %@", error.localizedDescription)
        }
    }
}
