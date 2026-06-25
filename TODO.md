# TODO: Auto-Stop Recording When Zoom Meeting Ends

## Phase 1: Window Logging (Completed)
- [x] Create `whisperer/Services/WindowMonitorService.swift`
- [x] Modify `whisperer/Services/AudioRecordingService.swift` to start/stop monitoring
- [x] Verify build

## Phase 2: Zoom Detection (Next)

### Overview
When recording is active and ANY Zoom window closes, a floating popup with a subtle blinking background appears below the Whisperer menu bar icon. The popup stays visible until the user clicks "Stop Recording" (stops and dismisses) or "Keep Recording" (dismisses, monitoring continues).

### Files to Create

| File | Description |
|------|-------------|
| `Views/ZoomEndedPopupView.swift` | SwiftUI view with blinking background effect |
| `Views/ZoomEndedPopupWindow.swift` | NSPanel wrapper + `PopupWindowManager` singleton |

### Files to Modify

| File | Description |
|------|-------------|
| `Services/WindowMonitorService.swift` | Zoom-only tracking, delegate, 10s polling |
| `Services/AudioRecordingService.swift` | Implement delegate, add callback |
| `whispererApp.swift` | Wire callback to show popup via manager |

### Tasks
- [x] Update WindowMonitorService to track only Zoom windows (`us.zoom.xos`) and detect closes
- [x] Add `WindowMonitorServiceDelegate` protocol to notify about Zoom window closes
- [x] Change polling interval from 30s to 10s
- [x] Create `ZoomEndedPopupView.swift` - SwiftUI view with blinking orange background
- [x] Create `ZoomEndedPopupWindow.swift` - NSPanel (floating, all spaces) + `PopupWindowManager` singleton
- [x] Modify `AudioRecordingService` to implement delegate and add `onZoomWindowClosed` callback
- [x] Modify `RecordingState` to wire callback to `PopupWindowManager.shared.showPopup()`
- [x] Configure `PopupWindowManager` in `WhispererApp.init`

### Flow
1. User starts recording → `WindowMonitorService` starts tracking Zoom windows
2. User joins Zoom meeting → Zoom windows appear, get tracked
3. User leaves/ends meeting → Zoom window(s) close
4. `WindowMonitorService` detects close → calls delegate
5. `AudioRecordingService` receives delegate call → invokes `onZoomWindowClosed` callback
6. `RecordingState` callback → calls `PopupWindowManager.shared.showPopup()`
7. Floating popup appears below menu icon with blinking orange background
8. User clicks:
   - **"Stop Recording"** → `recordingState.stopRecording()` + hide popup
   - **"Keep Recording"** → hide popup, monitoring continues for next Zoom close

### Popup Specifications
- **Position**: Below Whisperer menu bar icon
- **Style**: Same as MenuBarView (260px width)
- **Window type**: NSPanel, floating level, visible on all spaces
- **Background**: Subtle blinking orange (opacity 0.05 ↔ 0.15, 0.8s cycle)
- **Buttons**: "Keep Recording" (bordered), "Stop Recording" (borderedProminent, red)
