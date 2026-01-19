//
//  AmbientLevelTracker.swift
//  FootstepNoiseAnalyzer
//
//  Tracks ambient noise level using a rolling window of audio samples.
//  Ambient level is estimated as the 0th-10th percentile of recent dB readings.
//

import Foundation
import AVFoundation
import Combine

/// Tracks and provides the current ambient noise level.
final class AmbientLevelTracker: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AmbientLevelTracker()
    
    // MARK: - Published Properties
    
    /// Current estimated ambient level in dB SPL
    @Published private(set) var ambientLevel: Float = 30.0
    
    /// Whether enough samples have been collected for a reliable estimate
    @Published private(set) var isCalibrated: Bool = false
    
    // MARK: - Configuration
    
    /// Number of samples to keep in the rolling window
    private let windowSize: Int = 100
    
    /// Minimum samples needed before providing an estimate
    private let minimumSamples: Int = 20
    
    /// Percentile range for ambient estimation (0th to 10th)
    private let lowerPercentile: Float = 0.0
    private let upperPercentile: Float = 0.10
    
    // MARK: - Private Properties
    
    /// Rolling window of dB readings
    private var dbReadings: [Float] = []
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        dbReadings.reserveCapacity(windowSize)
    }
    
    // MARK: - Public Methods
    
    /// Add a dB reading from an audio buffer.
    /// - Parameter dbLevel: The dB SPL level of the buffer
    func addReading(_ dbLevel: Float) {
        lock.lock()
        defer { lock.unlock() }
        
        // Add to rolling window
        dbReadings.append(dbLevel)
        
        // Remove oldest if over capacity
        if dbReadings.count > windowSize {
            dbReadings.removeFirst()
        }
        
        // Update ambient estimate if we have enough samples
        if dbReadings.count >= minimumSamples {
            updateAmbientEstimate()
            if !isCalibrated {
                isCalibrated = true
            }
        }
    }
    
    /// Add a reading from an audio buffer.
    /// - Parameter buffer: The audio buffer to analyze
    func addReading(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        // Calculate RMS
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        
        // Convert to dB SPL
        guard rms > 0 else { return }
        let dbFS = 20 * log10(rms)
        let dbSPL = dbFS + DecibelCalculator.dbFSToSPLOffset
        
        addReading(max(0, dbSPL))
    }
    
    /// Reset the tracker (e.g., when starting a new recording session).
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        dbReadings.removeAll(keepingCapacity: true)
        ambientLevel = 30.0
        isCalibrated = false
    }
    
    /// Get the current classification thresholds based on ambient level.
    /// - Parameter sensitivityOffset: The sensitivity offset in dB
    /// - Returns: Tuple of (mild, medium, hard, extreme) thresholds
    func getThresholds(sensitivityOffset: Float = 0) -> (mild: Float, medium: Float, hard: Float, extreme: Float) {
        let base = ambientLevel + sensitivityOffset
        return (
            mild: base + 5,      // ambient + 5 to ambient + 10
            medium: base + 10,   // ambient + 10 to ambient + 15
            hard: base + 15,     // ambient + 15 to ambient + 20
            extreme: base + 20   // ambient + 20+
        )
    }
    
    // MARK: - Private Methods
    
    /// Update the ambient level estimate from the rolling window.
    private func updateAmbientEstimate() {
        let sorted = dbReadings.sorted()
        let count = sorted.count
        
        // Get 10th and 25th percentile indices
        let lowerIndex = Int(Float(count) * lowerPercentile)
        let upperIndex = Int(Float(count) * upperPercentile)
        
        // Average the values in the percentile range
        let rangeValues = Array(sorted[lowerIndex...upperIndex])
        let average = rangeValues.reduce(0, +) / Float(rangeValues.count)
        
        ambientLevel = average
    }
}
