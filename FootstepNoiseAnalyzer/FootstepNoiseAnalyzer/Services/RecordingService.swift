//
//  RecordingService.swift
//  FootstepNoiseAnalyzer
//
//  Coordinates AudioRecorder and AnalysisService to manage the complete
//  recording session lifecycle and persist detected events.
//  Requirements: 1.1, 1.2, 3.1
//

import Foundation
import AVFoundation
import Combine

/// Protocol defining the interface for recording service operations.
protocol RecordingServiceProtocol: AnyObject {
    /// Whether recording is currently active
    var isRecording: Bool { get }
    
    /// Whether recording is currently paused
    var isPaused: Bool { get }
    
    /// Current duration of the recording in seconds
    var currentDuration: TimeInterval { get }
    
    /// Publisher that emits audio level updates (0.0 to 1.0)
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    
    /// Publisher that emits detected footstep events in real-time
    var eventPublisher: AnyPublisher<FootstepEvent, Never> { get }
    
    /// Publisher that emits the current event count
    var eventCountPublisher: AnyPublisher<Int, Never> { get }
    
    /// Publisher that emits frequency spectrum data
    var frequencyPublisher: AnyPublisher<FrequencySpectrum, Never> { get }
    
    /// The current recording session (nil if not recording)
    var currentSession: RecordingSession? { get }
    
    /// Start a new recording session
    /// - Returns: The newly created RecordingSession
    func startRecording() async throws -> RecordingSession
    
    /// Stop the current recording
    /// - Returns: The completed RecordingSession
    func stopRecording() async throws -> RecordingSession
    
    /// Pause the current recording
    func pauseRecording()
    
    /// Resume a paused recording
    func resumeRecording()
}

/// Implementation of RecordingServiceProtocol coordinating audio recording and analysis.
final class RecordingService: RecordingServiceProtocol {
    
    // MARK: - Public Properties
    
    var isRecording: Bool {
        audioRecorder.isRecording
    }
    
    var isPaused: Bool {
        audioRecorder.isPaused
    }
    
    var currentDuration: TimeInterval {
        audioRecorder.currentDuration
    }
    
    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioRecorder.audioLevelPublisher
    }
    
    var eventPublisher: AnyPublisher<FootstepEvent, Never> {
        analysisService.eventPublisher
    }
    
    var eventCountPublisher: AnyPublisher<Int, Never> {
        eventCountSubject.eraseToAnyPublisher()
    }
    
    var frequencyPublisher: AnyPublisher<FrequencySpectrum, Never> {
        frequencySubject.eraseToAnyPublisher()
    }
    
    private(set) var currentSession: RecordingSession?
    
    // MARK: - Private Properties
    
    private let audioRecorder: AudioRecorderProtocol
    private let analysisService: AnalysisServiceProtocol
    private let eventService: EventServiceProtocol
    private let coreDataStore: CoreDataStoreProtocol
    private let frequencyAnalyzer: FrequencyAnalyzer
    
    private var cancellables = Set<AnyCancellable>()
    private let eventCountSubject = CurrentValueSubject<Int, Never>(0)
    private let frequencySubject = PassthroughSubject<FrequencySpectrum, Never>()
    private var recordingStartTime: Date?
    
    // MARK: - Initialization
    
    /// Initialize the recording service with dependencies.
    /// - Parameters:
    ///   - audioRecorder: The audio recorder for capturing audio
    ///   - analysisService: The analysis service for detecting and classifying footsteps
    ///   - eventService: The event service for persisting detected events
    ///   - coreDataStore: The Core Data store for session persistence
    init(
        audioRecorder: AudioRecorderProtocol = AudioRecorder(),
        analysisService: AnalysisServiceProtocol = AnalysisService(),
        eventService: EventServiceProtocol = EventService.shared,
        coreDataStore: CoreDataStoreProtocol = CoreDataStore.shared
    ) {
        self.audioRecorder = audioRecorder
        self.analysisService = analysisService
        self.eventService = eventService
        self.coreDataStore = coreDataStore
        self.frequencyAnalyzer = FrequencyAnalyzer(fftSize: 2048, sampleRate: 44100)
    }
    
    // MARK: - Public Methods
    
    func startRecording() async throws -> RecordingSession {
        // Start audio recording
        let session = try await audioRecorder.startRecording()
        currentSession = session
        recordingStartTime = Date()
        eventCountSubject.send(0)
        
        // Start analysis for this session
        analysisService.startAnalysis(for: session)
        
        // Subscribe to audio buffers for analysis
        audioRecorder.audioBufferPublisher
            .sink { [weak self] buffer in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let timestamp = Date().timeIntervalSince(startTime)
                self.analysisService.processBuffer(buffer, timestamp: timestamp)
                
                // Perform frequency analysis and publish
                if let spectrum = self.frequencyAnalyzer.analyze(buffer: buffer) {
                    self.frequencySubject.send(spectrum)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to detected events for persistence
        analysisService.eventPublisher
            .sink { [weak self] event in
                self?.handleDetectedEvent(event)
            }
            .store(in: &cancellables)
        
        return session
    }
    
    func stopRecording() async throws -> RecordingSession {
        // Stop analysis first
        analysisService.stopAnalysis()
        
        // Cancel subscriptions
        cancellables.removeAll()
        
        // Stop audio recording
        var session = try await audioRecorder.stopRecording()
        
        // Update session with final event count and mark as completed
        session.eventCount = eventCountSubject.value
        session.status = .completed
        
        // Save session to Core Data
        try await coreDataStore.saveSession(session)
        
        // Reset state
        currentSession = nil
        recordingStartTime = nil
        eventCountSubject.send(0)
        
        return session
    }
    
    func pauseRecording() {
        audioRecorder.pauseRecording()
    }
    
    func resumeRecording() {
        audioRecorder.resumeRecording()
    }
    
    // MARK: - Private Methods
    
    /// Handle a detected footstep event by persisting it and updating the count.
    private func handleDetectedEvent(_ event: FootstepEvent) {
        // Update event count
        let newCount = eventCountSubject.value + 1
        eventCountSubject.send(newCount)
        
        // Update current session event count
        if var session = currentSession {
            session.eventCount = newCount
            currentSession = session
        }
        
        // Persist the event asynchronously
        Task {
            do {
                // Extract audio data from the buffer if available
                // For now, we save without audio clip data - this can be enhanced later
                _ = try await eventService.save(event: event, audioClipData: nil)
            } catch {
                print("Failed to save footstep event: \(error.localizedDescription)")
            }
        }
    }
}
