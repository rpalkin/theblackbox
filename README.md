# Whisperer - MenuBar Audio Recording Application

## Project Overview

Whisperer is a macOS MenuBar application that records system audio and microphone audio simultaneously using ScreenCaptureKit's SCStreamOutput for audio capture and AVAssetWriter for file recording. The application runs entirely from the menu bar without a main window.

## Technical Requirements

### Platform & Framework
- **Platform**: macOS 13.0+ (required for `captureMicrophone` in SCStreamConfiguration)
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Audio Capture**: ScreenCaptureKit with SCStreamOutput (system audio + microphone capture via separate stream outputs) + AVAssetWriter for file recording

### Key Features
1. **MenuBar-only Application** - No dock icon, no main window
2. **Unified Audio Recording** - System audio + microphone via single SCStream
3. **Settings Window** - Configure output directory
4. **Persistent Settings** - Save user preferences using UserDefaults

---

## Architecture

### Components

```
whisperer/
├── App/
│   └── WhispererApp.swift          # App entry point, MenuBar setup, RecordingState
├── Views/
│   ├── MenuBarView.swift           # Menu bar dropdown content
│   └── SettingsView.swift          # Settings window view
├── Services/
│   ├── AudioRecordingService.swift # Main recording orchestrator
│   └── UnifiedAudioCapture.swift   # ScreenCaptureKit with SCStreamOutput + AVAssetWriter (system + mic + file writing)
├── Models/
│   └── AppSettings.swift           # Settings model with UserDefaults
└── Utilities/
    └── PermissionsManager.swift    # Handle system permissions
```

### Data Flow

```
┌─────────────────────────────────────────────────────┐
│  SCStream with captureMicrophone=true               │
│  + SCStreamOutput (audio + microphone types)        │
│  (System Audio + Microphone via separate outputs)   │
└─────────────────┬───────────────────────────────────┘
                  │
          ┌───────▼───────┐
          │ AVAssetWriter │
          │ (AudioFileWriter)│
          └───────┬───────┘
                  │
          ┌───────▼───────┐
          │  Output File  │
          │  (.m4a/.wav)  │
          └───────────────┘
```

---

## Implementation Tasks

### Phase 1: Project Setup & MenuBar Configuration

- [X] **1.1** Remove default WindowGroup and configure app as MenuBar-only
  - Modify `WhispererApp.swift` to use `MenuBarExtra` instead of `WindowGroup`
  - Set `LSUIElement` to `true` in Info.plist to hide dock icon
  - Create basic menu structure

- [X] **1.2** Create MenuBar UI
  - Add menu bar icon (waveform or microphone symbol)
  - Add "Start Recording" / "Stop Recording" toggle button
  - Add "Settings" menu item
  - Add "Quit" menu item
  - Show recording status indicator (icon change or color)

### Phase 2: Settings Implementation

- [X] **2.1** Create Settings Model
  - Create `AppSettings.swift` with `@AppStorage` for persistence
  - Define default output directory (e.g., `~/Documents/Whisperer`)
  - Define audio format settings (optional: format, quality)

- [X] **2.2** Create Settings Window
  - Create `SettingsView.swift` with SwiftUI
  - Add directory picker using `NSOpenPanel`
  - Add "Browse" button to select output directory
  - Display current selected directory path
  - Add "Reset to Default" button

- [X] **2.3** Implement Settings Window Opening
  - Create separate `Window` scene for settings
  - Handle opening settings window from menu bar
  - Ensure settings window appears in front when opened

### Phase 3: Permissions Management

- [X] **3.1** Create Permissions Manager
  - Create `PermissionsManager.swift`
  - Check and request microphone permission (`AVCaptureDevice.requestAccess`)
  - Check and request screen recording permission (ScreenCaptureKit)
  - Provide user-friendly error messages if permissions denied

- [X] **3.2** Handle Permission States
  - Show permission status in menu (optional)
  - Disable recording button if permissions not granted
  - Guide user to System Preferences if needed

### Phase 4: Unified Audio Capture (ScreenCaptureKit)

