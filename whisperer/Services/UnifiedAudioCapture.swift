//
//  UnifiedAudioCapture.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import Foundation
import ScreenCaptureKit
internal import AVFoundation
internal import CoreMedia
internal import Combine
internal import Accelerate

/// Protocol for receiving recording events from the unified capture
@MainActor
protocol UnifiedAudioCaptureDelegate: AnyObject {
    /// Called when recording completes successfully
    func unifiedAudioCapture(_ capture: UnifiedAudioCapture, didFinishRecordingTo url: URL)
    
    /// Called when an error occurs during capture
    func unifiedAudioCapture(_ capture: UnifiedAudioCapture, didFailWithError error: Error)
    
    /// Called when capture stops
    func unifiedAudioCaptureDidStop(_ capture: UnifiedAudioCapture)
}

/// Errors that can occur during unified audio capture
enum UnifiedAudioCaptureError: LocalizedError {
    case noDisplaysAvailable
    case streamConfigurationFailed
    case streamStartFailed(Error)
    case recordingOutputFailed(Error)
    case permissionDenied
    case alreadyCapturing
    case notCapturing
    case directoryCreationFailed(Error)
    case unsupportedOS
    
    var errorDescription: String? {
        switch self {
        case .noDisplaysAvailable:
            return "No displays available for capture"
        case .streamConfigurationFailed:
            return "Failed to configure audio stream"
        case .streamStartFailed(let error):
            return "Failed to start audio stream: \(error.localizedDescription)"
        case .recordingOutputFailed(let error):
            return "Failed to configure recording output: \(error.localizedDescription)"
        case .permissionDenied:
            return "Screen recording permission is required"
        case .alreadyCapturing:
            return "Audio capture is already in progress"
        case .notCapturing:
            return "No audio capture is currently active"
        case .directoryCreationFailed(let error):
            return "Failed to create output directory: \(error.localizedDescription)"
        case .unsupportedOS:
            return "This feature requires macOS 15.0 or later"
        }
    }
}

