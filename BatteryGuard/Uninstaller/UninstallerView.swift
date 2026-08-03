// UninstallerView.swift
// BatteryGuard — UI untuk fitur App Uninstaller
// Desain mengikuti referensi Vorssaint Utils: header app info, file list dengan
// section per kategori, footer dengan counter & tombol Move to Trash

import SwiftUI
import AppKit

// MARK: - UninstallerView (root)

struct UninstallerView: View {
    @StateObject private var vm = UninstallerViewModel()

    var body: some View {
        ZStack {
            if vm.isShowingSuccess, let summary = vm.uninstallSummary {
                // ──────── Uninstall berhasil → tampilkan halaman sukses ────────
                UninstallSuccessView(summary: summary, onDone: { vm.reset() })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                VStack(spacing: 0) {
                    if let app = vm.appInfo {
                        // ──────── App sudah di-drop → tampilkan hasil scan ────────
                        AppHeaderView(app: app, onDismiss: { vm.reset() })
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                        Divider()

                        if vm.isScanning {
                            // Scanning state
                            Spacer()
                            VStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("Mencari file terkait...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        } else {
                            // File list
                            FileListView(vm: vm)
                        }

                        Divider()

                        // Footer
                        FooterView(vm: vm)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                    } else {
                        // ──────── Belum ada app yang di-drop → tampilkan drop zone ────────
                        DropZoneView(vm: vm)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: vm.isShowingSuccess)
        .animation(.easeInOut(duration: 0.25), value: vm.appInfo == nil)
        // Error banner
        .overlay(alignment: .top) {
            if let msg = vm.errorMessage {
                ErrorBanner(message: msg) { vm.errorMessage = nil }
                    .padding(.top, 6)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
    }
}

// MARK: - Drop Zone

private struct DropZoneView: View {
    @ObservedObject var vm: UninstallerViewModel

    var body: some View {
        ZStack {
            // Background drop zone
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    vm.isDraggingOver
                        ? Color.accentColor
                        : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: vm.isDraggingOver ? 2 : 1.5, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(vm.isDraggingOver
                              ? Color.accentColor.opacity(0.08)
                              : Color.secondary.opacity(0.04))
                )
                .animation(.easeInOut(duration: 0.15), value: vm.isDraggingOver)

            // Center content
            VStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "arrow.down.app")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 4) {
                    Text("Drop Aplikasi di Sini")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Drag file .app untuk melihat dan menghapus\nsemua file yang berkaitan")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                // Tombol browse sebagai alternatif drag
                Button {
                    openFilePicker(vm: vm)
                } label: {
                    Text("Pilih Aplikasi...")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(32)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Drop handler menggunakan UTType untuk .app bundle
        .onDrop(of: ["public.file-url"], isTargeted: $vm.isDraggingOver) { providers in
            vm.handleDrop(providers: providers)
            return true
        }
    }

    private func openFilePicker(vm: UninstallerViewModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Pilih aplikasi yang ingin di-uninstall"

        if panel.runModal() == .OK, let url = panel.url {
            vm.handleDropURLs([url])
        }
    }
}

// MARK: - App Header

private struct AppHeaderView: View {
    let app: AppInfo
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

            // Name + Bundle ID
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Total size + dismiss button
            VStack(alignment: .trailing, spacing: 2) {
                Text(app.formattedBundleSize)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .monospacedDigit()

                Text("bundle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Tombol ✕
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hapus app ini dari Uninstaller")
        }
    }
}

// MARK: - File List

private struct FileListView: View {
    @ObservedObject var vm: UninstallerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if vm.files.isEmpty {
                    // Tidak ada file yang ditemukan (selain .app itu sendiri)
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Tidak ada file tambahan ditemukan")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(vm.filesByCategory, id: \.category.id) { section in
                        Section {
                            ForEach(section.files) { file in
                                FileRowView(
                                    file: file,
                                    onToggle: { vm.toggleFile(id: file.id) }
                                )

                                if file.id != section.files.last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        } header: {
                            SectionHeaderView(
                                category: section.category,
                                count: section.files.count
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeaderView: View {
    let category: AppFileCategory
    let count: Int

    var body: some View {
        HStack {
            Text(category.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }
}

// MARK: - File Row

private struct FileRowView: View {
    let file: AppFile
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: file.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(file.isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)

            // File icon
            Image(systemName: file.category.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            // Name + path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.parentDisplayPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Size
            Text(file.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .background(
            file.isSelected
                ? Color.accentColor.opacity(0.04)
                : Color.clear
        )
        .animation(.easeInOut(duration: 0.1), value: file.isSelected)
    }
}

// MARK: - Footer

private struct FooterView: View {
    @ObservedObject var vm: UninstallerViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Selection info
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.selectionLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(vm.selectedTotalSizeFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Cancel
            Button("Cancel") {
                vm.reset()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(vm.isMovingToTrash)

            // Move to Trash (destructive)
            Button {
                vm.moveSelectedToTrash()
            } label: {
                HStack(spacing: 5) {
                    if vm.isMovingToTrash {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text("Move to Trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.regular)
            .disabled(vm.selectedCount == 0 || vm.isMovingToTrash)
        }
    }
}

// MARK: - Error Banner

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

// MARK: - Uninstall Success View

private struct UninstallSuccessView: View {
    let summary: UninstallSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Icon + Checkmark overlay ──
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: summary.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .opacity(0.7)

                // Checkmark badge
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 6, y: 6)
            }
            .padding(.bottom, 20)

            // ── Judul ──
            Text("\(summary.appName) Dihapus")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .padding(.bottom, 6)

            Text("Semua file yang dipilih berhasil dipindahkan ke Trash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            // ── Ringkasan stats ──
            HStack(spacing: 24) {
                StatBadge(
                    value: "\(summary.deletedCount)",
                    label: "File Dihapus",
                    icon: "trash.fill",
                    color: .red
                )

                Divider()
                    .frame(height: 40)

                StatBadge(
                    value: summary.deletedSizeFormatted,
                    label: "Ruang Dibebaskan",
                    icon: "externaldrive.fill",
                    color: .green
                )

                if summary.failedCount > 0 {
                    Divider()
                        .frame(height: 40)

                    StatBadge(
                        value: "\(summary.failedCount)",
                        label: "Gagal",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 36)

            // ── Tombol aksi ──
            Button {
                onDone()
            } label: {
                Label("Uninstall Aplikasi Lain", systemImage: "arrow.down.app")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Stat Badge (untuk success view)

private struct StatBadge: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 80)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    UninstallerView()
        .frame(width: 580, height: 460)
}
#endif
