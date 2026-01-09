//
//  whispererApp.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import SwiftUI
internal import Combine

@main
struct WhispererApp: App {
    @StateObject private var permissionsManager = PermissionsManager()
    @StateObject private var recordingState: RecordingState
    
    init() {
        let permissions = PermissionsManager()
        _permissionsManager = StateObject(wrappedValue: permissions)
        _recordingState = StateObject(wrappedValue: RecordingState(permissionsManager: permissions))
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(recordingState: recordingState, permissionsManager: permissionsManager)
                .frame(width: 260)
        } label: {
            Label {
                Text("Whisperer")
            } icon: {
                Image(systemName: recordingState.isRecording ? "waveform.circle.fill" : "waveform.circle")
            }
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}

/// Observable class to manage recording state across the app
/// Uses UnifiedAudioCapture for recording
@MainActor
class RecordingState: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastError: Error?
    @Published var showingError: Bool = false
    @Published var shouldOpenSettings: Bool = false
    @Published var currentRecordingURL: URL?
    
    private var timerTask: Task<Void, Never>?
    private let recordingService: AudioRecordingService
    
    init(permissionsManager: PermissionsManager) {
        self.recordingService = AudioRecordingService(permissionsManager: permissionsManager)
    }
    
    func startRecording() {
        Task {
            await startRecordingAsync()
        }
    }
    
    @available(macOS 15.0, *)
    private func startRecordingAsync() async {
        do {
            try await recordingService.startRecording()
            isRecording = true
            recordingDuration = 0
            currentRecordingURL = recordingService.currentRecordingURL
            startTimer()
            print("[RecordingState] Recording started")
        } catch {
            print("[RecordingState] Failed to start recording: \(error)")
            handleError(error)
        }
    }
    
    func stopRecording() {
        Task {
            await stopRecordingAsync()
        }
    }
    
    @available(macOS 15.0, *)
    private func stopRecordingAsync() async {
        stopTimer()
        
        do {
            let savedURL = try await recordingService.stopRecording()
            isRecording = false
            currentRecordingURL = savedURL
            print("[RecordingState] Recording saved to: \(savedURL.path)")
        } catch {
            print("[RecordingState] Failed to stop recording: \(error)")
            isRecording = false
            handleError(error)
        }
    }
    
    func cancelRecording() {
        Task {
            await cancelRecordingAsync()
        }
    }
    
    @available(macOS 15.0, *)
    private func cancelRecordingAsync() async {
        stopTimer()
        await recordingService.cancelRecording()
        isRecording = false
        currentRecordingURL = nil
        print("[RecordingState] Recording cancelled")
    }
    
    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    recordingDuration += 1
                }
            }
        }
    }
    
    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
    
    private func handleError(_ error: Error) {
        lastError = error
        showingError = true
        
        // Check if this error should prompt opening Settings
        if let recordingError = error as? AudioRecordingError, recordingError.shouldOpenSettings {
            shouldOpenSettings = true
        }
    }
    
    func dismissError() {
        showingError = false
        lastError = nil
        shouldOpenSettings = false
    }
    
    func formattedDuration() -> String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