/// Unified audio capture service using ScreenCaptureKit with SCStreamOutput
/// Captures both system audio and microphone audio and records to file using AVAssetWriter
@MainActor
class UnifiedAudioCapture: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    weak var delegate: UnifiedAudioCaptureDelegate?
    
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var currentError: Error?
    @Published private(set) var currentRecordingURL: URL?
    
    private var stream: SCStream?
    private var outputHandler: StreamOutputHandler?
    private let audioQueue = DispatchQueue(label: "com.whisperer.audioQueue")
    
    // Audio configuration
    private let sampleRate: Double = 48000.0  // 48kHz recommended for ScreenCaptureKit
    private let channelCount: Int = 1          // Mono
    
    // MARK: - Public Methods
    
    /// Start capturing and recording unified audio (system audio + microphone) directly to file
    /// - Parameters:
    ///   - directory: The directory to save the recording
    ///   - format: The audio format to use (.m4a or .wav)
    /// - Returns: The URL where the recording will be saved
    @available(macOS 15.0, *)
    func startCapture(to directory: String, format: AppSettings.AudioFormat) async throws -> URL {
        guard !isCapturing else {
            throw UnifiedAudioCaptureError.alreadyCapturing
        }
        
        print("[UnifiedAudioCapture] Starting capture with SCStreamOutput...")
        
        // Ensure directory exists
        let directoryURL = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw UnifiedAudioCaptureError.directoryCreationFailed(error)
        }
        
        // Generate unique filename with timestamp
        let filename = generateFilename(format: format)
        let outputURL = directoryURL.appendingPathComponent(filename)
        
        print("[UnifiedAudioCapture] Will record to: \(outputURL.path)")
        
        // Get available content
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            print("[UnifiedAudioCapture] Failed to get shareable content: \(error)")
            throw UnifiedAudioCaptureError.permissionDenied
        }
        
        // Get the main display
        guard let display = content.displays.first else {
            print("[UnifiedAudioCapture] No displays available")
            throw UnifiedAudioCaptureError.noDisplaysAvailable
        }
        
        print("[UnifiedAudioCapture] Using display: \(display.displayID)")
        
        // Create content filter for the display (we only want audio, but need a display for the filter)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure the stream for audio-only capture
        let configuration = SCStreamConfiguration()
        
        // Audio settings
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true  // Don't capture our own audio
        configuration.sampleRate = Int(sampleRate)
        configuration.channelCount = channelCount
        
        configuration.width = 2
        configuration.height = 2
        
        // Microphone settings (macOS 13+)
        configuration.captureMicrophone = true
        print("[UnifiedAudioCapture] Microphone capture enabled")
        
        print("[UnifiedAudioCapture] Configuration: sampleRate=\(sampleRate), channels=\(channelCount)")
        
        // Create the stream
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        // Create audio file writer
        let fileWriter: AudioFileWriter
        do {
            fileWriter = try AudioFileWriter(
                url: outputURL,
                format: format,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
            
            fileWriter.onError = { [weak self] error in
                Task { @MainActor in
                    print("[UnifiedAudioCapture] Writer error: \(error)")
                    self?.currentError = error
                    if let self = self {
                        self.delegate?.unifiedAudioCapture(self, didFailWithError: error)
                    }
                }
            }
            
            fileWriter.start()
        } catch {
            print("[UnifiedAudioCapture] Failed to create file writer: \(error)")
            throw UnifiedAudioCaptureError.recordingOutputFailed(error)
        }
        
        // Create output handler
        let handler = StreamOutputHandler(fileWriter: fileWriter)
        
        // Store handler first to ensure it's retained before adding to stream
        self.outputHandler = handler
        
        do {
            // Add video output first (required even for audio-only capture to prevent "stream output NOT found" errors)
            // ScreenCaptureKit always sends video frames, even with minimal resolution
            try newStream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: audioQueue)
            try newStream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: audioQueue)
            try newStream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: audioQueue)
            print("[UnifiedAudioCapture] Added stream outputs (screen, audio, microphone)")
        } catch {
            print("[UnifiedAudioCapture] Failed to add stream outputs: \(error)")
            self.outputHandler = nil
            throw UnifiedAudioCaptureError.recordingOutputFailed(error)
        }
        
        // Start the stream
        do {
            try await newStream.startCapture()
            self.stream = newStream
            self.isCapturing = true
            self.currentError = nil
            self.currentRecordingURL = outputURL
            print("[UnifiedAudioCapture] Capture started successfully")
            return outputURL
        } catch {
            print("[UnifiedAudioCapture] Failed to start capture: \(error)")
            throw UnifiedAudioCaptureError.streamStartFailed(error)
        }
    }
    
    /// Stop capturing and finalize the recording
    /// - Returns: The URL of the saved recording
    @available(macOS 15.0, *)
    func stopCapture() async throws -> URL {
        guard isCapturing, let stream = stream else {
            throw UnifiedAudioCaptureError.notCapturing
        }
        
        guard let outputURL = currentRecordingURL else {
            throw UnifiedAudioCaptureError.notCapturing
        }
        
        print("[UnifiedAudioCapture] Stopping capture...")
        
        do {
            try await stream.stopCapture()
            print("[UnifiedAudioCapture] Capture stopped successfully")
        } catch {
            print("[UnifiedAudioCapture] Error stopping capture: \(error)")
            // Continue cleanup even if stop fails
        }
        
        if let handler = outputHandler {
            await handler.fileWriter.finish()
        }
        
        self.stream = nil
        self.outputHandler = nil
        self.isCapturing = false
        
        delegate?.unifiedAudioCaptureDidStop(self)
        
        print("[UnifiedAudioCapture] Recording saved to: \(outputURL.path)")
        return outputURL
    }
    
    /// Cancel recording and delete partial file
    @available(macOS 15.0, *)
    func cancelCapture() async {
        print("[UnifiedAudioCapture] Cancelling capture...")
        
        if let stream = stream {
            try? await stream.stopCapture()
        }
        
        if let handler = outputHandler {
            await handler.fileWriter.finish()
        }
        
        // Delete partial file
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            print("[UnifiedAudioCapture] Deleted partial file: \(url.path)")
        }
        
        self.stream = nil
        self.outputHandler = nil
        self.isCapturing = false
        self.currentRecordingURL = nil
        
        print("[UnifiedAudioCapture] Capture cancelled")
    }
    
    /// Get the audio format for the captured audio
    func getAudioFormat() -> AVAudioFormat? {
        return AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount)
        )
    }
    
    // MARK: - Private Methods
    
    /// Generate a unique filename with timestamp
    private func generateFilename(format: AppSettings.AudioFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        return "Recording_\(timestamp).\(format.fileExtension)"
    }
}

// MARK: - SCStreamDelegate

extension UnifiedAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            print("[UnifiedAudioCapture] Stream stopped with error: \(error)")
            currentError = error
            delegate?.unifiedAudioCapture(self, didFailWithError: error)
        }
    }
}

// MARK: - Audio Normalizer

/// Audio normalizer that balances volume levels between system audio and microphone
private class AudioNormalizer {
    // Target RMS level in linear scale (approximately -12 dB)
    private let targetRMSLevel: Float = 0.25
    
