// LogView.swift
// BatteryGuard — Menampilkan log dari com.ibrardev.BatteryGuard.Helper

import SwiftUI
import Combine

class LogViewModel: ObservableObject {
    @Published var logs: String = ""
    private var process: Process?
    
    func startLogging() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["stream", "--predicate", "process == \"com.ibrardev.BatteryGuard.Helper\"", "--info"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.count > 0, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.logs.append(str)
                }
            }
        }
        
        do {
            try task.run()
            self.process = task
        } catch {
            DispatchQueue.main.async {
                self.logs = "Gagal memulai log stream: \(error.localizedDescription)"
            }
        }
    }
    
    func stopLogging() {
        process?.terminate()
        process = nil
    }
}

struct LogView: View {
    @StateObject private var viewModel = LogViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.logs)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("LOG_BOTTOM")
                }
                .onChange(of: viewModel.logs) { _ in
                    proxy.scrollTo("LOG_BOTTOM", anchor: .bottom)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            viewModel.startLogging()
        }
        .onDisappear {
            viewModel.stopLogging()
        }
    }
}
