//
//  AudioTrackExtractor.swift
//  whisperer
//

import Foundation
internal import AVFoundation
internal import CoreMedia

enum AudioTrackRole {
    case systemAudio
    case microphone

    fileprivate var trackIndex: Int {
        switch self {
        case .systemAudio:
            return 0
        case .microphone:
            return 1
        }
    }
}

enum AudioTrackExtractorError: LocalizedError {
    case trackReaderSetupFailed
    case readerStartFailed(String)
    case readerFailed(String)
    case missingPCMFormatDescription
    case failedToCreatePCMBuffer
    case failedToCreateConverter

    var errorDescription: String? {
        switch self {
        case .trackReaderSetupFailed:
            return "Failed to configure audio track reader"
        case .readerStartFailed(let message):
            return "Failed to start reading audio track: \(message)"
        case .readerFailed(let message):
            return "Failed to decode audio track: \(message)"
        case .missingPCMFormatDescription:
            return "Decoded audio track did not provide a PCM format description"
        case .failedToCreatePCMBuffer:
            return "Failed to create PCM buffer for decoded audio"
        case .failedToCreateConverter:
            return "Failed to create audio converter for 16 kHz resampling"
        }
    }
}

struct AudioTrackExtractor {
    private static let sourceSampleRate: Double = 48_000
    private static let outputSampleRate: Double = 16_000
    private static let shortClipPaddingSampleCount = 16_000
    private static let shortClipThresholdSampleCount = 240_000

    func extract(url: URL, role: AudioTrackRole) async throws -> [Float] {
        // Read-only path by contract: AVAsset + AVAssetReader only, never mutating the source file.
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard audioTracks.indices.contains(role.trackIndex) else {
            return []
        }

        let track = audioTracks[role.trackIndex]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: Self.sourceSampleRate,
        ])
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AudioTrackExtractorError.trackReaderSetupFailed
        }

        reader.add(output)

        guard reader.startReading() else {
            let message = reader.error?.localizedDescription ?? "Unknown AVAssetReader error"
            throw AudioTrackExtractorError.readerStartFailed(message)
        }

        var decodedSamples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let pcmBuffer = try makePCMBuffer(from: sampleBuffer)

            if let channelData = pcmBuffer.floatChannelData {
                let sampleCount = Int(pcmBuffer.frameLength)
                let samples = UnsafeBufferPointer(start: channelData[0], count: sampleCount)
                decodedSamples.append(contentsOf: samples)
            }
        }

        if reader.status == .failed {
            let message = reader.error?.localizedDescription ?? "Unknown AVAssetReader failure"
            throw AudioTrackExtractorError.readerFailed(message)
        }

        var resampledSamples = try resampleTo16kHzMono(decodedSamples)
        if resampledSamples.count <= Self.shortClipThresholdSampleCount {
            resampledSamples.append(contentsOf: repeatElement(0, count: Self.shortClipPaddingSampleCount))
        }

        return resampledSamples
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioTrackExtractorError.missingPCMFormatDescription
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let format = AVAudioFormat(streamDescription: streamDescription),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioTrackExtractorError.failedToCreatePCMBuffer
        }

        pcmBuffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return pcmBuffer
    }

    private func resampleTo16kHzMono(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sourceSampleRate,
            channels: 1,
            interleaved: false
        ),
        let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.outputSampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat) else {
            throw AudioTrackExtractorError.failedToCreateConverter
        }

        let inputFrameCount = AVAudioFrameCount(samples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputFrameCount),
              let inputChannel = inputBuffer.floatChannelData?[0] else {
            throw AudioTrackExtractorError.failedToCreatePCMBuffer
        }

        inputBuffer.frameLength = inputFrameCount
        for (index, sample) in samples.enumerated() {
            inputChannel[index] = sample
        }

        let outputCapacity = AVAudioFrameCount(
            ceil(Double(samples.count) * Self.outputSampleRate / Self.sourceSampleRate)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: destinationFormat,
            frameCapacity: max(outputCapacity, 1)
        ) else {
            throw AudioTrackExtractorError.failedToCreatePCMBuffer
        }

        var conversionError: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            break
        case .error:
            throw AudioTrackExtractorError.failedToCreateConverter
        @unknown default:
            throw AudioTrackExtractorError.failedToCreateConverter
        }

        guard let outputChannel = outputBuffer.floatChannelData?[0] else {
            return []
        }

        let outputSamples = UnsafeBufferPointer(start: outputChannel, count: Int(outputBuffer.frameLength))
        return Array(outputSamples)
    }
}