    // Smoothing factor for level tracking (0-1, higher = faster response)
    private let smoothingFactor: Float = 0.1
    
    // Current tracked RMS levels for each source
    private var systemAudioRMS: Float = 0.0
    private var microphoneRMS: Float = 0.0
    
    // Current gain values
    private var systemAudioGain: Float = 1.0
    private var microphoneGain: Float = 1.0
    
    // Minimum and maximum gain limits to prevent extreme adjustments
    private let minGain: Float = 0.1
    private let maxGain: Float = 10.0
    
    // Number of samples to analyze before applying normalization
    private var systemSampleCount: Int = 0
    private var micSampleCount: Int = 0
    private let warmupSamples: Int = 10  // Wait for this many samples before normalizing
    
    /// Calculate RMS level from audio buffer
    private func calculateRMS(from buffer: UnsafeMutablePointer<Float>, count: Int) -> Float {
        var rms: Float = 0.0
        vDSP_rmsqv(buffer, 1, &rms, vDSP_Length(count))
        return rms
    }
    
    /// Apply gain to audio buffer in place
    private func applyGain(_ gain: Float, to buffer: UnsafeMutablePointer<Float>, count: Int) {
        var gainValue = gain
        vDSP_vsmul(buffer, 1, &gainValue, buffer, 1, vDSP_Length(count))
        
        // Clip to prevent distortion
        var minVal: Float = -1.0
        var maxVal: Float = 1.0
        vDSP_vclip(buffer, 1, &minVal, &maxVal, buffer, 1, vDSP_Length(count))
    }
    
    /// Update gain based on current RMS level
    private func updateGain(currentRMS: Float, currentGain: inout Float) {
        guard currentRMS > 0.001 else { return }  // Ignore very quiet signals
        
        // Calculate desired gain to reach target level
        let desiredGain = targetRMSLevel / currentRMS
        
        // Smooth the gain change to avoid sudden jumps
        let newGain = currentGain + smoothingFactor * (desiredGain - currentGain)
        
        // Clamp to limits
        currentGain = max(minGain, min(maxGain, newGain))
    }
    
    /// Process and normalize a sample buffer
    /// - Parameters:
    ///   - sampleBuffer: The audio sample buffer to process
    ///   - type: The type of audio (system or microphone)
    /// - Returns: A new normalized sample buffer, or the original if processing fails
    func normalize(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) -> CMSampleBuffer {
        // Get audio buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return sampleBuffer
        }
        
