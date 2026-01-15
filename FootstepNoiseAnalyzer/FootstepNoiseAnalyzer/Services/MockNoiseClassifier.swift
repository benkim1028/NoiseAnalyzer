//
//  MockNoiseClassifier.swift
//  FootstepNoiseAnalyzer
//
//  A mock implementation of NoiseClassifierProtocol for testing.
//

import Foundation
import AVFoundation

/// A mock noise classifier for testing purposes.
final class MockNoiseClassifier: NoiseClassifierProtocol {
    
    // MARK: - Configuration
    
    private var fixedResult: FootstepClassification?
    private var errorToThrow: Error?
    private var classificationDelay: TimeInterval = 0
    private let config: ClassifierConfig
    
    // MARK: - Initialization
    
    init(config: ClassifierConfig = .default) {
        self.config = config
    }
    
    init(fixedResult: FootstepClassification) {
        self.fixedResult = fixedResult
        self.config = .default
    }
    
    init(error: Error) {
        self.errorToThrow = error
        self.config = .default
    }
    
    // MARK: - Configuration Methods
    
    func setFixedResult(_ result: FootstepClassification) {
        self.fixedResult = result
        self.errorToThrow = nil
    }
    
    func setError(_ error: Error) {
        self.errorToThrow = error
        self.fixedResult = nil
    }
    
    func setClassificationDelay(_ delay: TimeInterval) {
        self.classificationDelay = delay
    }
    
    func reset() {
        self.fixedResult = nil
        self.errorToThrow = nil
        self.classificationDelay = 0
    }
    
    // MARK: - NoiseClassifierProtocol
    
    func classify(
        audioBuffer: AVAudioPCMBuffer,
        previousConfirmedEventTime: TimeInterval?,
        recentLoudEventTime: TimeInterval?,
        recentLoudEventDb: Float?,
        currentTime: TimeInterval
    ) -> FootstepClassification? {
        if let fixedResult = fixedResult {
            return fixedResult
        }
        
        guard audioBuffer.frameLength > 0,
              let channelData = audioBuffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameCount = Int(audioBuffer.frameLength)
        
        // Calculate mock decibel level
        let rms = calculateRMS(channelData, frameCount: frameCount)
        let dbFS = rms > 0 ? 20 * log10(rms) : -96
        let decibelLevel = max(0, dbFS + 96)
        
        // Mock dominant frequency (low frequency for footsteps)
        let dominantFrequency: Float = 150  // Simulated low frequency
        
        let interval: TimeInterval? = previousConfirmedEventTime.map { currentTime - $0 }
        
        // Determine type based on decibel level
        let type: FootstepType
        let confidence: Float
        
        if decibelLevel < config.minimumDecibelLevel {
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
        
        // Check for running first (using confirmed event interval)
        if let interval = interval, interval <= config.runningIntervalThreshold {
            type = .running
            confidence = 0.85
        } else if decibelLevel < config.mildToMediumDb {
            type = .mildStomping
            confidence = 0.75
        } else if decibelLevel < config.mediumToHardDb {
            type = .mediumStomping
            confidence = 0.80
        } else {
            type = .hardStomping
            confidence = 0.90
        }
        
        return FootstepClassification(
            type: type,
            confidence: confidence,
            decibelLevel: decibelLevel,
            dominantFrequency: dominantFrequency,
            intervalFromPrevious: interval
        )
    }
    
    // MARK: - Private Methods
    
    private func calculateRMS(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = data[i]
            sum += sample * sample
        }
        
        return sqrt(sum / Float(frameCount))
    }
}

// MARK: - Test Helpers

extension MockNoiseClassifier {
    
    static func createTestBuffer(
        amplitude: Float = 0.5,
        frequency: Float = 100.0,
        sampleRate: Double = 44100.0,
        duration: TimeInterval = 0.1
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let angularFrequency = 2.0 * Float.pi * frequency / Float(sampleRate)
        
        for i in 0..<Int(frameCount) {
            channelData[i] = amplitude * sin(angularFrequency * Float(i))
        }
        
        return buffer
    }
    
    /// Create a buffer simulating mild stomping (low amplitude, low frequency)
    static func createMildStompingBuffer() -> AVAudioPCMBuffer? {
        return createTestBuffer(amplitude: 0.1, frequency: 80.0, duration: 0.15)
    }
    
    /// Create a buffer simulating medium stomping
    static func createMediumStompingBuffer() -> AVAudioPCMBuffer? {
        return createTestBuffer(amplitude: 0.3, frequency: 80.0, duration: 0.15)
    }
    
    /// Create a buffer simulating hard stomping (high amplitude, low frequency)
    static func createHardStompingBuffer() -> AVAudioPCMBuffer? {
        return createTestBuffer(amplitude: 0.8, frequency: 60.0, duration: 0.15)
    }
    
    /// Create a buffer simulating running
    static func createRunningBuffer() -> AVAudioPCMBuffer? {
        return createTestBuffer(amplitude: 0.5, frequency: 100.0, duration: 0.08)
    }
}
