//
//  AudioRecordingService.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import Foundation
internal import AVFoundation
internal import CoreMedia
internal import Combine
internal import UserNotifications

/// Errors that can occur during audio recording
enum AudioRecordingError: LocalizedError {
    case permissionDenied(String)
    case outputDirectoryNotWritable
    case captureError(Error)
    case alreadyRecording
    case notRecording
    case unknownError(String)
    case unsupportedOS
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .outputDirectoryNotWritable:
            return "Cannot write to the output directory. Please select a different folder in Settings."
        case .captureError(let error):
            return "Capture error: \(error.localizedDescription)"
        case .alreadyRecording:
            return "Recording is already in progress"
        case .notRecording:
            return "No recording is currently active"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        case .unsupportedOS:
            return "This feature requires macOS 15.0 or later"
        }
    }
    
    /// Whether this error should prompt the user to open Settings
    var shouldOpenSettings: Bool {
        switch self {
        case .outputDirectoryNotWritable:
            return true
        default:
            return false
        }
    }
}

/// Recording state for the service
enum RecordingServiceState: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case error(String)
    
    static func == (lhs: RecordingServiceState, rhs: RecordingServiceState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.starting, .starting), (.recording, .recording), (.stopping, .stopping):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

/// Main recording orchestrator that coordinates audio capture
@MainActor
class AudioRecordingService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var state: RecordingServiceState = .idle
    @Published private(set) var currentRecordingURL: URL?
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private var audioCapture: UnifiedAudioCapture?
    private let settings: AppSettings
    private let permissionsManager: PermissionsManager
    
    // MARK: - Initialization
    
    init(settings: AppSettings? = nil, permissionsManager: PermissionsManager) {
        self.settings = settings ?? AppSettings.shared
        self.permissionsManager = permissionsManager
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Check if recording is currently active
    var isRecording: Bool {
        return state == .recording
    }
    
    /// Start recording audio
    @available(macOS 15.0, *)
    func startRecording() async throws {
        guard state == .idle else {
            throw AudioRecordingError.alreadyRecording
        }
        
        print("[AudioRecordingService] Starting recording...")
        state = .starting
        lastError = nil
        
        // Check permissions
        guard permissionsManager.allPermissionsGranted else {
            let error = AudioRecordingError.permissionDenied("Microphone and screen recording permissions are required")
            handleError(error)
            throw error
        }
        
        // Check if output directory is writable
        guard settings.isOutputDirectoryWritable() else {
            let error = AudioRecordingError.outputDirectoryNotWritable
            handleError(error)
            throw error
        }
        
        // Create audio capture
        let capture = UnifiedAudioCapture()
        capture.delegate = self
        self.audioCapture = capture
        
        // Start capture
        do {
            let outputURL = try await capture.startCapture(
                to: settings.outputDirectory,
                format: settings.audioFormat
            )
            currentRecordingURL = outputURL
            state = .recording
            print("[AudioRecordingService] Recording started successfully to: \(outputURL.path)")
        } catch {
            handleError(AudioRecordingError.captureError(error))
            throw AudioRecordingError.captureError(error)
        }
    }
    
    /// Stop recording and save the file
    /// - Returns: The URL of the saved recording
    @available(macOS 15.0, *)
    @discardableResult
    func stopRecording() async throws -> URL {
        guard state == .recording else {
            throw AudioRecordingError.notRecording
        }
        
        print("[AudioRecordingService] Stopping recording...")
        state = .stopping
        
        // Stop audio capture
        guard let capture = audioCapture else {
            let error = AudioRecordingError.notRecording
            handleError(error)
            throw error
        }
        
        do {
            let savedURL = try await capture.stopCapture()
            print("[AudioRecordingService] Recording saved to: \(savedURL.path)")
            
            state = .idle
            audioCapture = nil
            
            // Show notification
            showSaveNotification(url: savedURL)
            
            return savedURL
        } catch {
            handleError(AudioRecordingError.captureError(error))
            throw AudioRecordingError.captureError(error)
        }
    }
    
    /// Cancel recording and delete partial file
    @available(macOS 15.0, *)
    func cancelRecording() async {
        print("[AudioRecordingService] Cancelling recording...")
        
        // Cancel capture - it handles file cleanup
        if let capture = audioCapture {
            await capture.cancelCapture()
        }
        audioCapture = nil
        
        currentRecordingURL = nil
        state = .idle
        
        print("[AudioRecordingService] Recording cancelled")
    }
    
    // MARK: - Private Methods
    
    private func handleError(_ error: Error) {
        print("[AudioRecordingService] Error: \(error.localizedDescription)")
        lastError = error
        state = .error(error.localizedDescription)
        
        // Clean up
        if #available(macOS 15.0, *) {
            Task {
                await cancelRecording()
            }
        }
    }
    
    private func showSaveNotification(url: URL) {
        // Create a user notification for the saved file using UserNotifications framework
        let content = UNMutableNotificationContent()
        content.title = "Recording Saved"
        content.body = url.lastPathComponent
        content.sound = .default
        content.userInfo = ["filePath": url.path]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AudioRecordingService] Failed to show notification: \(error)")
            }
        }
    }
}

// MARK: - UnifiedAudioCaptureDelegate

extension AudioRecordingService: UnifiedAudioCaptureDelegate {
    func unifiedAudioCapture(_ capture: UnifiedAudioCapture, didFinishRecordingTo url: URL) {
        print("[AudioRecordingService] Recording finished to: \(url.path)")
        // Recording completed successfully - notification already shown in stopRecording
    }
    
    func unifiedAudioCapture(_ capture: UnifiedAudioCapture, didFailWithError error: Error) {
        print("[AudioRecordingService] Capture failed: \(error)")
        handleError(AudioRecordingError.captureError(error))
    }
    
    func unifiedAudioCaptureDidStop(_ capture: UnifiedAudioCapture) {
        print("[AudioRecordingService] Capture stopped")
        // If we're still in recording state, this was an unexpected stop
        if state == .recording {
            handleError(AudioRecordingError.unknownError("Audio capture stopped unexpectedly"))
        }
    }
}