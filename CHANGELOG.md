# Changelog

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
