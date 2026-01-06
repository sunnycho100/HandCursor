//
//  GestureEngine.swift
//  HandCursor
//
//  Interprets hand gestures using state machine with debouncing and hysteresis
//

import Foundation
import CoreGraphics

// MARK: - Protocol

protocol GestureEngineProtocol: AnyObject {
    var delegate: GestureEngineDelegate? { get set }
    func processFrame(_ handFrame: HandFrame, smoothedPoint: SmoothedPoint)
    func reset()
    var currentState: GestureState { get }
}

protocol GestureEngineDelegate: AnyObject {
    func gestureEngine(_ engine: GestureEngineProtocol, didEmit event: GestureEvent)
    func gestureEngine(_ engine: GestureEngineProtocol, didChangeState newState: GestureState)
}

// MARK: - Gesture Engine Implementation

final class GestureEngine: GestureEngineProtocol {
    
    // MARK: - Properties
    
    weak var delegate: GestureEngineDelegate?
    
    private(set) var currentState: GestureState = .idle
    
    // Configuration
    private let pinchThreshold: CGFloat
    private let pinchHysteresis: CGFloat
    private let debounceTime: TimeInterval
    private let clickTimeout: TimeInterval
    
    // State tracking
    private var lastPinchDistance: CGFloat?
    private var lastStateChange: CFTimeInterval = 0
    private var mouseDownPosition: CGPoint?
    private var mouseDownTime: CFTimeInterval?
    private var lastCursorPosition: CGPoint?
    
    // MARK: - Initialization
    
    init(
        pinchThreshold: CGFloat = 0.05,
        pinchHysteresis: CGFloat = 0.02,
        debounceTime: TimeInterval = 0.1,
        clickTimeout: TimeInterval = 0.3
    ) {
        self.pinchThreshold = pinchThreshold
        self.pinchHysteresis = pinchHysteresis
        self.debounceTime = debounceTime
        self.clickTimeout = clickTimeout
    }
    
    // MARK: - Public Methods
    
    func processFrame(_ handFrame: HandFrame, smoothedPoint: SmoothedPoint) {
        // Check if hand is detected
        guard !handFrame.landmarks.isEmpty else {
            transitionTo(.idle, at: handFrame.timestamp)
            return
        }
        
        // Calculate pinch distance
        guard let pinchDistance = handFrame.pinchDistance else {
            transitionTo(.idle, at: handFrame.timestamp)
            return
        }
        
        // Get pointer position (use index tip as primary pointer)
        let pointerPosition = smoothedPoint.point
        
        // Determine if pinched
        let isPinched = evaluatePinch(distance: pinchDistance, timestamp: handFrame.timestamp)
        
        // State machine
        switch currentState {
        case .idle:
            transitionTo(.tracking, at: handFrame.timestamp)
            emitEvent(.move(pointerPosition))
            
        case .tracking:
            if isPinched {
                transitionTo(.down, at: handFrame.timestamp)
                emitEvent(.mouseDown)
                mouseDownPosition = pointerPosition
                mouseDownTime = handFrame.timestamp
            } else {
                emitEvent(.move(pointerPosition))
            }
            
        case .down:
            if !isPinched {
                // Check if it was a click (no significant movement + short duration)
                if let downPos = mouseDownPosition,
                   let downTime = mouseDownTime,
                   distance(from: downPos, to: pointerPosition) < 0.02,
                   handFrame.timestamp - downTime < clickTimeout {
                    emitEvent(.click)
                } else {
                    emitEvent(.mouseUp)
                }
                transitionTo(.tracking, at: handFrame.timestamp)
                mouseDownPosition = nil
                mouseDownTime = nil
            } else {
                // Check for drag (movement while pinched)
                if let downPos = mouseDownPosition,
                   distance(from: downPos, to: pointerPosition) > 0.01 {
                    transitionTo(.drag, at: handFrame.timestamp)
                }
            }
            
        case .drag:
            if !isPinched {
                emitEvent(.mouseUp)
                transitionTo(.tracking, at: handFrame.timestamp)
                mouseDownPosition = nil
                mouseDownTime = nil
            } else {
                emitEvent(.move(pointerPosition))
            }
            
        case .clutch:
            // Reserved for future use (e.g., hand closed to freeze cursor)
            if !isPinched {
                transitionTo(.tracking, at: handFrame.timestamp)
            }
        }
        
        lastCursorPosition = pointerPosition
        lastPinchDistance = pinchDistance
    }
    
    func reset() {
        currentState = .idle
        lastPinchDistance = nil
        lastStateChange = 0
        mouseDownPosition = nil
        mouseDownTime = nil
        lastCursorPosition = nil
    }
    
    // MARK: - Private Methods
    
    private func evaluatePinch(distance: CGFloat, timestamp: CFTimeInterval) -> Bool {
        // Apply hysteresis to prevent fluttering
        let threshold = currentState == .down || currentState == .drag
            ? pinchThreshold + pinchHysteresis
            : pinchThreshold
        
        return distance < threshold
    }
    
    private func transitionTo(_ newState: GestureState, at timestamp: CFTimeInterval) {
        guard newState != currentState else { return }
        
        // Check debounce time
        let timeSinceLastChange = timestamp - lastStateChange
        if timeSinceLastChange < debounceTime && newState != .idle {
            return
        }
        
        currentState = newState
        lastStateChange = timestamp
        delegate?.gestureEngine(self, didChangeState: newState)
    }
    
    private func emitEvent(_ event: GestureEvent) {
        delegate?.gestureEngine(self, didEmit: event)
    }
    
    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Gesture Configuration

extension GestureEngine {
    
    struct Configuration {
        var pinchThreshold: CGFloat
        var pinchHysteresis: CGFloat
        var debounceTime: TimeInterval
        var clickTimeout: TimeInterval
        
        static let `default` = Configuration(
            pinchThreshold: 0.05,
            pinchHysteresis: 0.02,
            debounceTime: 0.1,
            clickTimeout: 0.3
        )
        
        static let sensitive = Configuration(
            pinchThreshold: 0.06,
            pinchHysteresis: 0.015,
            debounceTime: 0.05,
            clickTimeout: 0.25
        )
        
        static let relaxed = Configuration(
            pinchThreshold: 0.04,
            pinchHysteresis: 0.025,
            debounceTime: 0.15,
            clickTimeout: 0.4
        )
    }
}
