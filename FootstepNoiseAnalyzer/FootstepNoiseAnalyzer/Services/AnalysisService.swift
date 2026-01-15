//
//  AnalysisService.swift
//  FootstepNoiseAnalyzer
//
//  Coordinates real-time audio analysis pipeline, connecting NoiseAnalyzer
//  and NoiseClassifier to produce FootstepEvents.
//  Requirements: 3.1, 4.1
//

import Foundation
import AVFoundation
import Combine

/// Represents a detected footstep event with its associated audio buffer
struct DetectedFootstepEvent {
    let event: FootstepEvent
    let audioBuffer: AVAudioPCMBuffer?
}

/// Protocol defining the interface for analysis service operations.
protocol AnalysisServiceProtocol: AnyObject {
    /// Publisher that emits classified footstep events with audio buffers
    var detectedEventPublisher: AnyPublisher<DetectedFootstepEvent, Never> { get }
    
    /// Publisher that emits classified footstep events (legacy, without audio)
    var eventPublisher: AnyPublisher<FootstepEvent, Never> { get }
    
    /// Whether analysis is currently active
    var isAnalyzing: Bool { get }
    
    /// Start analysis for a recording session
    /// - Parameter session: The recording session to analyze
    func startAnalysis(for session: RecordingSession)
    
    /// Stop the current analysis
    func stopAnalysis()
    
    /// Process an audio buffer for analysis
    /// - Parameters:
    ///   - buffer: The audio buffer to analyze
    ///   - timestamp: The timestamp of the buffer
    func processBuffer(_ buffer: AVAudioPCMBuffer, timestamp: TimeInterval)
}

/// Implementation of AnalysisServiceProtocol coordinating noise analysis and classification.
final class AnalysisService: AnalysisServiceProtocol {
    
    // MARK: - Public Properties
    
    var detectedEventPublisher: AnyPublisher<DetectedFootstepEvent, Never> {
        detectedEventSubject.eraseToAnyPublisher()
    }
    
    var eventPublisher: AnyPublisher<FootstepEvent, Never> {
        detectedEventSubject.map { $0.event }.eraseToAnyPublisher()
    }
    
    private(set) var isAnalyzing: Bool = false
    
    // MARK: - Private Properties
    
    private let noiseAnalyzer: NoiseAnalyzerProtocol
    private let noiseClassifier: NoiseClassifierProtocol
    private let detectedEventSubject = PassthroughSubject<DetectedFootstepEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var currentSession: RecordingSession?
    private var lastEventTime: TimeInterval?
    private var lastEventDb: Float?
    
    // MARK: - Initialization
    
    /// Initialize the analysis service with dependencies.
    /// - Parameters:
    ///   - noiseAnalyzer: The noise analyzer for detecting audio events
    ///   - noiseClassifier: The classifier for categorizing detected sounds
    init(
        noiseAnalyzer: NoiseAnalyzerProtocol = NoiseAnalyzer(),
        noiseClassifier: NoiseClassifierProtocol = NoiseClassifier()
    ) {
        self.noiseAnalyzer = noiseAnalyzer
        self.noiseClassifier = noiseClassifier
    }
    
    // MARK: - Public Methods
    
    func startAnalysis(for session: RecordingSession) {
        guard !isAnalyzing else { return }
        
        currentSession = session
        isAnalyzing = true
        lastEventTime = nil
        lastEventDb = nil
        
        // Reset the analyzer state for a new session
        noiseAnalyzer.reset()
        
        // Subscribe to detection events from the noise analyzer
        noiseAnalyzer.detectionPublisher
            .sink { [weak self] audioEvent in
                self?.handleDetectedEvent(audioEvent)
            }
            .store(in: &cancellables)
    }
    
    func stopAnalysis() {
        isAnalyzing = false
        currentSession = nil
        lastEventTime = nil
        lastEventDb = nil
        cancellables.removeAll()
    }
    
    func processBuffer(_ buffer: AVAudioPCMBuffer, timestamp: TimeInterval) {
        guard isAnalyzing else { return }
        noiseAnalyzer.analyze(buffer: buffer, timestamp: timestamp)
    }
    
    // MARK: - Private Methods
    
    /// Handle a detected audio event by classifying it and emitting a FootstepEvent.
    private func handleDetectedEvent(_ audioEvent: AudioEvent) {
        guard let session = currentSession else { return }
        
        let currentTime = audioEvent.timestamp
        
        // Classify the detected audio
        guard let classification = noiseClassifier.classify(
            audioBuffer: audioEvent.buffer,
            previousConfirmedEventTime: lastEventTime,
            recentLoudEventTime: lastEventTime,
            recentLoudEventDb: lastEventDb,
            currentTime: currentTime
        ) else {
            return // Sound didn't meet classification criteria
        }
        
        // Skip unknown sounds
        guard classification.type != .unknown else { return }
        
        // Update last event tracking
        lastEventTime = currentTime
        lastEventDb = classification.decibelLevel
        
        // Create a FootstepEvent from the classification
        let footstepEvent = FootstepEvent(
            id: UUID(),
            sessionId: session.id,
            timestamp: Date(),
            timestampInRecording: currentTime,
            classification: classification,
            audioClipURL: nil,
            notes: nil
        )
        
        // Emit the event with its audio buffer
        let detectedEvent = DetectedFootstepEvent(
            event: footstepEvent,
            audioBuffer: audioEvent.buffer
        )
        detectedEventSubject.send(detectedEvent)
    }
}
