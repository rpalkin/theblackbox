# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whisperer is a macOS MenuBar-only audio recording application that captures system audio and microphone simultaneously using ScreenCaptureKit and AVAssetWriter.

## Build and Run

This is an Xcode project. Open `whisperer.xcodeproj` in Xcode:
- Build: Cmd+B
- Run: Cmd+R
- The app runs from the menu bar only (no dock icon)

No test targets exist currently - testing is manual.

## Architecture

```
WhispererApp (MenuBarExtra entry point)
└── RecordingState (@MainActor ObservableObject)
    ├── AudioRecordingService (recording orchestrator)
    │   └── UnifiedAudioCapture (ScreenCaptureKit wrapper)
    │       └── AudioFileWriter (AVAssetWriter for dual-track M4A)
    └── PermissionsManager (microphone + screen recording permissions)
```

### Key Files

- `whispererApp.swift` - App entry, MenuBarExtra setup, RecordingState class
- `Services/AudioRecordingService.swift` - Coordinates recording lifecycle, validates permissions
- `Services/UnifiedAudioCapture.swift` - SCStream with dual audio outputs + AVAssetWriter file writing
- `Models/AppSettings.swift` - Singleton (`AppSettings.shared`) wrapping UserDefaults
- `Utilities/PermissionsManager.swift` - AVCaptureDevice + ScreenCaptureKit permission handling

### Audio Capture Details

Single SCStream captures both audio sources via separate SCStreamOutputType values:
- `.screen` - Required even for audio-only (minimal 2x2 video)
- `.audio` - System audio
- `.microphone` - Microphone input

Output: Multi-track M4A (AAC 128kbps, 48kHz mono) with system and mic as separate tracks.

### Platform Requirements

- macOS 13.0+ (for `captureMicrophone` in SCStreamConfiguration)
- macOS 15.0+ for async/await stream operations

### Required Entitlements

- App Sandbox
- Audio Input (`device.audio-input`)
- Screen Recording
- User-selected file read-write access

### Permission Flow

Both microphone AND screen recording permissions required. Screen recording uses `CGPreflightScreenCaptureAccess` for detection (no dialog on first check - user must grant in System Settings).

## State Management

Uses SwiftUI's `@StateObject`, `@Published`, `@ObservedObject` pattern. RecordingState tracks:
- Recording state enum (idle/starting/recording/stopping/error)
- Duration via Task-based timer
- Error messages for UI display

## Zoom Meeting Detection

`WindowMonitorService.swift` monitors Zoom windows (`us.zoom.xos`) via `SCShareableContent` polling (10s interval):
- Tracks Zoom window IDs between polls to detect closes
- Uses delegate pattern to notify `AudioRecordingService` of window close events
- Started/stopped automatically with recording lifecycle

When a Zoom window closes during recording:
1. `WindowMonitorService` detects close → calls delegate
2. `AudioRecordingService` invokes `onZoomWindowClosed` callback
3. `RecordingState` triggers `PopupWindowManager.shared.showPopup()`
4. Floating NSPanel appears below menu bar with "Stop Recording" / "Keep Recording" options

### Key Files for Zoom Detection
- `Services/WindowMonitorService.swift` - Zoom window polling + delegate
- `Views/ZoomEndedPopupView.swift` - SwiftUI popup with blinking orange background
- `Views/ZoomEndedPopupWindow.swift` - NSPanel wrapper + `PopupWindowManager` singleton

## System Stop Triggers

`SystemRecordingStopMonitor.swift` observes `NSWorkspace` and distributed notifications to auto-stop recording on screen lock, system sleep, screens sleep, and screensaver start. Uses an `onStopRequested(reason)` callback wired through `AudioRecordingService`.

## Design Decisions

- **Dual-track audio**: System audio and microphone recorded as separate AVAssetWriter inputs (not mixed) for post-processing flexibility
- **Minimal video capture**: SCStream requires video output; uses 2x2 resolution to minimize overhead
- **Task-based concurrency**: Uses Swift structured concurrency (`Task`, `async/await`) throughout instead of Combine or GCD timers
- **Polling vs notifications**: Window monitoring uses polling since macOS lacks reliable window close notifications for arbitrary apps
