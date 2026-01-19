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
    /// Maximum dominant frequency (Hz) to be considered a footstep candidate
    let lowFrequencyThreshold: Float
    
    /// Minimum ratio of impact energy (20-100 Hz) to total energy for footstep detection
    /// Footsteps have strong sub-bass impact; other sounds have energy spread across bands
    let minimumImpactEnergyRatio: Float
    
    /// Minimum dB level for events at the frequency threshold boundary
    /// Events at exactly the frequency threshold need higher dB to be considered footsteps
    let boundaryFrequencyMinDb: Float
    
    /// Maximum interval (seconds) between steps to classify as running
    let runningIntervalThreshold: TimeInterval
    
    /// Time window (seconds) to consider for echo detection
    let echoWindowSeconds: TimeInterval
    
    /// Minimum dB drop from previous event to consider current event as echo
    let echoDbDropThreshold: Float
    
    static let `default` = ClassifierConfig(
        lowFrequencyThreshold: 65,       // Hz - footsteps typically have dominant freq at or below 65 Hz
        minimumImpactEnergyRatio: 0.70,  // Impact band must be at least 70% of total energy (stomping is 74-95%)
        boundaryFrequencyMinDb: 38.0,    // dB - events at 60-70 Hz need at least 38 dB
        runningIntervalThreshold: 0.15,  // seconds - very short interval for running
        echoWindowSeconds: 0.5,          // seconds - reduced echo window to capture more events
        echoDbDropThreshold: 12.0        // dB - increased drop threshold to be less aggressive
    )
}

/// Implementation of NoiseClassifierProtocol using frequency and decibel analysis.
final class NoiseClassifier: NoiseClassifierProtocol {
    
    // MARK: - Private Properties
    
    private let frequencyAnalyzer: FrequencyAnalyzer
    private let config: ClassifierConfig
    private let sampleRate: Float
    private let sensitivitySettings: SensitivitySettings
    private let ambientTracker: AmbientLevelTracker
    
    // MARK: - Initialization
    
    init(
        config: ClassifierConfig = .default,
        sampleRate: Float = 44100,
        sensitivitySettings: SensitivitySettings = .shared,
        ambientTracker: AmbientLevelTracker = .shared
    ) {
        self.config = config
        self.sampleRate = sampleRate
        self.sensitivitySettings = sensitivitySettings
        self.ambientTracker = ambientTracker
        self.frequencyAnalyzer = FrequencyAnalyzer(fftSize: 2048, sampleRate: sampleRate)
    }
    
    /// Get current thresholds based on ambient level and sensitivity
    private var currentThresholds: (mild: Float, medium: Float, hard: Float, extreme: Float) {
        sensitivitySettings.getThresholds(ambientLevel: ambientTracker.ambientLevel)
    }
    
    /// Current minimum decibel level (mild threshold)
    private var effectiveMinimumDecibelLevel: Float {
        currentThresholds.mild
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
        
        // Ignore sounds below minimum threshold (using sensitivity-adjusted level)
        guard decibelLevel >= effectiveMinimumDecibelLevel else {
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
        
        // Check if this is a footstep candidate using multiple criteria:
        // 1. Dominant frequency must be low (at or below threshold)
        // 2. Impact energy (20-100 Hz) must be significant portion of total energy
        // 3. Events at boundary frequency (60-70 Hz) need higher dB OR very high impact ratio
        let isLowFrequency = spectrum.dominantFrequency <= config.lowFrequencyThreshold
        let totalEnergy = spectrum.impactEnergy + spectrum.lowMidEnergy + spectrum.midEnergy + spectrum.highMidEnergy + spectrum.highEnergy
        let impactRatio = totalEnergy > 0 ? spectrum.impactEnergy / totalEnergy : 0
        let hasStrongImpact = impactRatio >= config.minimumImpactEnergyRatio
        
        // For events at the boundary frequency (60-70 Hz):
        // - Need dB >= 35 AND impact ratio < 0.57 (to filter out false positives with high impact ratio)
        // - OR need very high dB (>= 43) regardless of impact ratio
        let isAtBoundary = spectrum.dominantFrequency >= 60 && spectrum.dominantFrequency <= 70
        let hasModerateDb = decibelLevel >= config.boundaryFrequencyMinDb
        let hasVeryHighDb = decibelLevel >= 43.0
        let hasNormalImpact = impactRatio < 0.57
        let meetsBoundaryRequirement = !isAtBoundary || hasVeryHighDb || (hasModerateDb && hasNormalImpact)
        
        // Must pass all checks to be considered a footstep
        let isFootstepCandidate = isLowFrequency && hasStrongImpact && meetsBoundaryRequirement
        
        // Classify the sound
        let (type, confidence) = classifySound(
            isFootstepCandidate: isFootstepCandidate,
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
        isFootstepCandidate: Bool,
        decibelLevel: Float,
        interval: TimeInterval?
    ) -> (FootstepType, Float) {
        // If not a footstep candidate, it's not a footstep
        guard isFootstepCandidate else {
            return (.unknown, 0.3)
        }
        
        // Get current thresholds based on ambient level
        let thresholds = currentThresholds
        
        // Determine base stomping type from decibel level using ambient-relative thresholds
        // Mild: ambient + 5 to ambient + 10
        // Medium: ambient + 10 to ambient + 15
        // Hard: ambient + 15 to ambient + 20
        // Extreme: ambient + 20+
        let baseType: FootstepType
        let baseConfidence: Float
        
        if decibelLevel < thresholds.medium {
            // Mild stomping (ambient + 5 to ambient + 10)
            baseType = .mildStomping
            let range = thresholds.medium - thresholds.mild
            let normalized = (decibelLevel - thresholds.mild) / range
            baseConfidence = 0.7 + normalized * 0.15
        } else if decibelLevel < thresholds.hard {
            // Medium stomping (ambient + 10 to ambient + 15)
            baseType = .mediumStomping
            let range = thresholds.hard - thresholds.medium
            let normalized = (decibelLevel - thresholds.medium) / range
            baseConfidence = 0.75 + normalized * 0.1
        } else if decibelLevel < thresholds.extreme {
            // Hard stomping (ambient + 15 to ambient + 20)
            baseType = .hardStomping
            let range = thresholds.extreme - thresholds.hard
            let normalized = (decibelLevel - thresholds.hard) / range
            baseConfidence = 0.8 + normalized * 0.1
        } else {
            // Extreme stomping (ambient + 20+)
            baseType = .extremeStomping
            baseConfidence = min(0.95, 0.85 + (decibelLevel - thresholds.extreme) / 20 * 0.1)
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
