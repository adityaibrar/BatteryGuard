// ResponsibleProcess.swift
// BatteryGuard — Resolusi Process ID & Kepemilikan Aplikasi untuk Volume Mixer

import AppKit
import Darwin

/// Memetakan helper / worker process (misal Chromium/Brave Audio Service, WebKit helper)
/// ke aplikasi induk utama (UI App) serta menyediakan nama dan ikon aplikasi.
enum ResponsibleProcess {
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    /// `responsibility_get_pid_responsible_for_pid` dari libsystem kernel macOS
    private static let resolve: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */,
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    /// Mengembalikan PID yang bertanggung jawab atas proses ini
    static func owner(of pid: pid_t) -> pid_t {
        guard let resolve else { return pid }
        let owner = resolve(pid)
        return owner > 0 ? owner : pid
    }

    /// Menemukan aplikasi reguler (UI app) yang memiliki audio stream ini.
    /// Jika responsibility API berhenti di helper yang berdiri sendiri, fungsi ini
    /// menelusuri rantai parent process (BSD ppid) hingga 6 tingkat ke atas.
    static func regularAppOwner(of pid: pid_t) -> NSRunningApplication? {
        let respPid = owner(of: pid)
        if let app = NSRunningApplication(processIdentifier: respPid), app.activationPolicy == .regular {
            return app
        }
        var current = respPid
        for _ in 0..<6 {
            current = parent(of: current)
            guard current > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
        }
        return nil
    }

    /// Mengambil parent PID dari BSD process table
    private static func parent(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }

    /// Nama tampilan aplikasi dengan fallback semantik
    static func displayName(pid: pid_t, fallback: String) -> String {
        if let app = NSRunningApplication(processIdentifier: pid),
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        return fallback.trimmingCharacters(in: .whitespaces)
    }

    /// Mengambil ikon aplikasi dengan caching memori
    static func icon(for pid: pid_t, pointSize: CGFloat = 32) -> NSImage {
        let key = "\(pid)@\(Int(pointSize))" as NSString
        if let cached = iconCache.object(forKey: key) { return cached }

        let source = NSRunningApplication(processIdentifier: pid)?.icon
            ?? NSWorkspace.shared.icon(for: .unixExecutable)

        let targetSize = NSSize(width: pointSize, height: pointSize)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: targetSize),
                    from: NSRect(origin: .zero, size: source.size),
                    operation: .copy,
                    fraction: 1.0)
        resized.unlockFocus()

        iconCache.setObject(resized, forKey: key)
        return resized
    }

    static func clearIconCache() {
        iconCache.removeAllObjects()
    }
}
