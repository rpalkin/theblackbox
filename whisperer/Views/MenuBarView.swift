//
//  MenuBarView.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import SwiftUI
internal import AVFoundation

struct MenuBarView: View {
    @ObservedObject var recordingState: RecordingState
    @ObservedObject var permissionsManager: PermissionsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItem: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with app name
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(recordingState.isRecording ? Color.red : Color.accentColor)
                Text("Whisperer")
                    .font(.headline)
                Spacer()
                if recordingState.isRecording {
                    Text(recordingState.formattedDuration())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            VStack(spacing: 2) {
                // Error section
                if recordingState.showingError, let error = recordingState.lastError {
                    ErrorBannerWithSettings(
                        message: error.localizedDescription,
                        showSettingsButton: recordingState.shouldOpenSettings,
                        onDismiss: { recordingState.dismissError() }
                    )
                    
                    Divider()
                        .padding(.horizontal, 8)
                }
                
                // Permissions section
                if !permissionsManager.allPermissionsGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Permissions Required", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        
                        if permissionsManager.microphoneStatus != .authorized {
                            PermissionRow(
                                icon: "mic.slash.fill",
                                title: "Microphone",
                                status: permissionsManager.microphoneStatus == .notDetermined ? "Not Set" : "Denied",
                                buttonTitle: permissionsManager.microphoneStatus == .notDetermined ? "Allow" : "Open Settings",
                                action: {
                                    if permissionsManager.microphoneStatus == .notDetermined {
                                        Task { await permissionsManager.requestMicrophonePermission() }
                                    } else {
                                        permissionsManager.openSystemSettings(for: .microphone)
                                    }
                                }
                            )
                        }
                        
                        if !permissionsManager.hasScreenRecordingPermission {
                            PermissionRow(
                                icon: "rectangle.dashed.badge.record",
                                title: "Screen Recording",
                                status: "Enable in Settings, then restart app",
                                buttonTitle: "Open Settings",
                                action: {
                                    // Only open settings, don't trigger the system dialog
                                    permissionsManager.openSystemSettings(for: .screenRecording)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 6)
                    
                    Divider()
                        .padding(.horizontal, 8)
                }

                // Recording status indicator
                if recordingState.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: .red.opacity(0.5), radius: 4)
                        Text("Recording in progress...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                
                // Start/Stop Recording button
                MenuButton(
                    icon: recordingState.isRecording ? "stop.circle.fill" : "record.circle",
                    iconColor: recordingState.isRecording ? .red : .primary,
                    title: recordingState.isRecording ? "Stop Recording" : "Start Recording",
                    shortcut: "⌘R",
                    isHovered: hoveredItem == "record",
                    isDisabled: !permissionsManager.allPermissionsGranted
                ) {
                    if recordingState.isRecording {
                        recordingState.stopRecording()
                    } else {
                        recordingState.startRecording()
                    }
                }
                .onHover { hovering in
                    hoveredItem = hovering ? "record" : nil
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!permissionsManager.allPermissionsGranted)
                
                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                MenuButton(
                    icon: "clock.arrow.circlepath",
                    iconColor: .primary,
                    title: "Recording History",
                    shortcut: "⌘H",
                    isHovered: hoveredItem == "history"
                ) {
                    openWindow(id: "recording-history")
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                }
                .onHover { hovering in
                    hoveredItem = hovering ? "history" : nil
                }
                .keyboardShortcut("h", modifiers: [.command])

                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                 
                // Settings button
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        MenuButtonContent(
                            icon: "gear",
                            iconColor: .primary,
                            title: "Settings...",
                            shortcut: "⌘,",
                            isHovered: hoveredItem == "settings"
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredItem = hovering ? "settings" : nil
                    }
                    .keyboardShortcut(",", modifiers: [.command])
                } else {
                    MenuButton(
                        icon: "gear",
                        iconColor: .primary,
                        title: "Settings...",
                        shortcut: "⌘,",
                        isHovered: hoveredItem == "settings"
                    ) {
                        openSettings()
                        dismiss()
                    }
                    .onHover { hovering in
                        hoveredItem = hovering ? "settings" : nil
                    }
                    .keyboardShortcut(",", modifiers: [.command])
                }
                
                // Quit button
                MenuButton(
                    icon: "power",
                    iconColor: .primary,
                    title: "Quit Whisperer",
                    shortcut: "⌘Q",
                    isHovered: hoveredItem == "quit"
                ) {
                    NSApplication.shared.terminate(nil)
                }
                .onHover { hovering in
                    hoveredItem = hovering ? "quit" : nil
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(.vertical, 6)
        }
        .onAppear {
            // Refresh permissions when menu opens
            permissionsManager.refreshPermissions()
        }
    }
    
    private func openSettings() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Supporting Views

struct MenuButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let shortcut: String
    var isHovered: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            MenuButtonContent(
                icon: icon,
                iconColor: iconColor,
                title: title,
                shortcut: shortcut,
                isHovered: isHovered,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct MenuButtonContent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let shortcut: String
    var isHovered: Bool = false
    var isDisabled: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(isDisabled ? Color.secondary.opacity(0.5) : iconColor)
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
            
            Spacer()
            
            Text(shortcut)
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered && !isDisabled ? Color.primary.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 6)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let status: String
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}

struct ErrorBannerWithSettings: View {
    let message: String
    let showSettingsButton: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if showSettingsButton {
                HStack {
                    Spacer()
                    if #available(macOS 14.0, *) {
                        SettingsLink {
                            Text("Open Settings")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Open Settings") {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}

#Preview {
    MenuBarView(recordingState: RecordingState(permissionsManager: PermissionsManager()), permissionsManager: PermissionsManager())
        .frame(width: 260)
}
