//
//  WindowMonitorService.swift
//  whisperer
//
//  Created by Roman Palkin on 04.02.2026.
//

import Foundation
import ScreenCaptureKit

/// Delegate protocol for WindowMonitorService to notify about Zoom window close events
protocol WindowMonitorServiceDelegate: AnyObject {
    /// Called when any tracked Zoom window closes
    func windowMonitorServiceDidDetectZoomWindowClose(_ service: WindowMonitorService)
}

/// Monitors open windows using ScreenCaptureKit for detecting Zoom meeting app
class WindowMonitorService {
    
    // MARK: - Constants
    
    private static let zoomBundleID = "us.zoom.xos"
    
    // MARK: - Properties
    
    weak var delegate: WindowMonitorServiceDelegate?
    
    private var pollingTask: Task<Void, Never>?
    private var trackedZoomWindowIDs: Set<CGWindowID> = []
    private let pollingInterval: TimeInterval = 10.0
    
    // MARK: - Public Methods
    
    /// Start monitoring Zoom windows - polls every 10 seconds and detects window close events
    func startMonitoring() {
        print("[WindowMonitor] Starting Zoom window monitoring...")
        
        pollingTask = Task {
            // Initial snapshot
            await captureZoomWindowSnapshot()
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollingInterval))
                guard !Task.isCancelled else { break }
                await pollAndCheckZoomWindows()
            }
        }
    }
    
    /// Stop monitoring windows
    func stopMonitoring() {
        print("[WindowMonitor] Stopping Zoom window monitoring")
        pollingTask?.cancel()
        pollingTask = nil
        trackedZoomWindowIDs.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// Capture initial snapshot of Zoom windows for tracking closes
    private func captureZoomWindowSnapshot() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        ) else {
            print("[WindowMonitor] Failed to get shareable content")
            return
        }
        
        let zoomWindows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == Self.zoomBundleID
        }
        
        trackedZoomWindowIDs = Set(zoomWindows.map { $0.windowID })
        
        if !trackedZoomWindowIDs.isEmpty {
            print("[WindowMonitor] Initial Zoom windows tracked: \(trackedZoomWindowIDs.sorted())")
            logZoomWindows(zoomWindows)
        } else {
            print("[WindowMonitor] No Zoom windows currently open")
        }
    }
    
    /// Poll for Zoom windows and detect closes
    private func pollAndCheckZoomWindows() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        ) else {
            print("[WindowMonitor] Failed to get shareable content")
            return
        }
        
        let zoomWindows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == Self.zoomBundleID
        }
        
        let currentZoomWindowIDs = Set(zoomWindows.map { $0.windowID })
        
        // Detect closed Zoom windows
        let closedZoomWindowIDs = trackedZoomWindowIDs.subtracting(currentZoomWindowIDs)
        
        if !closedZoomWindowIDs.isEmpty {
            print("[WindowMonitor] === ZOOM WINDOWS CLOSED: \(closedZoomWindowIDs.sorted()) ===")
            
            // Notify delegate about Zoom window close
            await MainActor.run {
                delegate?.windowMonitorServiceDidDetectZoomWindowClose(self)
            }
        }
        
        // Log current state if there are Zoom windows
        if !currentZoomWindowIDs.isEmpty {
            logZoomWindows(zoomWindows)
        } else if !trackedZoomWindowIDs.isEmpty {
            print("[WindowMonitor] All Zoom windows have closed")
        }
        
        // Update tracked windows for next poll
        trackedZoomWindowIDs = currentZoomWindowIDs
    }
    
    /// Log Zoom windows to console
    private func logZoomWindows(_ windows: [SCWindow]) {
        print("[WindowMonitor] === ZOOM WINDOWS (\(windows.count)) ===")
        for window in windows {
            let title = window.title ?? "untitled"
            let onScreen = window.isOnScreen
            print("[WindowMonitor] [\(window.windowID)] Zoom | \"\(title)\" | onScreen: \(onScreen)")
        }
        print("[WindowMonitor] ==============================")
    }
}
