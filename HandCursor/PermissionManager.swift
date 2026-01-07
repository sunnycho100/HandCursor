//
//  PermissionManager.swift
//  HandCursor
//
//  Handles camera and accessibility permissions for macOS
//

import Foundation
import AVFoundation
import AppKit
import ApplicationServices

// MARK: - Permission Status

enum PermissionStatus {
    case authorized
    case denied
    case notDetermined
    case restricted
    
    var description: String {
        switch self {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        }
    }
    
    var isGranted: Bool {
        return self == .authorized
    }
}

// MARK: - Permission Manager

final class PermissionManager {
    
    // MARK: - Singleton
    
    static let shared = PermissionManager()
    
    private init() {}
    
    // MARK: - Camera Permission
    
    /// Check camera authorization status
    func checkCameraPermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }
    
    /// Request camera permission (asynchronous)
    func requestCameraPermission() async -> Bool {
        let status = checkCameraPermission()
        
        switch status {
        case .authorized:
            return true
            
        case .notDetermined:
            // Request permission
            return await AVCaptureDevice.requestAccess(for: .video)
            
        case .denied, .restricted:
            // Already denied or restricted - need to open System Settings
            return false
        }
    }
    
    /// Open System Settings to camera privacy settings
    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Accessibility Permission
    
    /// Check if the app has accessibility permissions (required for CGEvent posting)
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request accessibility permission by showing system prompt
    /// Note: macOS doesn't have a direct API to request this - shows system dialog
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("⚠️ Accessibility permissions required for cursor control")
            print("Please enable in System Settings > Privacy & Security > Accessibility")
        }
    }
    
    /// Open System Settings to accessibility privacy settings
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Combined Status
    
    /// Check all required permissions
    func checkAllPermissions() -> (camera: PermissionStatus, accessibility: Bool) {
        let cameraStatus = checkCameraPermission()
        let accessibilityGranted = checkAccessibilityPermission()
        
        return (camera: cameraStatus, accessibility: accessibilityGranted)
    }
    
    /// Returns true if all permissions are granted
    func areAllPermissionsGranted() -> Bool {
        let (camera, accessibility) = checkAllPermissions()
        return camera.isGranted && accessibility
    }
    
    // MARK: - User-Friendly Messages
    
    func getCameraPermissionMessage() -> String? {
        let status = checkCameraPermission()
        
        switch status {
        case .authorized:
            return nil
            
        case .notDetermined:
            return "Camera access is required for hand tracking. Please grant permission when prompted."
            
        case .denied:
            return "Camera access was denied. Please enable it in System Settings > Privacy & Security > Camera."
            
        case .restricted:
            return "Camera access is restricted by system policy."
        }
    }
    
    func getAccessibilityPermissionMessage() -> String? {
        if checkAccessibilityPermission() {
            return nil
        }
        
        return "Accessibility access is required to control the cursor. Please enable it in System Settings > Privacy & Security > Accessibility."
    }
    
    func getPermissionsSummary() -> String? {
        var messages: [String] = []
        
        if let cameraMsg = getCameraPermissionMessage() {
            messages.append("🎥 " + cameraMsg)
        }
        
        if let accessibilityMsg = getAccessibilityPermissionMessage() {
            messages.append("♿️ " + accessibilityMsg)
        }
        
        return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }
}
