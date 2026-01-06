//
//  CameraService.swift
//  HandCursor
//
//  Captures video frames from the Mac camera using AVFoundation
//

import AVFoundation
import CoreVideo

// MARK: - Protocol

protocol CameraServiceProtocol: AnyObject {
    var delegate: CameraServiceDelegate? { get set }
    var frameHandler: ((CVPixelBuffer, CFTimeInterval) -> Void)? { get set }
    func start() async throws
    func stop()
    var isRunning: Bool { get }
}

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraServiceProtocol, didCapture pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval)
    func cameraService(_ service: CameraServiceProtocol, didFailWithError error: Error)
}

// MARK: - Camera Service Implementation

@MainActor
final class CameraService: NSObject, CameraServiceProtocol {
    
    weak var delegate: CameraServiceDelegate?
    
    /// Synchronous frame handler called on the capture queue - use this for processing
    nonisolated(unsafe) var frameHandler: ((CVPixelBuffer, CFTimeInterval) -> Void)?
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.handcursor.camera", qos: .userInteractive)
    
    private(set) var isRunning = false
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Setup
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        
        // Configure session preset
        if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        }
        
        captureSession.commitConfiguration()
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
        
        // Start capture session
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
        
        isRunning = true
    }
    
    func stop() {
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
        // Find camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CameraError.deviceNotFound
        }
        
        // Create input
        let input = try AVCaptureDeviceInput(device: camera)
        
        guard captureSession.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        
        captureSession.addInput(input)
        
        // Configure video output
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.cannotAddOutput
        }
        
        captureSession.addOutput(videoOutput)
        
        // Configure connection
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
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
        // Handle dropped frames if needed
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
