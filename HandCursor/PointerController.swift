//
//  PointerController.swift
//  HandCursor
//
//  Converts normalized coordinates to screen space and injects mouse events using CGEvent
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Protocol

protocol PointerControllerProtocol: AnyObject {
    func handleEvent(_ event: GestureEvent)
    func convertToScreenCoordinates(_ normalizedPoint: CGPoint) -> CGPoint
    var isEnabled: Bool { get set }
}

// MARK: - Pointer Controller Implementation

final class PointerController: PointerControllerProtocol {
    
    // MARK: - Properties
    
    var isEnabled: Bool = true
    
    private var isMouseDown: Bool = false
    private var currentScreenPosition: CGPoint = .zero
    
    // MARK: - Initialization
    
    init() {
        // Check accessibility permissions
        checkAccessibilityPermissions()
    }
    
    // MARK: - Public Methods
    
    func handleEvent(_ event: GestureEvent) {
        guard isEnabled else { return }
        
        switch event {
        case .move(let normalizedPoint):
            let screenPoint = convertToScreenCoordinates(normalizedPoint)
            moveCursor(to: screenPoint)
            
        case .mouseDown:
            performMouseDown()
            
        case .mouseUp:
            performMouseUp()
            
        case .click:
            performClick()
        }
    }
    
    func convertToScreenCoordinates(_ normalizedPoint: CGPoint) -> CGPoint {
        // Get main screen bounds
        guard let screen = NSScreen.main else {
            return .zero
        }
        
        let screenFrame = screen.frame
        
        // Vision coordinates: (0,0) is bottom-left, (1,1) is top-right
        // Screen coordinates: (0,0) is top-left
        
        // Invert Y-axis and scale to screen dimensions
        let x = normalizedPoint.x * screenFrame.width + screenFrame.minX
        let y = (1.0 - normalizedPoint.y) * screenFrame.height + screenFrame.minY
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Private Methods
    
    private func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("⚠️ Accessibility permissions required for cursor control")
            print("Please enable in System Settings > Privacy & Security > Accessibility")
        }
    }
    
    private func moveCursor(to point: CGPoint) {
        currentScreenPosition = point
        
        let eventType: CGEventType = isMouseDown ? .leftMouseDragged : .mouseMoved
        
        guard let event = CGEvent(mouseEventSource: nil,
                                  mouseType: eventType,
                                  mouseCursorPosition: point,
                                  mouseButton: .left) else {
            return
        }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func performMouseDown() {
        guard !isMouseDown else { return }
        
        isMouseDown = true
        
        guard let event = CGEvent(mouseEventSource: nil,
                                  mouseType: .leftMouseDown,
                                  mouseCursorPosition: currentScreenPosition,
                                  mouseButton: .left) else {
            return
        }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func performMouseUp() {
        guard isMouseDown else { return }
        
        isMouseDown = false
        
        guard let event = CGEvent(mouseEventSource: nil,
                                  mouseType: .leftMouseUp,
                                  mouseCursorPosition: currentScreenPosition,
                                  mouseButton: .left) else {
            return
        }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func performClick() {
        // Perform a complete click (down + up)
        performMouseDown()
        
        // Small delay between down and up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.performMouseUp()
        }
    }
}

// MARK: - Multi-Display Support

extension PointerController {
    
    /// Convert normalized point to screen coordinates with multi-display support
    func convertToScreenCoordinatesMultiDisplay(_ normalizedPoint: CGPoint) -> CGPoint {
        // Get all screens
        let screens = NSScreen.screens
        
        guard !screens.isEmpty else {
            return .zero
        }
        
        // Calculate total bounds
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        
        for screen in screens {
            let frame = screen.frame
            minX = min(minX, frame.minX)
            maxX = max(maxX, frame.maxX)
            minY = min(minY, frame.minY)
            maxY = max(maxY, frame.maxY)
        }
        
        let totalWidth = maxX - minX
        let totalHeight = maxY - minY
        
        // Convert normalized to total screen space
        let x = normalizedPoint.x * totalWidth + minX
        let y = (1.0 - normalizedPoint.y) * totalHeight + minY
        
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Coordinate Transformation Utilities

extension PointerController {
    
    /// Get the screen containing a specific point
    static func screen(containing point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.main
    }
    
    /// Clamp point to screen bounds
    static func clamp(_ point: CGPoint, to screen: NSScreen) -> CGPoint {
        let frame = screen.frame
        return CGPoint(
            x: max(frame.minX, min(point.x, frame.maxX)),
            y: max(frame.minY, min(point.y, frame.maxY))
        )
    }
}