        // Get format description to determine sample format
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return sampleBuffer
        }
        
        let bytesPerSample = Int(asbd.pointee.mBytesPerFrame)
        let sampleCount = length / bytesPerSample
        
        guard sampleCount > 0 else { return sampleBuffer }
        
        // Convert to float for processing
        var floatBuffer = [Float](repeating: 0, count: sampleCount)
        
        // Handle different audio formats
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Already float format
            data.withMemoryRebound(to: Float.self, capacity: sampleCount) { floatPtr in
                floatBuffer = Array(UnsafeBufferPointer(start: floatPtr, count: sampleCount))
            }
        } else if asbd.pointee.mBitsPerChannel == 16 {
            // 16-bit integer format
            data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
                var scale: Float = 1.0 / 32768.0
                var tempBuffer = [Float](repeating: 0, count: sampleCount)
                vDSP_vflt16(int16Ptr, 1, &tempBuffer, 1, vDSP_Length(sampleCount))
                vDSP_vsmul(tempBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(sampleCount))
            }
        } else if asbd.pointee.mBitsPerChannel == 32 {
            // 32-bit integer format
            data.withMemoryRebound(to: Int32.self, capacity: sampleCount) { int32Ptr in
                var scale: Float = 1.0 / Float(Int32.max)
                var tempBuffer = [Float](repeating: 0, count: sampleCount)
                vDSP_vflt32(int32Ptr, 1, &tempBuffer, 1, vDSP_Length(sampleCount))
                vDSP_vsmul(tempBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(sampleCount))
            }
        } else {
            // Unsupported format, return original
            return sampleBuffer
        }
        
        // Calculate current RMS
        let currentRMS = calculateRMS(from: &floatBuffer, count: sampleCount)
        
        // Update tracking and gain based on source type
        switch type {
        case .audio:
            systemSampleCount += 1
            systemAudioRMS = systemAudioRMS * (1 - smoothingFactor) + currentRMS * smoothingFactor
            if systemSampleCount > warmupSamples {
                updateGain(currentRMS: systemAudioRMS, currentGain: &systemAudioGain)
            }
            applyGain(systemAudioGain, to: &floatBuffer, count: sampleCount)
            
        case .microphone:
            micSampleCount += 1
            microphoneRMS = microphoneRMS * (1 - smoothingFactor) + currentRMS * smoothingFactor
            if micSampleCount > warmupSamples {
                updateGain(currentRMS: microphoneRMS, currentGain: &microphoneGain)
            }
            applyGain(microphoneGain, to: &floatBuffer, count: sampleCount)
            
        default:
            return sampleBuffer
        }
        
        // Convert back to original format and create new sample buffer
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Write back float data
            floatBuffer.withUnsafeBufferPointer { bufferPtr in
                data.withMemoryRebound(to: Float.self, capacity: sampleCount) { floatPtr in
                    floatPtr.update(from: bufferPtr.baseAddress!, count: sampleCount)
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 16 {
            // Convert back to 16-bit integer
            var scale: Float = 32767.0
            var scaledBuffer = [Float](repeating: 0, count: sampleCount)
            vDSP_vsmul(floatBuffer, 1, &scale, &scaledBuffer, 1, vDSP_Length(sampleCount))
            
            data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
                for i in 0..<sampleCount {
                    int16Ptr[i] = Int16(max(-32768, min(32767, scaledBuffer[i])))
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 32 {
            // Convert back to 32-bit integer
            var scale: Float = Float(Int32.max)
            var scaledBuffer = [Float](repeating: 0, count: sampleCount)
            vDSP_vsmul(floatBuffer, 1, &scale, &scaledBuffer, 1, vDSP_Length(sampleCount))
            
            data.withMemoryRebound(to: Int32.self, capacity: sampleCount) { int32Ptr in
                for i in 0..<sampleCount {
                    int32Ptr[i] = Int32(max(Float(Int32.min), min(Float(Int32.max), scaledBuffer[i])))
                }
            }
        }
        
        // Return the modified buffer (we modified in place)
        return sampleBuffer
    }
    
    /// Get current gain levels for debugging/display
    func getCurrentGains() -> (systemAudio: Float, microphone: Float) {
        return (systemAudioGain, microphoneGain)
    }
    
    /// Get current RMS levels for debugging/display
    func getCurrentLevels() -> (systemAudio: Float, microphone: Float) {
        return (systemAudioRMS, microphoneRMS)
    }
}

// MARK: - Helper Classes

private class AudioFileWriter {
    let writer: AVAssetWriter
    let audioInput: AVAssetWriterInput
    let micInput: AVAssetWriterInput
    private var isSessionStarted = false
    var onError: ((Error) -> Void)?
    
    init(url: URL, format: AppSettings.AudioFormat, sampleRate: Double, channelCount: Int) throws {
        self.writer = try AVAssetWriter(outputURL: url, fileType: format == .m4a ? .m4a : .wav)
        
        var audioSettings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount
        ]
        
        if format == .m4a {
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = 128000
        } else {
            audioSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            audioSettings[AVLinearPCMBitDepthKey] = 16
            audioSettings[AVLinearPCMIsFloatKey] = false
            audioSettings[AVLinearPCMIsBigEndianKey] = false
            audioSettings[AVLinearPCMIsNonInterleaved] = false
        }
        
        // We need separate inputs for system audio and mic if we want to record both.
        // AVAssetWriter can handle multiple inputs.
        
        self.audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        self.audioInput.expectsMediaDataInRealTime = true
        
        self.micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        self.micInput.expectsMediaDataInRealTime = true
        
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        if writer.canAdd(micInput) {
            writer.add(micInput)
        }
    }
    
    func start() {
        writer.startWriting()
    }
    
    func append(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard writer.status == .writing else {
            if writer.status == .failed, let error = writer.error {
                onError?(error)
            }
            return
        }
        
        if !isSessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            isSessionStarted = true
        }
        
        switch type {
        case .audio:
            if audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        case .microphone:
            if micInput.isReadyForMoreMediaData {
                micInput.append(sampleBuffer)
            }
        default:
            break
        }
    }
    
    func finish() async {
        audioInput.markAsFinished()
        micInput.markAsFinished()
        await writer.finishWriting()
    }
}

private class StreamOutputHandler: NSObject, SCStreamOutput {
    let fileWriter: AudioFileWriter
    let normalizer: AudioNormalizer
    
    init(fileWriter: AudioFileWriter) {
        self.fileWriter = fileWriter
        self.normalizer = AudioNormalizer()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Apply normalization before writing
        let normalizedBuffer = normalizer.normalize(sampleBuffer, type: type)
        fileWriter.append(normalizedBuffer, type: type)
    }
}
