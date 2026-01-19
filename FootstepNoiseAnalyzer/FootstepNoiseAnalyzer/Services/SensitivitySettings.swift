//
//  SensitivitySettings.swift
//  FootstepNoiseAnalyzer
//
//  Manages user-adjustable microphone sensitivity and calibration settings with persistence.
//

import Foundation
import Combine

/// Manages sensitivity settings for footstep detection.
/// 
/// - Sensitivity: dB offset that shifts all stomping classification thresholds relative to ambient.
///   Positive values = need louder sounds (less sensitive), Negative = quieter sounds detected (more sensitive)
/// - Calibration: Adjusts dBFS to dB SPL conversion for microphone differences.
///
/// Classification is relative to ambient noise level:
/// - Mild: ambient + 5 + sensitivity to ambient + 10 + sensitivity
/// - Medium: ambient + 10 + sensitivity to ambient + 15 + sensitivity
/// - Hard: ambient + 15 + sensitivity to ambient + 20 + sensitivity
/// - Extreme: ambient + 20 + sensitivity and above
final class SensitivitySettings: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SensitivitySettings()
    
    // MARK: - Published Properties
    
    /// Sensitivity offset in dB (-10 to +10)
    /// Shifts all stomping classification thresholds relative to ambient.
    /// Positive = less sensitive (need louder sounds), Negative = more sensitive (quieter sounds detected)
    /// Default is 0
    @Published var sensitivityOffset: Float {
        didSet {
            let clamped = max(-10, min(10, sensitivityOffset))
            if clamped != sensitivityOffset {
                sensitivityOffset = clamped
            }
            UserDefaults.standard.set(sensitivityOffset, forKey: sensitivityKey)
        }
    }
    
    /// Microphone calibration offset in dB (-20 to +20)
    /// Adjusts the dBFS to dB SPL conversion for microphone hardware differences.
    /// Increase if readings seem too low, decrease if too high.
    /// Default is 0 (no adjustment from base offset)
    @Published var calibrationOffset: Float {
        didSet {
            let clamped = max(-20, min(20, calibrationOffset))
            if clamped != calibrationOffset {
                calibrationOffset = clamped
            }
            UserDefaults.standard.set(calibrationOffset, forKey: calibrationKey)
        }
    }
    
    // MARK: - Classification Offsets (relative to ambient)
    
    /// Offset from ambient for mild stomping threshold
    static let mildOffset: Float = 5.0
    
    /// Offset from ambient for medium stomping threshold
    static let mediumOffset: Float = 10.0
    
    /// Offset from ambient for hard stomping threshold
    static let hardOffset: Float = 15.0
    
    /// Offset from ambient for extreme stomping threshold
    static let extremeOffset: Float = 20.0
    
    // MARK: - Computed Properties
    
    /// Total dBFS to dB SPL offset including user calibration
    /// Base offset of 75 dB + user calibration adjustment
    var effectiveDbOffset: Float {
        return DecibelCalculator.baseDbFSToSPLOffset + calibrationOffset
    }
    
    /// Human-readable sensitivity label
    var sensitivityLabel: String {
        if sensitivityOffset > 0 {
            return "Less Sensitive (+\(Int(sensitivityOffset)) dB)"
        } else if sensitivityOffset < 0 {
            return "More Sensitive (\(Int(sensitivityOffset)) dB)"
        } else {
            return "Normal (0 dB)"
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
    
    private let sensitivityKey = "footstep_sensitivity_offset"
    private let calibrationKey = "microphone_calibration_offset"
    
    // MARK: - Initialization
    
    private init() {
        // Load saved sensitivity or use default
        if UserDefaults.standard.object(forKey: sensitivityKey) != nil {
            self.sensitivityOffset = UserDefaults.standard.float(forKey: sensitivityKey)
        } else {
            self.sensitivityOffset = 0.0 // Default no offset
        }
        
        // Load saved calibration or use default
        if UserDefaults.standard.object(forKey: calibrationKey) != nil {
            self.calibrationOffset = UserDefaults.standard.float(forKey: calibrationKey)
        } else {
            self.calibrationOffset = 0.0 // Default no adjustment
        }
    }
    
    // MARK: - Methods
    
    /// Get classification thresholds based on ambient level and sensitivity.
    /// - Parameter ambientLevel: The current ambient noise level in dB SPL
    /// - Returns: Tuple of (mild, medium, hard, extreme) thresholds
    func getThresholds(ambientLevel: Float) -> (mild: Float, medium: Float, hard: Float, extreme: Float) {
        let base = ambientLevel + sensitivityOffset
        return (
            mild: base + SensitivitySettings.mildOffset,
            medium: base + SensitivitySettings.mediumOffset,
            hard: base + SensitivitySettings.hardOffset,
            extreme: base + SensitivitySettings.extremeOffset
        )
    }
    
    /// Reset sensitivity to default value
    func resetToDefault() {
        sensitivityOffset = 0.0
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
