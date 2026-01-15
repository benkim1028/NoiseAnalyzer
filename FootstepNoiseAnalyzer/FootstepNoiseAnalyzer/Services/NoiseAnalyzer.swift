//
//  NoiseAnalyzer.swift
//  FootstepNoiseAnalyzer
//
//  Processes audio buffers to detect potential footstep events using signal processing.
//  Requirements: 3.1, 3.2, 3.4
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

/// Represents a detected audio event before classification.
struct AudioEvent: Equatable {
    /// Timestamp of the event relative to recording start
    let timestamp: TimeInterval
    
    /// RMS amplitude of the detected sound
    let amplitude: Float
    
    /// The audio buffer containing the detected sound
    let buffer: AVAudioPCMBuffer
    
    static func == (lhs: AudioEvent, rhs: AudioEvent) -> Bool {
        return lhs.timestamp == rhs.timestamp && lhs.amplitude == rhs.amplitude
    }
}

/// Protocol defining the interface for noise analysis operations.
protocol NoiseAnalyzerProtocol: AnyObject {
    /// Publisher that emits detected audio events
    var detectionPublisher: AnyPublisher<AudioEvent, Never> { get }
    
    /// Current detection threshold (0.0 to 1.0)
    var detectionThreshold: Float { get }
    
    /// Analyze an audio buffer for potential footstep events
    /// - Parameters:
    ///   - buffer: The audio buffer to analyze
    ///   - timestamp: The timestamp of the buffer relative to recording start
    func analyze(buffer: AVAudioPCMBuffer, timestamp: TimeInterval)
    
    /// Set the detection threshold for event detection
    /// - Parameter threshold: New threshold value (0.0 to 1.0)
    func setDetectionThreshold(_ threshold: Float)
    
    /// Reset the analyzer state (e.g., when starting a new recording)
    func reset()
}

/// Implementation of NoiseAnalyzerProtocol for detecting footstep-like sounds.
final class NoiseAnalyzer: NoiseAnalyzerProtocol {
    
    // MARK: - Public Properties
    
    var detectionPublisher: AnyPublisher<AudioEvent, Never> {
        detectionSubject.eraseToAnyPublisher()
    }
    
    private(set) var detectionThreshold: Float
    
    // MARK: - Private Properties
    
    private let detectionSubject = PassthroughSubject<AudioEvent, Never>()
    private let sensitivitySettings: SensitivitySettings
    private var cancellables = Set<AnyCancellable>()
    
    /// Minimum time interval between detected events (in seconds)
    private let minimumEventInterval: TimeInterval = 0.1
    
    /// Timestamp of the last detected event
    private var lastEventTime: TimeInterval = -1
    
    /// Peak detection window size (number of samples)
    private let peakWindowSize: Int = 512
    
    /// Minimum peak prominence for detection
    private let minimumPeakProminence: Float = 0.1
    
    // MARK: - Initialization
    
    init(threshold: Float? = nil, sensitivitySettings: SensitivitySettings = .shared) {
        self.sensitivitySettings = sensitivitySettings
        self.detectionThreshold = threshold ?? sensitivitySettings.detectionThreshold
        
        // Subscribe to sensitivity changes
        sensitivitySettings.$sensitivity
            .dropFirst()
            .sink { [weak self] _ in
                self?.detectionThreshold = sensitivitySettings.detectionThreshold
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func analyze(buffer: AVAudioPCMBuffer, timestamp: TimeInterval) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        // Calculate RMS amplitude
        let rms = calculateRMS(channelData, frameCount: frameCount)
        
        // Detect peaks in the audio signal
        let hasPeak = detectPeaks(channelData, frameCount: frameCount)
        
        // Check if this qualifies as a footstep event
        let meetsThreshold = rms > detectionThreshold
        let meetsTimeInterval = (lastEventTime < 0) || (timestamp - lastEventTime >= minimumEventInterval)
        
        if meetsThreshold && meetsTimeInterval && hasPeak {
            let event = AudioEvent(
                timestamp: timestamp,
                amplitude: rms,
                buffer: buffer
            )
            detectionSubject.send(event)
            lastEventTime = timestamp
        }
    }
    
    func setDetectionThreshold(_ threshold: Float) {
        detectionThreshold = max(0, min(1, threshold))
    }
    
    func reset() {
        lastEventTime = -1
    }
    
    // MARK: - Private Methods
    
    /// Calculate the Root Mean Square (RMS) of the audio samples.
    /// - Parameters:
    ///   - data: Pointer to the audio sample data
    ///   - frameCount: Number of frames in the buffer
    /// - Returns: RMS value of the audio signal
    func calculateRMS(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = data[i]
            sum += sample * sample
        }
        
        return sqrt(sum / Float(frameCount))
    }
    
    /// Detect peaks in the audio signal that may indicate footstep transients.
    /// - Parameters:
    ///   - data: Pointer to the audio sample data
    ///   - frameCount: Number of frames in the buffer
    /// - Returns: True if significant peaks are detected
    func detectPeaks(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        guard frameCount >= peakWindowSize else {
            // For small buffers, just check if any sample exceeds threshold
            for i in 0..<frameCount {
                if abs(data[i]) > detectionThreshold {
                    return true
                }
            }
            return false
        }
        
        // Analyze the buffer in windows to find peaks
        let windowCount = frameCount / peakWindowSize
        var maxPeak: Float = 0
        var minValley: Float = Float.greatestFiniteMagnitude
        
        for windowIndex in 0..<windowCount {
            let startIndex = windowIndex * peakWindowSize
            var windowMax: Float = 0
            var windowMin: Float = Float.greatestFiniteMagnitude
            
            for i in 0..<peakWindowSize {
                let sample = abs(data[startIndex + i])
                windowMax = max(windowMax, sample)
                windowMin = min(windowMin, sample)
            }
            
            maxPeak = max(maxPeak, windowMax)
            minValley = min(minValley, windowMin)
        }
        
        // Check if there's sufficient peak prominence (difference between peak and valley)
        let prominence = maxPeak - minValley
        return prominence >= minimumPeakProminence && maxPeak > detectionThreshold
    }
}
