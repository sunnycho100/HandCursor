//
//  HandTrackingService.swift
//  HandCursor
//
//  Detects hand landmarks using Apple Vision framework
//

import Vision
import CoreVideo
import CoreGraphics

// MARK: - Protocol

protocol HandTrackingServiceProtocol: AnyObject {
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) async -> HandFrame?
}

// MARK: - Hand Tracking Service Implementation

final class HandTrackingService: HandTrackingServiceProtocol {
    
    // MARK: - Properties
    
    private let handPoseRequest: VNDetectHumanHandPoseRequest
    private let confidenceThreshold: Float
    
    // MARK: - Initialization
    
    init(confidenceThreshold: Float = 0.5) {
        self.confidenceThreshold = confidenceThreshold
        self.handPoseRequest = VNDetectHumanHandPoseRequest()
        self.handPoseRequest.maximumHandCount = 1
    }
    
    // MARK: - Public Methods
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) async -> HandFrame? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try handler.perform([handPoseRequest])
            
            guard let observation = handPoseRequest.results?.first,
                  observation.confidence >= confidenceThreshold else {
                return nil
            }
            
            let landmarks = extractLandmarks(from: observation)
            
            return HandFrame(
                timestamp: timestamp,
                landmarks: landmarks,
                confidence: observation.confidence
            )
            
        } catch {
            print("Hand tracking error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func extractLandmarks(from observation: VNHumanHandPoseObservation) -> [HandLandmark] {
        var landmarks: [HandLandmark] = []
        
        // Define key joints to track
        let joints: [(VNHumanHandPoseObservation.JointName, String)] = [
            (.thumbTip, "thumbTip"),
            (.thumbIP, "thumbIP"),
            (.thumbMP, "thumbMP"),
            (.thumbCMC, "thumbCMC"),
            
            (.indexTip, "indexTip"),
            (.indexDIP, "indexDIP"),
            (.indexPIP, "indexPIP"),
            (.indexMCP, "indexMCP"),
            
            (.middleTip, "middleTip"),
            (.middleDIP, "middleDIP"),
            (.middlePIP, "middlePIP"),
            (.middleMCP, "middleMCP"),
            
            (.ringTip, "ringTip"),
            (.ringDIP, "ringDIP"),
            (.ringPIP, "ringPIP"),
            (.ringMCP, "ringMCP"),
            
            (.littleTip, "littleTip"),
            (.littleDIP, "littleDIP"),
            (.littlePIP, "littlePIP"),
            (.littleMCP, "littleMCP"),
            
            (.wrist, "wrist")
        ]
        
        for (joint, id) in joints {
            if let point = try? observation.recognizedPoint(joint),
               point.confidence >= confidenceThreshold {
                // Vision coordinates: (0,0) is bottom-left, (1,1) is top-right
                landmarks.append(HandLandmark(
                    id: id,
                    x: point.location.x,
                    y: point.location.y,
                    confidence: point.confidence
                ))
            }
        }
        
        return landmarks
    }
}

// MARK: - Landmark Names Extension

extension VNHumanHandPoseObservation.JointName {
    var displayName: String {
        switch self {
        case .thumbTip: return "Thumb Tip"
        case .thumbIP: return "Thumb IP"
        case .thumbMP: return "Thumb MP"
        case .thumbCMC: return "Thumb CMC"
        case .indexTip: return "Index Tip"
        case .indexDIP: return "Index DIP"
        case .indexPIP: return "Index PIP"
        case .indexMCP: return "Index MCP"
        case .middleTip: return "Middle Tip"
        case .middleDIP: return "Middle DIP"
        case .middlePIP: return "Middle PIP"
        case .middleMCP: return "Middle MCP"
        case .ringTip: return "Ring Tip"
        case .ringDIP: return "Ring DIP"
        case .ringPIP: return "Ring PIP"
        case .ringMCP: return "Ring MCP"
        case .littleTip: return "Little Tip"
        case .littleDIP: return "Little DIP"
        case .littlePIP: return "Little PIP"
        case .littleMCP: return "Little MCP"
        case .wrist: return "Wrist"
        default: return "Unknown"
        }
    }
}
