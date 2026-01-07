# Changelog

## [1.1.0] - 2026-01-07

### Added
- AppController for centralized pipeline orchestration with threading and frame dropping
- PermissionManager for camera and accessibility permission handling
- FPS and latency metrics tracking and display
- Permission status UI with buttons to open System Settings
- Info.plist with camera usage description

### Changed
- Replaced HandCursorCoordinator with AppController for better separation of concerns
- Vision processing now runs on dedicated queue with frame dropping for low latency
- UI updated to show FPS, latency, and permission warnings

## [1.0.2] - 2026-01-07

### Fixed
- GestureEngine now emits mouseUp when hand is lost while in down/drag state
- Proper debounce timing: pinch must be held for debounceTime before triggering

### Improved
- PointerController now supports multi-display coordinate mapping by default
- Added dead zone (1px) to reduce cursor jitter from tiny movements
- Cursor position now clamped to screen bounds

## [1.0.1] - 2026-01-06

### Fixed
- Fixed hand tracking not reflecting cursor movement on screen
- Fixed CVPixelBuffer threading issues with synchronous capture queue processing

### Improved
- Optimized camera capture with locked 30fps frame rate
- Reduced latency with proper camera device configuration
- Simplified codebase by removing unused delegate pattern

## [1.0.0] - 2026-01-06

### Added
- Initial release
- Hand tracking using Vision framework
- Cursor control with index finger pointing
- Pinch gesture for click
- Pinch + drag gesture support
- One Euro Filter for smooth cursor movement
- Real-time gesture state display
