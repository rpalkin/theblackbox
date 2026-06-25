//
//  SystemRecordingStopMonitor.swift
//  whisperer
//
//  Created by Roman Palkin on 23.06.2026.
//

import AppKit
import Foundation

enum SystemRecordingStopReason: String {
    case screenLocked = "screen locked"
    case systemWillSleep = "system will sleep"
    case screensDidSleep = "screens did sleep"
    case screensaverStarted = "screensaver started"
}

@MainActor
final class SystemRecordingStopMonitor {
    var onStopRequested: ((SystemRecordingStopReason) -> Void)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    func startMonitoring() {
        guard workspaceObservers.isEmpty, distributedObservers.isEmpty else { return }

        observeWorkspace(NSWorkspace.sessionDidResignActiveNotification, reason: .screenLocked)
        observeWorkspace(NSWorkspace.willSleepNotification, reason: .systemWillSleep)
        observeWorkspace(NSWorkspace.screensDidSleepNotification, reason: .screensDidSleep)
        observeDistributed(Notification.Name("com.apple.screenIsLocked"), reason: .screenLocked)
        observeDistributed(Notification.Name("com.apple.screensaver.didstart"), reason: .screensaverStarted)
    }

    func stopMonitoring() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.removeAll()
        distributedObservers.removeAll()
    }

    private func observeWorkspace(_ name: Notification.Name, reason: SystemRecordingStopReason) {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                print("[SystemRecordingStopMonitor] Stop requested: \(reason.rawValue)")
                self?.onStopRequested?(reason)
            }
        }

        workspaceObservers.append(observer)
    }

    private func observeDistributed(
        _ name: Notification.Name,
        reason: SystemRecordingStopReason
    ) {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                print("[SystemRecordingStopMonitor] Stop requested: \(reason.rawValue)")
                self?.onStopRequested?(reason)
            }
        }

        distributedObservers.append(observer)
    }
}
