//
//  ContentView.swift
//  HandCursor
//
//  Main view that orchestrates the hand tracking cursor pipeline
//

import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    
    @StateObject private var coordinator = HandCursorCoordinator()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text("HandCursor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.top, 40)
            
            // Status
            VStack(spacing: 12) {
                StatusRow(label: "Camera", value: coordinator.isCameraRunning ? "Active" : "Inactive", 
                         color: coordinator.isCameraRunning ? .green : .gray)
                StatusRow(label: "Hand Detected", value: coordinator.isHandDetected ? "Yes" : "No",
                         color: coordinator.isHandDetected ? .green : .orange)
                StatusRow(label: "Gesture State", value: coordinator.gestureState.description,
                         color: .blue)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // Controls
            VStack(spacing: 16) {
                Toggle("Enable Cursor Control", isOn: $coordinator.isEnabled)
                    .toggleStyle(.switch)
                    .padding(.horizontal)
                
                Button(action: {
                    coordinator.toggleTracking()
                }) {
                    HStack {
                        Image(systemName: coordinator.isCameraRunning ? "stop.circle.fill" : "play.circle.fill")
                        Text(coordinator.isCameraRunning ? "Stop Tracking" : "Start Tracking")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(coordinator.isCameraRunning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                if let error = coordinator.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(width: 400, height: 500)
        .padding()
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
    }
}

// MARK: - Coordinator

@MainActor
class HandCursorCoordinator: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isCameraRunning = false
    @Published var isHandDetected = false
    @Published var gestureState: GestureState = .idle
    @Published var isEnabled = true
    @Published var errorMessage: String?
    
    // MARK: - Services
    
    private let cameraService: CameraService
    private let handTrackingService: HandTrackingService
    private let stabilizationLayer: StabilizationLayer
    private let gestureEngine: GestureEngine
    private let pointerController: PointerController
    
    // MARK: - Initialization
    
    override init() {
        self.cameraService = CameraService()
        self.handTrackingService = HandTrackingService()
        self.stabilizationLayer = StabilizationLayer()
        self.gestureEngine = GestureEngine()
        self.pointerController = PointerController()
        
        super.init()
        setupDelegates()
    }
    
    // MARK: - Setup
    
    private func setupDelegates() {
        cameraService.delegate = self
        gestureEngine.delegate = self
    }
    
    // MARK: - Public Methods
    
    func toggleTracking() {
        if isCameraRunning {
            stopTracking()
        } else {
            startTracking()
        }
    }
    
    func startTracking() {
        Task {
            do {
                try await cameraService.start()
                isCameraRunning = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                print("Failed to start camera: \(error)")
            }
        }
    }
    
    func stopTracking() {
        cameraService.stop()
        isCameraRunning = false
        isHandDetected = false
        gestureState = .idle
        stabilizationLayer.reset()
        gestureEngine.reset()
    }
    
    // MARK: - Pipeline Processing
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) {
        Task {
            // Step 1: Detect hand landmarks
            guard let handFrame = await handTrackingService.processFrame(pixelBuffer, timestamp: timestamp) else {
                isHandDetected = false
                gestureEngine.processFrame(
                    HandFrame(timestamp: timestamp, landmarks: [], confidence: 0),
                    smoothedPoint: SmoothedPoint(point: .zero, timestamp: timestamp, rawPoint: .zero)
                )
                return
            }
            
            isHandDetected = true
            
            // Step 2: Get pointer position (use index tip)
            guard let indexTip = handFrame.indexTip else {
                return
            }
            
            // Step 3: Smooth the position
            let smoothedPoint = stabilizationLayer.smooth(point: indexTip.point, timestamp: timestamp)
            
            // Step 4: Process gesture
            gestureEngine.processFrame(handFrame, smoothedPoint: smoothedPoint)
        }
    }
}

// MARK: - Camera Service Delegate

extension HandCursorCoordinator: CameraServiceDelegate {
    
    nonisolated func cameraService(_ service: CameraServiceProtocol, didCapture pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) {
        Task { @MainActor in
            processFrame(pixelBuffer, timestamp: timestamp)
        }
    }
    
    nonisolated func cameraService(_ service: CameraServiceProtocol, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Gesture Engine Delegate

extension HandCursorCoordinator: GestureEngineDelegate {
    
    func gestureEngine(_ engine: GestureEngineProtocol, didEmit event: GestureEvent) {
        guard isEnabled else { return }
        pointerController.handleEvent(event)
    }
    
    func gestureEngine(_ engine: GestureEngineProtocol, didChangeState newState: GestureState) {
        gestureState = newState
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
