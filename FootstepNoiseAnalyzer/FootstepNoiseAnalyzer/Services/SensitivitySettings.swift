//
//  SensitivitySettings.swift
//  FootstepNoiseAnalyzer
//
//  Manages user-adjustable microphone sensitivity settings with persistence.
//

import Foundation
import Combine

/// Manages sensitivity settings for footstep detection.
/// Higher sensitivity = lower thresholds = detects quieter sounds.
final class SensitivitySettings: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SensitivitySettings()
    
    // MARK: - Published Properties
    
    /// Sensitivity level from 0.0 (least sensitive) to 1.0 (most sensitive)
    /// Default is 0.5 (medium sensitivity)
    @Published var sensitivity: Float {
        didSet {
            UserDefaults.standard.set(sensitivity, forKey: sensitivityKey)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Detection threshold for NoiseAnalyzer (RMS amplitude)
    /// Lower value = more sensitive
    var detectionThreshold: Float {
        // Map sensitivity 0-1 to threshold 0.5-0.1 (inverted)
        let minThreshold: Float = 0.1
        let maxThreshold: Float = 0.5
        return maxThreshold - (sensitivity * (maxThreshold - minThreshold))
    }
    
    /// Minimum decibel level for NoiseClassifier
    /// Lower value = more sensitive
    var minimumDecibelLevel: Float {
        // Map sensitivity 0-1 to dB 55-35 (inverted)
        let minDb: Float = 35.0
        let maxDb: Float = 55.0
        return maxDb - (sensitivity * (maxDb - minDb))
    }
    
    /// Human-readable sensitivity label
    var sensitivityLabel: String {
        switch sensitivity {
        case 0..<0.25:
            return "Low"
        case 0.25..<0.5:
            return "Medium-Low"
        case 0.5..<0.75:
            return "Medium-High"
        default:
            return "High"
        }
    }
    
    // MARK: - Private Properties
    
    private let sensitivityKey = "footstep_detection_sensitivity"
    
    // MARK: - Initialization
    
    private init() {
        // Load saved sensitivity or use default
        if UserDefaults.standard.object(forKey: sensitivityKey) != nil {
            self.sensitivity = UserDefaults.standard.float(forKey: sensitivityKey)
        } else {
            self.sensitivity = 0.5 // Default medium sensitivity
        }
    }
    
    // MARK: - Methods
    
    /// Reset sensitivity to default value
    func resetToDefault() {
        sensitivity = 0.5
    }
}
