//
//  DecibelCalculator.swift
//  FootstepNoiseAnalyzer
//
//  Utility for converting audio amplitude values to decibel scale.
//  Requirements: 8.4
//

import Foundation
import AVFoundation

/// Utility class for decibel calculations from audio data.
final class DecibelCalculator {
    
    // MARK: - Constants
    
    /// Base offset to convert dBFS to approximate dB SPL
    /// iOS microphones typically have sensitivity around -38 to -42 dBFS/Pa
    /// This base offset of 75 dB is calibrated so that:
    /// - Quiet room (~-45 dBFS) shows ~30 dB SPL
    /// - Normal conversation (~-25 dBFS) shows ~50 dB SPL
    /// - Loud sounds (~-10 dBFS) shows ~65 dB SPL
    /// Users can adjust via calibrationOffset in SensitivitySettings
    static let baseDbFSToSPLOffset: Float = 75.0
    
    /// Dynamic offset that includes user calibration
    static var dbFSToSPLOffset: Float {
        return baseDbFSToSPLOffset + SensitivitySettings.shared.calibrationOffset
    }
    
    /// Minimum dB SPL value (practical silence floor)
    static let minimumDecibelsSPL: Float = 0.0
    
    /// Maximum dB SPL value (pain threshold)
    static let maximumDecibelsSPL: Float = 130.0
    
    /// Minimum decibel value for normalized audio (silence floor) - dBFS
    static let minimumDecibels: Float = -160.0
    
    /// Maximum decibel value for normalized audio (full scale) - dBFS
    static let maximumDecibels: Float = 0.0
    
    /// Minimum amplitude value to avoid log(0)
    private static let minimumAmplitude: Float = 1e-8
    
    // MARK: - Public Methods
    
    /// Convert RMS amplitude to decibel scale.
    /// - Parameter rms: RMS amplitude value (typically 0.0 to 1.0 for normalized audio)
    /// - Returns: Decibel value, clamped to valid range [minimumDecibels, maximumDecibels]
    static func rmsToDecibels(_ rms: Float) -> Float {
        // Handle edge cases
        guard rms.isFinite else {
            return minimumDecibels
        }
        
        // Clamp to minimum amplitude to avoid log(0) or log(negative)
        let clampedRMS = max(abs(rms), minimumAmplitude)
        
        // Convert to decibels: dB = 20 * log10(amplitude)
        let decibels = 20.0 * log10(clampedRMS)
        
        // Ensure result is finite and within valid range
        guard decibels.isFinite else {
            return minimumDecibels
        }
        
        return max(minimumDecibels, min(maximumDecibels, decibels))
    }
    
    /// Convert decibel value back to linear amplitude.
    /// - Parameter decibels: Decibel value
    /// - Returns: Linear amplitude value
    static func decibelsToAmplitude(_ decibels: Float) -> Float {
        // Handle edge cases
        guard decibels.isFinite else {
            return 0
        }
        
        // Clamp decibels to valid range
        let clampedDb = max(minimumDecibels, min(maximumDecibels, decibels))
        
        // Convert from decibels: amplitude = 10^(dB/20)
        return pow(10.0, clampedDb / 20.0)
    }
    
    /// Calculate decibel level from an audio buffer.
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: Decibel level of the buffer, or minimumDecibels if buffer is invalid
    static func calculateDecibels(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return minimumDecibels
        }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return minimumDecibels
        }
        
        // Calculate RMS
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        
        return rmsToDecibels(rms)
    }
    
    /// Calculate peak decibel level from an audio buffer.
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: Peak decibel level of the buffer
    static func calculatePeakDecibels(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return minimumDecibels
        }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return minimumDecibels
        }
        
        // Find peak amplitude
        var peak: Float = 0
        for i in 0..<frameCount {
            peak = max(peak, abs(channelData[i]))
        }
        
        return rmsToDecibels(peak)
    }
    
    /// Normalize a decibel value to a 0.0-1.0 range for UI display.
    /// - Parameter decibels: Decibel value
    /// - Returns: Normalized value between 0.0 and 1.0
    static func normalizeDecibels(_ decibels: Float) -> Float {
        guard decibels.isFinite else {
            return 0
        }
        
        let range = maximumDecibels - minimumDecibels
        let normalized = (decibels - minimumDecibels) / range
        
        return max(0, min(1, normalized))
    }
    
    /// Convert dBFS (digital full scale) to approximate dB SPL (sound pressure level).
    /// Note: This is an approximation without microphone calibration.
    /// - Parameter dbFS: Decibel value in dBFS (typically -160 to 0)
    /// - Returns: Approximate dB SPL value (typically 0 to 130)
    static func dbFSToSPL(_ dbFS: Float) -> Float {
        let spl = dbFS + dbFSToSPLOffset
        return max(minimumDecibelsSPL, min(maximumDecibelsSPL, spl))
    }
    
    /// Convert dB SPL to dBFS.
    /// - Parameter dbSPL: Decibel value in dB SPL
    /// - Returns: dBFS value
    static func splToDbFS(_ dbSPL: Float) -> Float {
        return dbSPL - dbFSToSPLOffset
    }
    
    /// Calculate approximate dB SPL from an audio buffer.
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: Approximate dB SPL level
    static func calculateDecibelsSPL(from buffer: AVAudioPCMBuffer) -> Float {
        let dbFS = calculateDecibels(from: buffer)
        return dbFSToSPL(dbFS)
    }
    
    /// Normalize a dB SPL value to a 0.0-1.0 range for UI display.
    /// Uses a range of 30-100 dB SPL for typical indoor sounds.
    /// - Parameter dbSPL: Decibel SPL value
    /// - Returns: Normalized value between 0.0 and 1.0
    static func normalizeDecibelsSPL(_ dbSPL: Float) -> Float {
        let minDisplay: Float = 30.0  // Quiet room
        let maxDisplay: Float = 100.0 // Very loud
        
        let normalized = (dbSPL - minDisplay) / (maxDisplay - minDisplay)
        return max(0, min(1, normalized))
    }
}
