//
//  NoiseClassifier.swift
//  FootstepNoiseAnalyzer
//
//  Classifies detected sounds into footstep categories based on
//  frequency and decibel levels.
//

import Foundation
import AVFoundation

/// Protocol defining the interface for noise classification operations.
protocol NoiseClassifierProtocol: AnyObject {
    /// Classify an audio buffer and return the footstep classification.
    /// - Parameters:
    ///   - audioBuffer: The audio buffer to classify
    ///   - previousConfirmedEventTime: Timestamp of the last confirmed event (for running detection)
    ///   - recentLoudEventTime: Timestamp of the most recent loud event (for echo detection)
    ///   - recentLoudEventDb: Decibel level of the most recent loud event (for echo detection)
    ///   - currentTime: Current event timestamp
    /// - Returns: The classification result
    func classify(
        audioBuffer: AVAudioPCMBuffer,
        previousConfirmedEventTime: TimeInterval?,
        recentLoudEventTime: TimeInterval?,
        recentLoudEventDb: Float?,
        currentTime: TimeInterval
    ) -> FootstepClassification?
}

/// Errors that can occur during noise classification.
enum ClassificationError: Error, LocalizedError {
    case invalidAudioFormat
    case insufficientAudioData
    case frequencyAnalysisFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAudioFormat:
            return "The audio format is not supported for classification."
        case .insufficientAudioData:
            return "Not enough audio data for classification."
        case .frequencyAnalysisFailed:
            return "Failed to analyze frequency spectrum."
        }
    }
}

/// Configuration for the noise classifier thresholds.
struct ClassifierConfig {
    /// Maximum frequency (Hz) to be considered "low frequency" footstep
    let lowFrequencyThreshold: Float
    
    /// Decibel threshold between mild and medium stomping
    let mildToMediumDb: Float
    
    /// Decibel threshold between medium and hard stomping
    let mediumToHardDb: Float
    
    /// Maximum interval (seconds) between steps to classify as running
    let runningIntervalThreshold: TimeInterval
    
    /// Minimum decibel level to consider as a valid footstep
    let minimumDecibelLevel: Float
    
    /// Time window (seconds) to consider for echo detection
    let echoWindowSeconds: TimeInterval
    
    /// Minimum dB drop from previous event to consider current event as echo
    let echoDbDropThreshold: Float
    
    static let `default` = ClassifierConfig(
        lowFrequencyThreshold: 500,      // Hz - footsteps typically below 500 Hz
        mildToMediumDb: 56,              // dB SPL - normal walking
        mediumToHardDb: 62,              // dB SPL - heavy walking
        runningIntervalThreshold: 0.15,  // seconds - very short interval for running
        minimumDecibelLevel: 45,         // dB SPL - ignore ambient noise
        echoWindowSeconds: 1.0,          // seconds - window to detect echoes
        echoDbDropThreshold: 14.0        // dB - drop threshold to identify echo
    )
}

/// Implementation of NoiseClassifierProtocol using frequency and decibel analysis.
final class NoiseClassifier: NoiseClassifierProtocol {
    
    // MARK: - Private Properties
    
    private let frequencyAnalyzer: FrequencyAnalyzer
    private let config: ClassifierConfig
    private let sampleRate: Float
    
    // MARK: - Initialization
    
    init(config: ClassifierConfig = .default, sampleRate: Float = 44100) {
        self.config = config
        self.sampleRate = sampleRate
        self.frequencyAnalyzer = FrequencyAnalyzer(fftSize: 2048, sampleRate: sampleRate)
    }
    
    // MARK: - Public Methods
    
    func classify(
        audioBuffer: AVAudioPCMBuffer,
        previousConfirmedEventTime: TimeInterval?,
        recentLoudEventTime: TimeInterval?,
        recentLoudEventDb: Float?,
        currentTime: TimeInterval
    ) -> FootstepClassification? {
        guard audioBuffer.frameLength > 0,
              let channelData = audioBuffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameCount = Int(audioBuffer.frameLength)
        
        // Calculate decibel level
        let decibelLevel = calculateDecibelLevel(channelData, frameCount: frameCount)
        
        // Ignore sounds below minimum threshold
        guard decibelLevel >= config.minimumDecibelLevel else {
            return nil
        }
        
        // Check if this is likely an echo of a recent loud event
        if let recentTime = recentLoudEventTime,
           let recentDb = recentLoudEventDb {
            let timeSinceRecent = currentTime - recentTime
            let dbDrop = recentDb - decibelLevel
            
            // If within echo window and significantly quieter, it's likely an echo
            if timeSinceRecent <= config.echoWindowSeconds && dbDrop >= config.echoDbDropThreshold {
                return nil
            }
        }
        
        // Perform frequency analysis
        guard let spectrum = frequencyAnalyzer.analyze(buffer: audioBuffer) else {
            return nil
        }
        
        // Calculate interval from previous CONFIRMED event (for running detection)
        let interval: TimeInterval? = previousConfirmedEventTime.map { currentTime - $0 }
        
        // Determine if this is a low-frequency sound (footstep candidate)
        let isLowFrequency = spectrum.dominantFrequency <= config.lowFrequencyThreshold
        
        // Classify the sound
        let (type, confidence) = classifySound(
            isLowFrequency: isLowFrequency,
            decibelLevel: decibelLevel,
            interval: interval
        )
        
        return FootstepClassification(
            type: type,
            confidence: confidence,
            decibelLevel: decibelLevel,
            dominantFrequency: spectrum.dominantFrequency,
            intervalFromPrevious: interval
        )
    }
    
    // MARK: - Private Methods
    
    /// Classify the sound based on frequency, decibel level, and interval.
    private func classifySound(
        isLowFrequency: Bool,
        decibelLevel: Float,
        interval: TimeInterval?
    ) -> (FootstepType, Float) {
        // If not low frequency, it's not a footstep
        guard isLowFrequency else {
            return (.unknown, 0.3)
        }
        
        // Determine base stomping type from decibel level
        let baseType: FootstepType
        let baseConfidence: Float
        
        if decibelLevel < config.mildToMediumDb {
            baseType = .mildStomping
            baseConfidence = 0.7 + (decibelLevel / config.mildToMediumDb) * 0.2
        } else if decibelLevel < config.mediumToHardDb {
            baseType = .mediumStomping
            let normalized = (decibelLevel - config.mildToMediumDb) / (config.mediumToHardDb - config.mildToMediumDb)
            baseConfidence = 0.75 + normalized * 0.15
        } else {
            baseType = .hardStomping
            baseConfidence = min(0.95, 0.8 + (decibelLevel - config.mediumToHardDb) / 50 * 0.15)
        }
        
        // Check if this is running (short interval between steps)
        if let interval = interval, interval <= config.runningIntervalThreshold {
            // Running detected - short interval between footsteps
            let runningConfidence = min(0.95, baseConfidence + 0.1)
            return (.running, runningConfidence)
        }
        
        return (baseType, baseConfidence)
    }
    
    /// Calculate the decibel level (dB SPL approximation) from audio samples.
    private func calculateDecibelLevel(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        
        // Calculate RMS
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = data[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        
        // Convert to decibels (using reference of 1.0 for full scale)
        // Add offset to approximate dB SPL (without microphone calibration)
        guard rms > 0 else { return 0 }
        let dbFS = 20 * log10(rms)
        let dbSPL = dbFS + DecibelCalculator.dbFSToSPLOffset
        
        return max(0, dbSPL)
    }
}
