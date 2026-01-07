//
//  CameraService.swift
//  HandCursor
//
//  Captures video frames from the Mac camera using AVFoundation
//  Optimized for low-latency hand tracking
//

import AVFoundation
import CoreVideo

// MARK: - Protocol

protocol CameraServiceProtocol: AnyObject {
    var frameHandler: ((CVPixelBuffer, CFTimeInterval) -> Void)? { get set }
    func start() async throws
    func stop()
    var isRunning: Bool { get }
}

// MARK: - Camera Service Implementation

@MainActor
final class CameraService: NSObject, CameraServiceProtocol {
    
    /// Synchronous frame handler called on the capture queue - use this for processing
    nonisolated(unsafe) var frameHandler: ((CVPixelBuffer, CFTimeInterval) -> Void)?
    
    private nonisolated(unsafe) let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.handcursor.camera", qos: .userInteractive)
    
    private(set) var isRunning = false
    
    /// Target frame rate for capture
    private let targetFrameRate: Double = 30.0
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
    }
    
    deinit {
        Task { @MainActor in
            stop()
        }
    }
    
    // MARK: - Public Methods
    
    func start() async throws {
        // Request camera permissions
        let authorized = await checkCameraPermissions()
        guard authorized else {
            throw CameraError.permissionDenied
        }
        
        // Setup camera device
        try await setupCamera()
        
        // Start capture session on background queue
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
        
        isRunning = true
    }
    
    func stop() {
        guard isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        isRunning = false
    }
    
    // MARK: - Private Methods
    
    private func checkCameraPermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    private func setupCamera() async throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        // Use lower resolution for faster processing
        // 640x480 is sufficient for hand tracking
        if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        }
        
        // Find camera device - prefer front camera for hand tracking
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CameraError.deviceNotFound
        }
        
        // Configure camera for low latency
        try configureCamera(camera)
        
        // Create and add input
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        captureSession.addInput(input)
        
        // Configure video output for low latency
        configureVideoOutput()
        
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.cannotAddOutput
        }
        captureSession.addOutput(videoOutput)
        
        // Configure connection - mirror for natural hand movement
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
    }
    
    private func configureCamera(_ camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        
        // Set frame rate for consistent timing
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
        camera.activeVideoMinFrameDuration = frameDuration
        camera.activeVideoMaxFrameDuration = frameDuration
        
        // Disable features that add latency
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
    }
    
    private func configureVideoOutput() {
        // Process on high-priority queue
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        // Critical: Always discard late frames to minimize latency
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Use BGRA format - optimal for Vision framework
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        
        // Process frame synchronously on the capture queue where pixelBuffer is valid
        frameHandler?(pixelBuffer, timestamp)
    }
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frames are being dropped - this is expected with alwaysDiscardsLateVideoFrames
        // when processing takes longer than frame interval
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case cannotAddInput
    case cannotAddOutput
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable camera access in System Settings."
        case .deviceNotFound:
            return "No camera device found."
        case .cannotAddInput:
            return "Cannot add camera input to capture session."
        case .cannotAddOutput:
            return "Cannot add video output to capture session."
        }
    }
}
