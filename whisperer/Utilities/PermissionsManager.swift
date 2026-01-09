//
//  PermissionsManager.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import Foundation
internal import AVFoundation
import ScreenCaptureKit
import AppKit
internal import Combine
import SwiftUI

@MainActor
class PermissionsManager: NSObject, ObservableObject {
    @Published var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @Published var hasScreenRecordingPermission: Bool = false
    
    private var isCheckingPermissions = false
    
    override init() {
        super.init()
        // Initial check
        Task {
            await initialPermissionCheck()
        }
    }
    
    private func initialPermissionCheck() async {
        print("[Permissions] Starting initial check...")
        
        // Check microphone - request if not determined
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[Permissions] Initial mic status: \(micStatus.rawValue)")
        
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print("[Permissions] Mic request result: \(granted)")
        }
        
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[Permissions] Final mic status: \(microphoneStatus.rawValue)")
        
        // Check screen recording
        await checkScreenRecordingPermissionAsync()
    }
    
    func checkMicrophonePermission() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestMicrophonePermission() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    /// Check screen recording permission using SCShareableContent
    /// This is the most reliable method and does NOT show a dialog
    private func checkScreenRecordingPermissionAsync() async {
        print("[Permissions] Checking screen recording...")
        
        // Method 1: CGPreflightScreenCaptureAccess
        let preflightResult = CGPreflightScreenCaptureAccess()
        print("[Permissions] CGPreflight: \(preflightResult)")
        
        if preflightResult {
            hasScreenRecordingPermission = true
            print("[Permissions] Screen recording: GRANTED (via preflight)")
            return
        }
        
        // Method 2: Try SCShareableContent - this does NOT show a dialog
        // It will throw an error if permission is not granted
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let hasDisplays = !content.displays.isEmpty
            print("[Permissions] SCShareableContent: success, displays=\(content.displays.count)")
            hasScreenRecordingPermission = hasDisplays
            if hasDisplays {
                print("[Permissions] Screen recording: GRANTED (via SCShareableContent)")
            }
        } catch {
            print("[Permissions] SCShareableContent error: \(error.localizedDescription)")
            hasScreenRecordingPermission = false
            print("[Permissions] Screen recording: DENIED")
        }
    }
    
    /// Request screen recording permission - this WILL show a dialog
    func requestScreenRecordingPermission() {
        print("[Permissions] Requesting screen recording permission...")
        CGRequestScreenCaptureAccess()
        
        // Poll for permission change
        Task {
            for i in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await checkScreenRecordingPermissionAsync()
                print("[Permissions] Poll \(i+1): hasPermission=\(hasScreenRecordingPermission)")
                if hasScreenRecordingPermission { break }
            }
        }
    }
    
    func openSystemSettings(for type: PermissionType) {
        let urlString: String
        switch type {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        
        print("[Permissions] Opening: \(urlString)")
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    enum PermissionType {
        case microphone
        case screenRecording
    }
    
    var allPermissionsGranted: Bool {
        let result = microphoneStatus == .authorized && hasScreenRecordingPermission
        return result
    }
    
    /// Refresh all permissions - call when menu opens
    func refreshPermissions() {
        guard !isCheckingPermissions else { return }
        isCheckingPermissions = true
        
        print("[Permissions] Refreshing...")
        Task {
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            await checkScreenRecordingPermissionAsync()
            isCheckingPermissions = false
            print("[Permissions] Refresh done: mic=\(microphoneStatus.rawValue), screen=\(hasScreenRecordingPermission)")
        }
    }
}
