// MenuBarAppKitLabel.swift
// BatteryGuard — Pure AppKit status bar view
//
// MENGAPA bukan NSHostingView<SwiftUI>?
// NSHostingView membuat CVDisplayLink (display link) yang berjalan di ~60Hz
// bahkan saat tidak ada animasi aktif. Ini menyebabkan ~67 idle wakeups/detik
// yang terlihat di Activity Monitor, berkontribusi signifikan ke CPU usage tinggi.
//
// Solusi: NSView subclass murni AppKit dengan NSTextField subviews.
// View ini TIDAK PUNYA display link. Hanya redraws saat update() dipanggil,
// yaitu saat data benar-benar berubah (via removeDuplicates() di Combine pipeline).

import AppKit
import Foundation

// MARK: - MenuBarAppKitLabel

/// Pure AppKit replacement untuk NSHostingView<MenuBarStatusLabel>
/// Eliminasi CVDisplayLink → 0 idle wakeups dari rendering
final class MenuBarAppKitLabel: NSView {

    // MARK: - Subviews

    private let networkView = NetworkChipView()
    private let gpuChip     = StatusChipAppKit(chipLabel: "GPU")
    private let ramChip     = StatusChipAppKit(chipLabel: "RAM")
    private let cpuChip     = StatusChipAppKit(chipLabel: "CPU")
    private let tempField   = makePlainTextField()

    // MARK: - State (untuk layout)

    private var showNetwork = true
    private var showGPU     = true
    private var showRAM     = true
    private var showCPU     = true
    private var showTemp    = false

    // MARK: - Layout Constants (mirror MenuBarStatusLabel dari AppDelegate)

    private let chipW:    CGFloat = 45
    private let networkW: CGFloat = 72
    private let spacing:  CGFloat = 10
    private let hPad:     CGFloat = 4
    private let tempW:    CGFloat = 46

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        tempField.font      = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        tempField.alignment = .center

        for v in [networkView, gpuChip, ramChip, cpuChip, tempField] as [NSView] {
            addSubview(v)
        }
    }

    // MARK: - Layout
    // Hanya dipanggil saat ukuran view berubah atau visibilitas chip berubah

    override func layout() {
        super.layout()
        relayout()
    }

    private func relayout() {
        // Guard: jangan layout jika height belum siap
        guard bounds.height > 0 else { return }

        let h = bounds.height
        var x = hPad

        func place(_ view: NSView, width: CGFloat, visible: Bool) {
            if visible {
                view.frame = NSRect(x: x, y: 0, width: width, height: h)
                x += width + spacing
            } else {
                view.frame = .zero
            }
        }

        place(networkView, width: networkW, visible: showNetwork)
        place(gpuChip,     width: chipW,    visible: showGPU)
        place(ramChip,     width: chipW,    visible: showRAM)
        place(cpuChip,     width: chipW,    visible: showCPU)
        place(tempField,   width: tempW,    visible: showTemp)
    }

    // MARK: - Public Update API
    // Dipanggil HANYA saat data berubah — tidak ada timer, tidak ada display link

    struct DisplayData {
        var showNetwork: Bool
        var showGPU:     Bool
        var showRAM:     Bool
        var showCPU:     Bool
        var showTemp:    Bool

        var uploadText:   String
        var downloadText: String
        var gpuText:      String
        var ramText:      String
        var cpuText:      String
        var tempText:     String

        var gpuColor: NSColor
        var ramColor: NSColor
        var cpuColor: NSColor
        var tempColor: NSColor
    }

    func update(_ data: DisplayData) {
        // Relayout hanya jika visibilitas berubah
        let needsRelayout = showNetwork != data.showNetwork ||
                            showGPU     != data.showGPU     ||
                            showRAM     != data.showRAM     ||
                            showCPU     != data.showCPU     ||
                            showTemp    != data.showTemp

        showNetwork = data.showNetwork
        showGPU     = data.showGPU
        showRAM     = data.showRAM
        showCPU     = data.showCPU
        showTemp    = data.showTemp

        if needsRelayout { relayout() }

        networkView.update(upload: data.uploadText, download: data.downloadText)
        gpuChip.update(value: data.gpuText, color: data.gpuColor)
        ramChip.update(value: data.ramText, color: data.ramColor)
        cpuChip.update(value: data.cpuText, color: data.cpuColor)

        if data.showTemp {
            if tempField.stringValue != data.tempText { tempField.stringValue = data.tempText }
            if tempField.textColor   != data.tempColor { tempField.textColor = data.tempColor }
        }
    }
}

