//
//  SensitivitySettings.swift
//  FootstepNoiseAnalyzer
//
//  Manages user-adjustable microphone sensitivity and calibration settings with persistence.
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
    
    /// Microphone calibration offset in dB (-20 to +20)
    /// Adjusts the dBFS to dB SPL conversion to match real-world readings.
    /// Increase if readings are too low, decrease if too high.
    /// Default is 0 (no adjustment from base offset)
    @Published var calibrationOffset: Float {
        didSet {
            UserDefaults.standard.set(calibrationOffset, forKey: calibrationKey)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Detection threshold for NoiseAnalyzer (RMS amplitude)
    /// Lower value = more sensitive
    /// Calibrated from real audio files: median RMS ~0.0025, 90th percentile ~0.0085
    var detectionThreshold: Float {
        // Map sensitivity 0-1 to threshold 0.012-0.003 (inverted)
        // At sensitivity 0.5, threshold is ~0.0075
        let minThreshold: Float = 0.003  // Most sensitive
        let maxThreshold: Float = 0.012  // Least sensitive
        return maxThreshold - (sensitivity * (maxThreshold - minThreshold))
    }
    
    /// Minimum decibel level for NoiseClassifier
    /// Lower value = more sensitive
    var minimumDecibelLevel: Float {
        // Map sensitivity 0-1 to dB 60-46 (inverted)
        // At default sensitivity 0.5, threshold is 53 dB
        let minDb: Float = 46.0
        let maxDb: Float = 60.0
        return maxDb - (sensitivity * (maxDb - minDb))
    }
    
    /// Total dBFS to dB SPL offset including user calibration
    /// Base offset of 75 dB + user calibration adjustment
    var effectiveDbOffset: Float {
        return DecibelCalculator.baseDbFSToSPLOffset + calibrationOffset
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
    
    /// Human-readable calibration label
    var calibrationLabel: String {
        if calibrationOffset > 0 {
            return "+\(Int(calibrationOffset)) dB"
        } else {
            return "\(Int(calibrationOffset)) dB"
        }
    }
    
    // MARK: - Private Properties
    
    private let sensitivityKey = "footstep_detection_sensitivity"
    private let calibrationKey = "microphone_calibration_offset"
    
    // MARK: - Initialization
    
    private init() {
        // Load saved sensitivity or use default
        if UserDefaults.standard.object(forKey: sensitivityKey) != nil {
            self.sensitivity = UserDefaults.standard.float(forKey: sensitivityKey)
        } else {
            self.sensitivity = 0.5 // Default medium sensitivity
        }
        
        // Load saved calibration or use default
        if UserDefaults.standard.object(forKey: calibrationKey) != nil {
            self.calibrationOffset = UserDefaults.standard.float(forKey: calibrationKey)
        } else {
            self.calibrationOffset = 0.0 // Default no adjustment
        }
    }
    
    // MARK: - Methods
    
    /// Reset sensitivity to default value
    func resetToDefault() {
        sensitivity = 0.5
    }
    
    /// Reset calibration to default value
    func resetCalibration() {
        calibrationOffset = 0.0
    }
    
    /// Reset all settings to defaults
    func resetAll() {
        resetToDefault()
        resetCalibration()
    }
}
