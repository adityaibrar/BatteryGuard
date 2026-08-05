import Foundation
import CoreGraphics
import AppKit

let trusted = AXIsProcessTrusted()
print("[DIAGNOSE] AXIsProcessTrusted = \(trusted)")

if !trusted {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    print("[DIAGNOSE] PERMISSION BELUM aktif. Tambahkan Terminal di Accessibility Settings.")
    exit(1)
}

print("[DIAGNOSE] Permission aktif. Mencoba buat CGEventTap HID level...")

let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

if let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: { _, type, event, _ in
        if type == .scrollWheel {
            let isCont = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            let d1     = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let phase  = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            let mom    = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            let nsEv   = NSEvent(cgEvent: event)
            let prec   = nsEv?.hasPreciseScrollingDeltas ?? false
            print("[DIAGNOSE] scrollWheel isCont=\(isCont) d1=\(d1) phase=\(phase) mom=\(mom) prec=\(prec)")
        }
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
) {
    print("[DIAGNOSE] CGEventTap HID BERHASIL dibuat! Scroll dengan mouse fisik sekarang...")
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source!, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    CFRunLoopRun()
} else {
    print("[DIAGNOSE] GAGAL membuat HID tap. Mencoba session tap...")
    if let tap2 = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, type, event, _ in
            if type == .scrollWheel {
                let isCont = event.getIntegerValueField(.scrollWheelEventIsContinuous)
                let d1     = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                print("[DIAGNOSE] SESSION scrollWheel isCont=\(isCont) d1=\(d1)")
            }
            return Unmanaged.passUnretained(event)
        },
        userInfo: nil
    ) {
        print("[DIAGNOSE] Session tap BERHASIL. Scroll sekarang...")
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap2, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source!, .commonModes)
        CGEvent.tapEnable(tap: tap2, enable: true)
        CFRunLoopRun()
    } else {
        print("[DIAGNOSE] KEDUA TAP GAGAL!")
    }
}
