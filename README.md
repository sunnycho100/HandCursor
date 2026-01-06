# HandCursor

A macOS application that uses camera-based hand tracking to control the cursor with gesture recognition for clicks and dragging.

## Architecture Overview

HandCursor is built as a modular pipeline that processes camera frames through hand tracking, gesture recognition, and cursor control. The app leverages Apple's Vision framework for hand pose detection and Core Graphics for system-level cursor control.

### Pipeline Modules

```
Camera → Hand Tracking → Stabilization → Gesture Engine → Pointer Controller
```

#### 1. CaptureService
**Purpose**: Captures video frames from the Mac's camera using AVFoundation.

**Responsibilities**:
- Initialize and configure AVCaptureSession
- Manage camera device selection and permissions
- Output frames as CVPixelBuffer with timestamps

**Outputs**:
- `CVPixelBuffer`: Raw camera frame data
- `timestamp`: Frame capture timestamp

---

#### 2. HandTrackingService
**Purpose**: Detects hand landmarks using Apple's Vision framework.

**Responsibilities**:
- Process frames with `VNDetectHumanHandPoseRequest`
- Extract hand landmark positions
- Provide confidence scores for detected hands

**Outputs**:
- Normalized landmarks (0.0–1.0 coordinate space)
- Confidence scores for hand detection
- Key points: thumb tip, index finger tip, etc.

---

#### 3. StabilizationLayer
**Purpose**: Smooths landmark positions to reduce jitter and noise.

**Responsibilities**:
- Apply filtering algorithms (One Euro Filter or Exponential Moving Average)
- Stabilize pointer position and pinch distance
- Balance responsiveness vs. smoothness

**Outputs**:
- Smoothed pointer point (x, y)
- Filtered pinch distance

---

#### 4. GestureEngine
**Purpose**: Interprets hand gestures and maintains interaction state.

**State Machine**:
- `idle`: No hand detected or hand not in active zone
- `tracking`: Hand detected, cursor following
- `clutch`: Hand closed/hidden, cursor frozen
- `down`: Pinch detected, mouse button pressed
- `drag`: Mouse down + movement, dragging operation

**Responsibilities**:
- Detect pinch gestures with threshold + hysteresis
- Implement debouncing with time thresholds
- Generate high-level interaction events

**Outputs**:
- `move(x, y)`: Cursor movement command
- `mouseDown`: Press event
- `mouseUp`: Release event
- `click`: Complete click gesture

---

#### 5. PointerController
**Purpose**: Translates normalized coordinates to screen space and injects mouse events.

**Responsibilities**:
- Convert normalized (0.0–1.0) to screen coordinates
- Handle multi-display setups using NSScreen bounds
- Inject system mouse events via CGEvent API
- Manage cursor visibility and acceleration

**CGEvent Operations**:
- `mouseMoved`: Move cursor
- `leftMouseDown`: Press button
- `leftMouseUp`: Release button
- `leftMouseDragged`: Drag operation

---

#### 6. App Orchestrator
**Purpose**: Coordinates all modules and manages the application lifecycle.

**Responsibilities**:
- Initialize and wire all pipeline modules
- Run the main capture/processing loop
- Handle app lifecycle (start, stop, pause)
- Manage settings and configuration
- Coordinate frame flow: Camera → Vision → Filter → Gesture → Cursor

---

## Implementation TODO Stack

### Phase 1: Foundation & Camera Setup
- [ ] Set up Xcode project structure with modular architecture
- [ ] Create protocol definitions for each service
- [ ] Implement `CaptureService`
  - [ ] Request camera permissions
  - [ ] Configure AVCaptureSession
  - [ ] Set up video output delegate
  - [ ] Test frame capture and display

### Phase 2: Hand Detection
- [ ] Implement `HandTrackingService`
  - [ ] Configure VNDetectHumanHandPoseRequest
  - [ ] Process CVPixelBuffer frames
  - [ ] Extract hand landmarks (thumb tip, index tip)
  - [ ] Handle missing hand scenarios
  - [ ] Add confidence thresholding