// MARK: - StatusChipAppKit
// Dua baris: label kecil (7pt) di atas, nilai besar (13pt) di bawah
// Mirror: struct StatusChip di AppDelegate.swift

final class StatusChipAppKit: NSView {

    private let labelField = makePlainTextField()
    private let valueField = makePlainTextField()

    init(chipLabel: String) {
        super.init(frame: .zero)
        labelField.stringValue = chipLabel
        labelField.font        = .systemFont(ofSize: 7, weight: .bold)
        labelField.textColor   = .secondaryLabelColor
        labelField.alignment   = .right

        valueField.font      = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueField.textColor = .labelColor
        valueField.alignment = .right

        addSubview(labelField)
        addSubview(valueField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        guard bounds.height > 0, bounds.width > 0 else { return }
        let h = bounds.height
        let w = bounds.width
        // Label kecil: area atas (~40%), Value besar: area bawah (~60%)
        labelField.frame = NSRect(x: 0, y: h * 0.52, width: w, height: h * 0.42)
        valueField.frame = NSRect(x: 0, y: 0,         width: w, height: h * 0.62)
    }

    /// Update value dan color — hanya set jika berubah (hindari redraw yang tidak perlu)
    func update(value: String, color: NSColor) {
        if valueField.stringValue != value { valueField.stringValue = value }
        if valueField.textColor   != color { valueField.textColor   = color }
    }
}

// MARK: - NetworkChipView
// Dua baris: ↑ upload di atas, ↓ download di bawah (monospaced, 9pt)
// Mirror: network VStack di MenuBarStatusLabel

final class NetworkChipView: NSView {

    private let upArrow    = makePlainTextField()
    private let upField    = makePlainTextField()
    private let downArrow  = makePlainTextField()
    private let downField  = makePlainTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupFields()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupFields()
    }

    private func setupFields() {
        upArrow.stringValue  = "↑"
        downArrow.stringValue = "↓"

        upArrow.font    = .systemFont(ofSize: 7.5, weight: .bold)
        downArrow.font  = .systemFont(ofSize: 7.5, weight: .bold)
        upArrow.textColor   = .systemGreen
        downArrow.textColor = .systemBlue

        let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        upField.font   = monoFont
        downField.font = monoFont
        upField.alignment   = .right
        downField.alignment = .right

        for v in [upArrow, upField, downArrow, downField] { addSubview(v) }
    }

    override func layout() {
        super.layout()
        guard bounds.height > 0 else { return }
        let h  = bounds.height
        let w  = bounds.width
        let rH = h / 2.0
        let arW: CGFloat = 10

        upArrow.frame   = NSRect(x: 0,       y: rH, width: arW,          height: rH)
        upField.frame   = NSRect(x: arW + 2, y: rH, width: w - arW - 2,  height: rH)
        downArrow.frame = NSRect(x: 0,       y: 0,  width: arW,          height: rH)
        downField.frame = NSRect(x: arW + 2, y: 0,  width: w - arW - 2,  height: rH)
    }

    func update(upload: String, download: String) {
        if upField.stringValue   != upload   { upField.stringValue   = upload   }
        if downField.stringValue != download { downField.stringValue = download }
    }
}

// MARK: - Helpers

/// Buat NSTextField tanpa border, tidak editable, background transparan
private func makePlainTextField() -> NSTextField {
    let tf = NSTextField(labelWithString: "")
    tf.isBezeled        = false
    tf.isEditable       = false
    tf.drawsBackground  = false
    tf.lineBreakMode    = .byClipping
    return tf
}