- [X] **4.1** Implement Unified Audio Capture Service
  - Create `UnifiedAudioCapture.swift`
  - Initialize `SCShareableContent` to get available displays
  - Create `SCStreamConfiguration` with unified audio capture:
    - `capturesAudio = true` (system audio)
    - `captureMicrophone = true` (microphone, macOS 13+)
    - `excludesCurrentProcessAudio = true` (exclude app's own audio)
  - Configure `SCStream` with audio settings (sample rate, channels)

- [X] **4.2** Handle Unified Audio Stream
  - Implement `SCStreamOutput` protocol via `StreamOutputHandler` class
  - Add stream outputs using `stream.addStreamOutput(handler, type: .audio, ...)` for system audio
  - Add stream outputs using `stream.addStreamOutput(handler, type: .microphone, ...)` for microphone
  - Also add `.screen` output (required even for audio-only capture to prevent errors)
  - Process `CMSampleBuffer` for each audio type separately
  - Handle stream errors and interruptions via `SCStreamDelegate`

- [X] **4.3** Configure Audio Format
  - Set sample rate (48000 Hz recommended for ScreenCaptureKit)
  - Set channel count (mono)
  - Set minimal video dimensions (2x2) since video output is required but not used

### Phase 5: Audio Recording (AVAssetWriter)

- [X] **5.1** Implement File Recording with AVAssetWriter
  - Create `AudioFileWriter` helper class for file writing
  - Configure `AVAssetWriter` with output URL and file type (.m4a)
  - Create separate `AVAssetWriterInput` for system audio and microphone
  - Support M4A format (AAC encoding, 128kbps) for smaller files
  - Generate unique filename with timestamp

- [X] **5.2** Create Recording Orchestrator
  - Create `AudioRecordingService.swift`
  - Coordinate start/stop of unified capture with AVAssetWriter
  - Manage recording state
  - Handle errors gracefully
  - Implement `UnifiedAudioCaptureDelegate` for recording events

### Phase 6: Main Recording Flow (SCStreamOutput + AVAssetWriter)

- [X] **6.1** Implement Start Recording
  - Check permissions before starting (both mic and screen recording)
  - Initialize unified audio capture service
  - Create `AudioFileWriter` with output URL and format settings
  - Create `StreamOutputHandler` that forwards samples to `AudioFileWriter`
  - Add stream outputs using `stream.addStreamOutput()` for screen, audio, and microphone
  - Start SCStream - audio samples flow to AVAssetWriter
  - Update UI to show recording state

- [X] **6.2** Implement Stop Recording
  - Stop SCStream using `stream.stopCapture()`
  - Call `AudioFileWriter.finish()` to finalize the file
  - Mark inputs as finished and call `writer.finishWriting()`
  - File is saved to configured directory
  - Update UI to show idle state
  - Show notification of saved file via UserNotifications

- [X] **6.3** Handle Recording Errors
  - Implement `UnifiedAudioCaptureDelegate` methods for error handling
  - Monitor `AVAssetWriter.status` for failures
  - Display error alerts for failures
  - Clean up partial files on error (delete via FileManager)
  - Return to idle state gracefully

### Phase 7: Polish & Testing

- [ ] **7.1** UI Polish
  - Add recording duration display in menu
  - Add visual feedback for recording state
  - Ensure menu updates correctly during recording

- [ ] **7.2** Error Handling
  - Handle disk full scenarios
  - Handle permission revocation during recording
  - Handle audio device changes during recording

- [ ] **7.3** Testing
  - Test with various audio sources
  - Test long recordings
  - Test settings persistence
  - Test permission flows
  - Test microphone hot-plug during recording

---

## Required Entitlements & Info.plist

### Entitlements (whisperer.entitlements)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

### Info.plist Additions
```xml
<key>LSUIElement</key>
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>Whisperer needs microphone access to record audio.</string>
<key>NSScreenCaptureUsageDescription</key>
<string>Whisperer needs screen recording permission to capture system audio.</string>
```

---

## API References

### ScreenCaptureKit (Unified Audio Capture with SCStreamOutput)
- `SCShareableContent` - Get available content to capture
- `SCContentFilter` - Filter for display-based capture (required even for audio-only)
- `SCStreamConfiguration` - Configure stream settings:
  - `capturesAudio` - Enable system audio capture
  - `captureMicrophone` - Enable microphone capture (macOS 13+)
  - `excludesCurrentProcessAudio` - Exclude app's own audio
  - `sampleRate` - Audio sample rate (48000 Hz)
  - `channelCount` - Number of audio channels (1 for mono)
  - `width`, `height` - Minimal video dimensions (2x2, required but not used)
- `SCStream` - The actual capture stream
- `SCStreamOutput` - Protocol for receiving sample buffers:
  - `stream(_:didOutputSampleBuffer:of:)` - Receive audio/video samples
- `SCStreamOutputType` - Type of output:
  - `.screen` - Video frames (required even for audio-only)
  - `.audio` - System audio samples
  - `.microphone` - Microphone audio samples
- `SCStreamDelegate` - Delegate for stream lifecycle events:
  - `stream(_:didStopWithError:)` - Stream stopped with error

### AVFoundation (File Recording)
- `AVAssetWriter` - Write media to file
- `AVAssetWriterInput` - Input for audio/video data
- `CMSampleBuffer` - Container for audio samples

### SwiftUI (UI)
- `MenuBarExtra` - Menu bar item (macOS 13+)
- `Settings` - Settings scene
- `@AppStorage` - UserDefaults wrapper

---

## Notes for Developers

1. **ScreenCaptureKit Availability**: Requires macOS 13.0+ for `captureMicrophone` feature. Uses `SCStreamOutput` protocol with `AVAssetWriter` for file recording.

2. **Permissions**: Both microphone and screen recording permissions are required. Screen recording permission is needed even for audio-only capture via ScreenCaptureKit.

3. **Audio Streams**: System audio and microphone are captured via separate `SCStreamOutputType` values (`.audio` and `.microphone`). Each type delivers its own `CMSampleBuffer` instances.

4. **Video Output Required**: Even for audio-only capture, a `.screen` output must be added to prevent "stream output NOT found" errors. Minimal 2x2 resolution is used.

5. **File Naming**: Use ISO 8601 timestamp format for filenames: `Recording_2024-01-15_14-30-00.m4a`

6. **AVAssetWriter Architecture**: Uses `AudioFileWriter` helper class with separate `AVAssetWriterInput` for system audio and microphone. This results in a multi-track audio file where system audio and microphone are saved as separate streams (tracks), allowing for independent post-processing. Supports M4A (AAC) format.

7. **Testing Without Sandbox**: During development, you may need to disable sandbox to test screen recording. Re-enable for release.

8. **Delegate Pattern**: Implement `UnifiedAudioCaptureDelegate` to receive recording lifecycle events (finish, error, stop).

---

## Success Criteria

- [ ] App appears only in menu bar (no dock icon, no main window)
- [ ] Can start/stop recording from menu bar
- [ ] Records both system audio and microphone simultaneously
- [ ] Saves combined audio file to user-selected directory
- [ ] Settings persist between app launches
- [ ] Handles permission requests gracefully
- [ ] Provides clear feedback on recording state