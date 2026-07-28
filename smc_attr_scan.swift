// smc_attr_scan.swift
// Scan SMC keys dengan dataAttributes + coba write untuk detect writable keys
// Jalankan: sudo swift smc_attr_scan.swift
import Foundation
import IOKit

typealias SMCBytes = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                      UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                      UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                      UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: (UInt8,UInt8,UInt8,UInt16,UInt8) = (0,0,0,0,0)
    var pLimitData: (UInt16,UInt16,UInt32,UInt32,UInt32) = (0,0,0,0,0)
    var keyInfo: (IOByteCount32,UInt32,UInt8) = (0,0,0)
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func codeToStr(_ c: UInt32) -> String {
    [24,16,8,0].compactMap { UnicodeScalar((c >> $0) & 0xff).map { Character($0) } }
               .reduce("") { $0 + String($1) }
}

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0 else { print("ERROR: AppleSMC tidak ditemukan"); exit(1) }
var conn: io_connect_t = 0
guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("ERROR: Gagal buka koneksi SMC — coba jalankan dengan sudo")
    exit(1)
}

func smcCall(_ input: inout SMCParamStruct) -> SMCParamStruct? {
    var output = SMCParamStruct()
    var outSize = MemoryLayout<SMCParamStruct>.stride
    let ret = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
    return (ret == kIOReturnSuccess) ? output : nil
}

// Test tulis ke key (safe test — baca dulu, tulis nilai yg sama, cek result)
func testWritable(_ keyStr: String) -> (writable: Bool, result: UInt8) {
    // 1. Dapatkan keyInfo
    var infoInput = SMCParamStruct()
    infoInput.key = fourCC(keyStr)
    infoInput.data8 = 9
    guard let infoOut = smcCall(&infoInput), infoOut.result == 0 else { return (false, 255) }
    let dataSize = infoOut.keyInfo.0

    // 2. Baca nilai saat ini
    var readInput = SMCParamStruct()
    readInput.key = fourCC(keyStr)
    readInput.keyInfo.0 = dataSize
    readInput.data8 = 5
    guard let readOut = smcCall(&readInput), readOut.result == 0 else { return (false, 254) }

    // 3. Tulis nilai yg sama persis (safe — tidak mengubah apapun)
    var writeInput = SMCParamStruct()
    writeInput.key = fourCC(keyStr)
    writeInput.bytes = readOut.bytes  // tulis nilai saat ini
    writeInput.keyInfo.0 = dataSize
    writeInput.data8 = 6  // kSMCWriteKey
    guard let writeOut = smcCall(&writeInput) else { return (false, 253) }

    return (writeOut.result == 0, writeOut.result)
}

// Target keys untuk charge control
let chargeKeys = [
    "CHIB", "CHIC", "CHIE", "CHIL", "CHIO",
    "CHOC", "CHSW", "CHLT", "BCBL", "BCLM",
    "ACLC", "CH0B", "CH0I", "CH0C",
    "B0AC", "B0AV", "B0RM"
]

print("SMC Charge Key Analysis — M4 Mac")
print("================================")
print(String(format: "%-6s  %-8s  %-6s  %-4s  %-8s  %-12s", "Key", "DataType", "Size", "Attr", "Value", "Writable?"))
print(String(repeating: "-", count: 55))

for keyStr in chargeKeys {
    var infoInput = SMCParamStruct()
    infoInput.key = fourCC(keyStr)
    infoInput.data8 = 9
    guard let infoOut = smcCall(&infoInput), infoOut.result == 0 else {
        print(String(format: "%-6s  %-8s  %-6s  %-4s  %-8s  %@",
              keyStr, "-", "-", "-", "-", "❌ NOT FOUND"))
        continue
    }

    let dataSize = infoOut.keyInfo.0
    let dataType = infoOut.keyInfo.1
    let dataAttr = infoOut.keyInfo.2

    let typeStr = codeToStr(dataType)

    // Baca nilai
    var readInput = SMCParamStruct()
    readInput.key = fourCC(keyStr)
    readInput.keyInfo.0 = dataSize
    readInput.data8 = 5
    let readResult = smcCall(&readInput)
    let valueStr: String
    if let r = readResult, r.result == 0 {
        valueStr = String(format: "0x%02X %02X %02X %02X", r.bytes.0, r.bytes.1, r.bytes.2, r.bytes.3)
    } else {
        valueStr = "[unreadable]"
    }

    // Test write
    let (writable, writeResult) = testWritable(keyStr)
    let writableStr = writable
        ? "✅ WRITABLE"
        : "❌ result=\(writeResult)"

    // dataAttr bits: 0x10=Read, 0x20=Write, 0x40=Volatile
    let attrStr = String(format: "0x%02X", dataAttr)

    print(String(format: "%-6s  %-8s  %-6d  %-4s  \(valueStr)  \(writableStr)",
          keyStr, typeStr, Int(dataSize), attrStr))
}

print("\nKeterangan dataAttr:")
print("  0x10 = Readable")
print("  0x20 = Writable via normal path")  
print("  0x40 = Event-driven / Volatile")
print("  0xC0 = Non-volatile persistent")

IOServiceClose(conn)
