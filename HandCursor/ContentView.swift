//
//  ContentView.swift
//  HandCursor
//
//  Main view with start/stop controls and permission status
//

import SwiftUI

struct ContentView: View {
    
    @StateObject private var viewModel = HandCursorViewModel()
    
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
            .padding(.top, 30)
            
            // Permission warnings
            if let permissionMessage = viewModel.permissionMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(permissionMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    
                    HStack(spacing: 12) {
                        if !viewModel.cameraPermissionGranted {
                            Button("Open Camera Settings") {
                                PermissionManager.shared.openCameraSettings()
                            }
                            .font(.caption)
                        }
                        
                        if !viewModel.accessibilityPermissionGranted {
                            Button("Open Accessibility Settings") {
                                PermissionManager.shared.openAccessibilitySettings()
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Status
            VStack(spacing: 12) {
                StatusRow(label: "Status", value: viewModel.statusText, 
                         color: viewModel.isRunning ? .green : .gray)
                StatusRow(label: "Hand Detected", value: viewModel.isHandDetected ? "Yes" : "No",
                         color: viewModel.isHandDetected ? .green : .orange)
                StatusRow(label: "Gesture", value: viewModel.gestureState.description,
                         color: .blue)
                StatusRow(label: "FPS", value: String(format: "%.1f", viewModel.fps),
                         color: viewModel.fps > 20 ? .green : .orange)
                StatusRow(label: "Latency", value: String(format: "%.1f ms", viewModel.latency),
                         color: viewModel.latency < 50 ? .green : .orange)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // Controls
            VStack(spacing: 16) {
                Toggle("Enable Cursor Control", isOn: $viewModel.isEnabled)
                    .toggleStyle(.switch)
                    .padding(.horizontal)
                    .disabled(!viewModel.isRunning)
                
                Button(action: {
                    viewModel.toggleTracking()
                }) {
                    HStack {
                        Image(systemName: viewModel.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        Text(viewModel.isRunning ? "Stop Tracking" : "Start Tracking")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isRunning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStart && !viewModel.isRunning)
            }
            .padding(.bottom, 30)
        }
        .frame(width: 450, height: 600)
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

// MARK: - View Model

@MainActor
class HandCursorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRunning = false
    @Published var isHandDetected = false
    @Published var gestureState: GestureState = .idle
    @Published var fps: Double = 0
    @Published var latency: Double = 0
    @Published var isEnabled = true {
        didSet {
            appController.isEnabled = isEnabled
        }
    }
    
    @Published var cameraPermissionGranted = false
    @Published var accessibilityPermissionGranted = false
    @Published var permissionMessage: String?
    
    var statusText: String {
        appController.state.description
    }
    
    var canStart: Bool {
        cameraPermissionGranted && accessibilityPermissionGranted
    }
    
    // MARK: - Services
    
    private let appController: AppController
    private let permissionManager = PermissionManager.shared
    
    // MARK: - Initialization
    
    init() {
        self.appController = AppController()
        self.appController.delegate = self
        
        // Check initial permissions
        checkPermissions()
    }
    
    // MARK: - Public Methods
    
    func toggleTracking() {
        if isRunning {
            stopTracking()
        } else {
            startTracking()
        }
    }
    
    func startTracking() {
        // Recheck permissions before starting
        checkPermissions()
        
        guard canStart else {
            print("⚠️ Cannot start: missing permissions")
            return
        }
        
        Task {
            await appController.start()
        }
    }
    
    func stopTracking() {
        appController.stop()
    }
    
    // MARK: - Permissions
    
    private func checkPermissions() {
        let (camera, accessibility) = permissionManager.checkAllPermissions()
        
        cameraPermissionGranted = camera.isGranted
        accessibilityPermissionGranted = accessibility
        permissionMessage = permissionManager.getPermissionsSummary()
        
        if !canStart {
            print("ℹ️ Permissions status - Camera: \(camera.description), Accessibility: \(accessibility)")
        }
    }
}

// MARK: - App Controller Delegate

extension HandCursorViewModel: AppControllerDelegate {
    
    func appController(_ controller: AppController, didUpdateState state: AppControllerState) {
        switch state {
        case .running:
            isRunning = true
        case .stopped:
            isRunning = false
            isHandDetected = false
            fps = 0
            latency = 0
        case .error:
            isRunning = false
        default:
            break
        }
    }
    
    func appController(_ controller: AppController, didUpdateFPS fps: Double, latency: Double) {
        self.fps = fps
        self.latency = latency
    }
    
    func appController(_ controller: AppController, didDetectHand: Bool) {
        self.isHandDetected = didDetectHand
    }
    
    func appController(_ controller: AppController, didChangeGestureState state: GestureState) {
        self.gestureState = state
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