- [ ] Create visualization overlay for debugging landmarks

### Phase 3: Stabilization & Filtering
- [ ] Implement `StabilizationLayer`
  - [ ] Research and select filter (One Euro vs. EMA)
  - [ ] Implement position filtering
  - [ ] Implement pinch distance filtering
  - [ ] Add configurable smoothing parameters
  - [ ] Test filter performance and latency

### Phase 4: Gesture Recognition
- [ ] Implement `GestureEngine`
  - [ ] Design state machine structure
  - [ ] Calculate pinch distance (thumb-index)
  - [ ] Implement pinch threshold with hysteresis
  - [ ] Add debounce logic with time thresholds
  - [ ] Implement state transitions
  - [ ] Generate gesture events
- [ ] Test gesture detection accuracy
- [ ] Tune thresholds for reliability

### Phase 5: Cursor Control
- [ ] Implement `PointerController`
  - [ ] Request accessibility permissions for CGEvent
  - [ ] Implement coordinate transformation
  - [ ] Handle multi-display screen mapping
  - [ ] Inject mouse move events
  - [ ] Inject mouse down/up events
  - [ ] Handle drag operations
- [ ] Test cursor control smoothness
- [ ] Test multi-monitor support

### Phase 6: App Integration
- [ ] Implement `App Orchestrator`
  - [ ] Wire all modules together
  - [ ] Create processing pipeline
  - [ ] Implement start/stop controls
  - [ ] Add error handling and recovery
  - [ ] Implement performance monitoring
- [ ] Build minimal SwiftUI interface
  - [ ] Toggle on/off control
  - [ ] Status indicators
  - [ ] Settings panel

### Phase 7: Polish & Optimization
- [ ] Add configuration UI
  - [ ] Sensitivity adjustment
  - [ ] Pinch threshold tuning
  - [ ] Filter smoothing controls
- [ ] Optimize performance
  - [ ] Profile frame processing latency
  - [ ] Optimize hand detection frequency
  - [ ] Reduce CPU usage
- [ ] Add visual feedback
  - [ ] Hand tracking indicator
  - [ ] Gesture state visualization
  - [ ] On-screen cursor preview

### Phase 8: Testing & Refinement
- [ ] Test edge cases
  - [ ] Multiple hands
  - [ ] Partial occlusion
  - [ ] Varying lighting conditions
- [ ] User testing for gesture reliability
- [ ] Fine-tune all thresholds and parameters
- [ ] Add logging and diagnostics

### Phase 9: Distribution
- [ ] Create app icon and assets
- [ ] Add menu bar interface
- [ ] Implement launch at login
- [ ] Create installer/distribution package
- [ ] Write user documentation

---

## Key Technical Decisions

### Frameworks
- **AVFoundation**: Camera capture
- **Vision**: Hand pose detection
- **CoreGraphics**: Cursor control (CGEvent)
- **SwiftUI**: User interface

### Algorithms
- **Filtering**: One Euro Filter or Exponential Moving Average
- **Gesture Detection**: Threshold + hysteresis + debounce
- **State Machine**: Explicit state enum with transition logic

### Permissions Required
- Camera access (AVCaptureDevice)
- Accessibility (CGEvent posting)

---

## Development Notes

### Coordinate Spaces
- Vision framework: (0, 0) at bottom-left, (1, 1) at top-right
- Screen coordinates: (0, 0) at top-left
- Requires Y-axis inversion during transformation

### Performance Targets
- Frame processing: < 16ms (60 FPS)
- End-to-end latency: < 50ms
- CPU usage: < 20% on modern Macs

### Testing Strategy
- Unit tests for each module
- Integration tests for pipeline
- Manual testing for gesture UX
- Performance profiling with Instruments

---

## Future Enhancements
- Two-hand gestures (scroll, zoom)
- Configurable gesture mappings
- Multi-finger tracking
- Machine learning for custom gestures
- Haptic feedback integration
