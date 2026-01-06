//
//  StabilizationLayer.swift
//  HandCursor
//
//  Smooths hand landmark positions to reduce jitter using filtering
//

import Foundation
import CoreGraphics

// MARK: - Protocol

protocol StabilizationLayerProtocol: AnyObject {
    func smooth(point: CGPoint, timestamp: CFTimeInterval) -> SmoothedPoint
    func smooth(value: CGFloat, timestamp: CFTimeInterval, key: String) -> CGFloat
    func reset()
}

// MARK: - Stabilization Layer Implementation

final class StabilizationLayer: StabilizationLayerProtocol {
    
    // MARK: - Properties
    
    private let smoothingFactor: CGFloat
    private let velocityThreshold: CGFloat
    
    private var smoothedX: CGFloat?
    private var smoothedY: CGFloat?
    private var lastTimestamp: CFTimeInterval?
    
    // Storage for arbitrary values (e.g., pinch distance)
    private var smoothedValues: [String: CGFloat] = [:]
    
    // MARK: - Initialization
    
    init(smoothingFactor: CGFloat = 0.3, velocityThreshold: CGFloat = 0.1) {
        self.smoothingFactor = smoothingFactor
        self.velocityThreshold = velocityThreshold
    }
    
    // MARK: - Public Methods
    
    func smooth(point: CGPoint, timestamp: CFTimeInterval) -> SmoothedPoint {
        // Initialize on first point
        if smoothedX == nil || smoothedY == nil {
            smoothedX = point.x
            smoothedY = point.y
            lastTimestamp = timestamp
            return SmoothedPoint(point: point, timestamp: timestamp, rawPoint: point)
        }
        
        // Calculate time delta
        let dt = timestamp - (lastTimestamp ?? timestamp)
        let adaptiveFactor = calculateAdaptiveFactor(dt: dt)
        
        // Apply exponential moving average
        smoothedX = applyEMA(current: smoothedX!, new: point.x, factor: adaptiveFactor)
        smoothedY = applyEMA(current: smoothedY!, new: point.y, factor: adaptiveFactor)
        
        lastTimestamp = timestamp
        
        let smoothedPoint = CGPoint(x: smoothedX!, y: smoothedY!)
        return SmoothedPoint(point: smoothedPoint, timestamp: timestamp, rawPoint: point)
    }
    
    func smooth(value: CGFloat, timestamp: CFTimeInterval, key: String) -> CGFloat {
        guard let current = smoothedValues[key] else {
            smoothedValues[key] = value
            return value
        }
        
        let dt = timestamp - (lastTimestamp ?? timestamp)
        let adaptiveFactor = calculateAdaptiveFactor(dt: dt)
        
        let smoothed = applyEMA(current: current, new: value, factor: adaptiveFactor)
        smoothedValues[key] = smoothed
        
        return smoothed
    }
    
    func reset() {
        smoothedX = nil
        smoothedY = nil
        lastTimestamp = nil
        smoothedValues.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// Apply Exponential Moving Average filter
    private func applyEMA(current: CGFloat, new: CGFloat, factor: CGFloat) -> CGFloat {
        return current * (1.0 - factor) + new * factor
    }
    
    /// Calculate adaptive smoothing factor based on velocity
    private func calculateAdaptiveFactor(dt: CFTimeInterval) -> CGFloat {
        // Adjust smoothing based on time delta to maintain consistent behavior
        // regardless of frame rate
        let normalizedDt = CGFloat(min(dt, 0.1) / 0.016) // Normalize to ~60fps
        return smoothingFactor * normalizedDt
    }
}

// MARK: - One Euro Filter (Advanced Alternative)

/// One Euro Filter - more sophisticated filter with cutoff frequency adaptation
final class OneEuroFilter {
    
    // MARK: - Configuration
    
    struct Config {
        let minCutoff: Double       // Minimum cutoff frequency (lower = more smoothing)
        let beta: Double            // Cutoff slope (higher = more responsive to velocity)
        let dCutoff: Double         // Derivative cutoff frequency
        
        static let `default` = Config(
            minCutoff: 1.0,
            beta: 0.007,
            dCutoff: 1.0
        )
    }
    
    // MARK: - Properties
    
    private let config: Config
    private var xFilter: LowPassFilter?
    private var dxFilter: LowPassFilter?
    private var lastTimestamp: Double?
    
    // MARK: - Initialization
    
    init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public Methods
    
    func filter(value: Double, timestamp: Double) -> Double {
        // Initialize on first value
        if xFilter == nil {
            xFilter = LowPassFilter(alpha: alpha(cutoff: config.minCutoff))
            dxFilter = LowPassFilter(alpha: alpha(cutoff: config.dCutoff))
            lastTimestamp = timestamp
            return value
        }
        
        // Calculate time delta
        let dt = timestamp - (lastTimestamp ?? timestamp)
        lastTimestamp = timestamp
        
        guard dt > 0 else { return value }
        
        // Calculate derivative (velocity)
        let dx = (value - (xFilter?.lastValue ?? value)) / dt
        let edx = dxFilter!.filter(value: dx, alpha: alpha(cutoff: config.dCutoff))
        
        // Calculate adaptive cutoff frequency
        let cutoff = config.minCutoff + config.beta * abs(edx)
        
        // Apply filter
        return xFilter!.filter(value: value, alpha: alpha(cutoff: cutoff, dt: dt))
    }
    
    func reset() {
        xFilter = nil
        dxFilter = nil
        lastTimestamp = nil
    }
    
    // MARK: - Private Methods
    
    private func alpha(cutoff: Double, dt: Double = 1.0 / 60.0) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

// MARK: - Low Pass Filter

private class LowPassFilter {
    var lastValue: Double?
    
    init(alpha: Double) {
        // Alpha not stored as it's recalculated each frame
    }
    
    func filter(value: Double, alpha: Double) -> Double {
        if lastValue == nil {
            lastValue = value
            return value
        }
        
        let filtered = alpha * value + (1.0 - alpha) * lastValue!
        lastValue = filtered
        return filtered
    }
}
