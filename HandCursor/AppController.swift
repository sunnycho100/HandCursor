//
//  AppController.swift
//  HandCursor
//
//  Orchestrates the complete pipeline: Camera -> Hand Tracking -> Stabilization -> Gesture -> Pointer
//  Manages threading, FPS logging, and frame dropping for low latency
//

import Foundation
import CoreVideo
import AVFoundation

// MARK: - Protocol

@MainActor
protocol AppControllerDelegate: AnyObject {
    func appController(_ controller: AppController, didUpdateState state: AppControllerState)
    func appController(_ controller: AppController, didUpdateFPS fps: Double, latency: Double)
    func appController(_ controller: AppController, didDetectHand: Bool)
    func appController(_ controller: AppController, didChangeGestureState state: GestureState)
}

// MARK: - State

enum AppControllerState {
    case stopped
    case starting
    case running
    case stopping
    case error(String)
    
    var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .stopping: return "Stopping..."
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - App Controller

@MainActor
final class AppController: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: AppControllerDelegate?
    
    private(set) var state: AppControllerState = .stopped {
        didSet {
            delegate?.appController(self, didUpdateState: state)
        }
    }
    
    var isEnabled: Bool = true {
        didSet {
            pointerController.isEnabled = isEnabled
        }
    }
    
    // Services
    private let cameraService: CameraServiceProtocol
    private let handTrackingService: HandTrackingServiceProtocol
    private let stabilizationLayer: StabilizationLayerProtocol
    private let gestureEngine: GestureEngineProtocol
    private let pointerController: PointerControllerProtocol
    
    // Threading: Vision processing queue
    private let visionQueue = DispatchQueue(label: "com.handcursor.vision", qos: .userInteractive)
    private var isProcessingFrame = false // Guards against frame stacking
    
    // Performance tracking
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsUpdateTime: CFTimeInterval = 0
    private var totalLatency: Double = 0
    
    // MARK: - Initialization
    
    init(
        cameraService: CameraServiceProtocol? = nil,
        handTrackingService: HandTrackingServiceProtocol? = nil,
        stabilizationLayer: StabilizationLayerProtocol? = nil,
        gestureEngine: GestureEngineProtocol? = nil,
        pointerController: PointerControllerProtocol? = nil
    ) {
        self.cameraService = cameraService ?? CameraService()
        self.handTrackingService = handTrackingService ?? HandTrackingService()
        self.stabilizationLayer = stabilizationLayer ?? StabilizationLayer()
        self.gestureEngine = gestureEngine ?? GestureEngine()
        self.pointerController = pointerController ?? PointerController()
        
        super.init()
        
        setupPipeline()
    }
    
    // MARK: - Setup
    
    private func setupPipeline() {
        // Wire gesture engine -> pointer controller
        gestureEngine.delegate = self
        
        // Wire camera -> Vision processing
        cameraService.frameHandler = { [weak self] pixelBuffer, timestamp in
            self?.handleCameraFrame(pixelBuffer, captureTimestamp: timestamp)
        }
    }
    
    // MARK: - Public Methods
    
    func start() async {
        guard state == .stopped else {
            print("⚠️ Cannot start: already in state \(state)")
            return
        }
        
        state = .starting
        
        do {
            try await cameraService.start()
            state = .running
            print("✅ AppController started")
            
            // Reset metrics
            frameCount = 0
            fpsUpdateTime = CACurrentMediaTime()
            totalLatency = 0
            
        } catch {
            let errorMessage = error.localizedDescription
            state = .error(errorMessage)
            print("❌ Failed to start: \(errorMessage)")
        }
    }
    
    func stop() {
        guard state == .running || state == .starting else {
            print("⚠️ Cannot stop: not running")
            return
        }
        
        state = .stopping
        
        cameraService.stop()
        stabilizationLayer.reset()
        gestureEngine.reset()
        
        state = .stopped
        print("⏹️ AppController stopped")
    }
    
    // MARK: - Pipeline Processing
    
    /// Called on camera capture queue (high priority)
    private nonisolated func handleCameraFrame(_ pixelBuffer: CVPixelBuffer, captureTimestamp: CFTimeInterval) {
        // Frame dropping: if Vision is still processing, skip this frame to maintain low latency
        guard !isProcessingFrame else {
            // Frame dropped - this is intentional for low latency
            return
        }
        
        isProcessingFrame = true
        
        // Enqueue Vision processing on dedicated queue
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let processingStartTime = CACurrentMediaTime()
            
            // Step 1: Hand detection (Vision framework - synchronous, CPU/GPU intensive)
            let handFrame = self.handTrackingService.processFrame(pixelBuffer, timestamp: captureTimestamp)
            
            let processingEndTime = CACurrentMediaTime()
            let latency = processingEndTime - captureTimestamp
            
            // Step 2: Continue pipeline on main thread
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                self.continueProcessing(handFrame: handFrame, timestamp: captureTimestamp, latency: latency)
                self.isProcessingFrame = false
            }
        }
    }
    
    /// Continues processing on main thread: stabilization -> gesture -> pointer
    private func continueProcessing(handFrame: HandFrame?, timestamp: CFTimeInterval, latency: Double) {
        // Update FPS metrics
        updateMetrics(timestamp: timestamp, latency: latency)
        
        // Handle no hand detected
        guard let handFrame = handFrame else {
            delegate?.appController(self, didDetectHand: false)
            
            // Feed empty frame to gesture engine to transition to idle state
            let emptyFrame = HandFrame(timestamp: timestamp, landmarks: [], confidence: 0)
            let emptyPoint = SmoothedPoint(point: .zero, timestamp: timestamp, rawPoint: .zero)
            gestureEngine.processFrame(emptyFrame, smoothedPoint: emptyPoint)
            return
        }
        
        delegate?.appController(self, didDetectHand: true)
        
        // Step 3: Stabilization (smooth the index finger position)
        guard let indexTip = handFrame.indexTip else { return }
        let smoothedPoint = stabilizationLayer.smooth(point: indexTip.point, timestamp: timestamp)
        
        // Step 4: Gesture recognition
        gestureEngine.processFrame(handFrame, smoothedPoint: smoothedPoint)
        
        // Pointer events are sent via GestureEngineDelegate
    }
    
    // MARK: - Performance Metrics
    
    private func updateMetrics(timestamp: CFTimeInterval, latency: Double) {
        frameCount += 1
        totalLatency += latency
        
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - fpsUpdateTime
        
        // Update FPS every second
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            let avgLatency = totalLatency / Double(frameCount)
            
            delegate?.appController(self, didUpdateFPS: fps, latency: avgLatency * 1000) // Convert to ms
            
            // Reset counters
            frameCount = 0
            fpsUpdateTime = currentTime
            totalLatency = 0
        }
    }
}

// MARK: - Gesture Engine Delegate

extension AppController: GestureEngineDelegate {
    
    nonisolated func gestureEngine(_ engine: GestureEngineProtocol, didEmit event: GestureEvent) {
        Task { @MainActor in
            guard isEnabled else { return }
            pointerController.handleEvent(event)
        }
    }
    
    nonisolated func gestureEngine(_ engine: GestureEngineProtocol, didChangeState newState: GestureState) {
        Task { @MainActor in
            delegate?.appController(self, didChangeGestureState: newState)
        }
    }
}
