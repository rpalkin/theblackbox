//
//  UnifiedAudioCapture.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import Foundation
import ScreenCaptureKit
internal import CoreGraphics
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
    /// - Returns: The URL where the recording will be saved
    @available(macOS 15.0, *)
    func startCapture(to directory: String) async throws -> URL {
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
        let filename = generateFilename()
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
        
        // ScreenCaptureKit requires a display even for audio-only capture. Prefer the
        // built-in display so unplugging external monitors does not invalidate capture.
        guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? content.displays.first else {
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
        
        return await finishCapture(outputURL: outputURL, streamToStop: stream)
    }

    @available(macOS 15.0, *)
    func finishCaptureAfterUnexpectedStreamStop() async throws -> URL {
        guard isCapturing else {
            throw UnifiedAudioCaptureError.notCapturing
        }

        guard let outputURL = currentRecordingURL else {
            throw UnifiedAudioCaptureError.notCapturing
        }

        return await finishCapture(outputURL: outputURL, streamToStop: nil)
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
    private func generateFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        return "Recording_\(timestamp).m4a"
    }

    @available(macOS 15.0, *)
    private func finishCapture(outputURL: URL, streamToStop: SCStream?) async -> URL {
        print("[UnifiedAudioCapture] Stopping capture...")

        if let streamToStop {
            do {
                try await streamToStop.stopCapture()
                print("[UnifiedAudioCapture] Capture stopped successfully")
            } catch {
                print("[UnifiedAudioCapture] Error stopping capture: \(error)")
                // Continue cleanup even if stop fails
            }
        } else {
            print("[UnifiedAudioCapture] Stream already stopped; finalizing recording")
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

// MARK: - Helper Classes

private class AudioFileWriter {
    let writer: AVAssetWriter
    let audioInput: AVAssetWriterInput
    let micInput: AVAssetWriterInput
    private var isSessionStarted = false
    var onError: ((Error) -> Void)?
    
    init(url: URL, sampleRate: Double, channelCount: Int) throws {
        self.writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        
        let audioSettings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: 128000
        ]
        
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
    
    init(fileWriter: AudioFileWriter) {
        self.fileWriter = fileWriter
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        fileWriter.append(sampleBuffer, type: type)
    }
}
