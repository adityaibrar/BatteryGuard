// MixerRender.swift
// BatteryGuard — DSP Rendering Audio Real-Time Menggunakan Accelerate vDSP

import Accelerate
import CoreAudio

/// Merender audio dari Process Tap ke output buffer device secara real-time.
/// Menangani berbagai topologi channel (interleaved stereo, discrete mono per buffer, fold-down).
/// Berjalan pada audio thread real-time: zero-allocation, lock-free, single-pass.
enum MixerRender {
    /// Menghitung jumlah frame audio dalam suatu buffer
    static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    /// Menemukan buffer index yang membawa data dari Process Tap dalam Aggregate Device.
    ///
    /// Aggregate Device menaruh input stream sub-device terlebih dahulu (misal mikrofon)
    /// dan Process Tap di akhir list buffer. Oleh karena itu pencarian dilakukan dari belakang
    /// (reverse stride) mencocokkan jumlah channel tap yang diminta.
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer,
                               tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mData != nil && buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels { return index }
            if buffers.count == 1 { lone = index }
        }
        return lone
    }

    /// Memetakan channel output ke channel source yang sesuai
    static func sourceChannel(for outputChannel: Int, sourceChannels: Int) -> Int? {
        if outputChannel < sourceChannels { return outputChannel }
        // Source mono (1-ch) didistribusikan ke kedua channel depan
        if sourceChannels == 1, outputChannel == 1 { return 0 }
        return nil
    }

    /// Merender source buffer ke seluruh output buffer dengan pengali gain
    @discardableResult
    static func render(source: AudioBuffer,
                       into output: UnsafeMutableAudioBufferListPointer,
                       gain: Float) -> Int {
        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }

        var frames = self.frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            frames = min(frames, self.frames(bytes: buffer.mDataByteSize,
                                             channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0 else { return 0 }
        var gain = gain

        // 1. Kasus Standar: 1 buffer output interleaved dengan channel sama persis
        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            vDSP_vsmul(samples, 1, &gain, destination, 1, vDSP_Length(frames * sourceChannels))
            return frames
        }

        // 2. Output Mono (1 channel) dari source multi-channel (Stereo ke Mono downmix)
        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            var scale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &scale,
                       destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &scale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            return frames
        }

        // 3. Multi-buffer Non-Interleaved (misal Discrete Mono per Buffer pada Speaker/Headphone Apple)
        var firstOutputChannel = 0
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                guard let sourceChannel = sourceChannel(for: firstOutputChannel + channel,
                                                        sourceChannels: sourceChannels) else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                vDSP_vsmul(samples + sourceChannel, vDSP_Stride(sourceChannels), &gain,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        return frames
    }
}
