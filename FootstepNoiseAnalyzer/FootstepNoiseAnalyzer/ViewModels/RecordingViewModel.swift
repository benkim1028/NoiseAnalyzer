//
//  RecordingViewModel.swift
//  FootstepNoiseAnalyzer
//
//  ViewModel for managing recording state and real-time feedback.
//  Requirements: 1.1, 1.2, 1.3, 8.1, 8.2, 8.3
//

import Foundation
import Combine
import SwiftUI

/// ViewModel for the recording view, managing recording state and real-time feedback.
@MainActor
final class RecordingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether recording is currently active
    @Published private(set) var isRecording: Bool = false
    
    /// Whether recording is currently paused
    @Published private(set) var isPaused: Bool = false
    
    /// Current duration of the recording in seconds
    @Published private(set) var currentDuration: TimeInterval = 0
    
    /// Current audio level (0.0 to 1.0)
    @Published private(set) var audioLevel: Float = 0
    
    /// Number of events detected in the current session
    @Published private(set) var eventCount: Int = 0
    
    /// The last detected footstep event
    @Published private(set) var lastDetectedEvent: FootstepEvent?
    
    /// Current dominant frequency in Hz
    @Published private(set) var dominantFrequency: Float = 0
    
    /// Current spectral centroid in Hz
    @Published private(set) var spectralCentroid: Float = 0
    
    /// Current error message to display
    @Published var errorMessage: String?
    
    /// Whether an error alert should be shown
    @Published var showError: Bool = false
    
    /// Sensitivity settings for microphone detection
    let sensitivitySettings = SensitivitySettings.shared
    
    // MARK: - Computed Properties
    
    /// Formatted duration string (MM:SS or HH:MM:SS)
    var formattedDuration: String {
        let hours = Int(currentDuration) / 3600
        let minutes = (Int(currentDuration) % 3600) / 60
        let seconds = Int(currentDuration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Recording status text for display
    var statusText: String {
        if isRecording {
            return isPaused ? "Paused" : "Recording"
        }
        return "Ready"
    }
    
    // MARK: - Private Properties
    
    private let recordingService: RecordingServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var durationTimer: Timer?
    
    // MARK: - Initialization
    
    /// Initialize the view model with a recording service
    /// - Parameter recordingService: The recording service to use
    init(recordingService: RecordingServiceProtocol = RecordingService()) {
        self.recordingService = recordingService
        setupSubscriptions()
    }

    
    // MARK: - Public Methods
    
    /// Start a new recording session
    func startRecording() {
        Task {
            do {
                _ = try await recordingService.startRecording()
                isRecording = true
                isPaused = false
                eventCount = 0
                lastDetectedEvent = nil
                startDurationTimer()
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Stop the current recording
    func stopRecording() {
        Task {
            do {
                _ = try await recordingService.stopRecording()
                isRecording = false
                isPaused = false
                stopDurationTimer()
                currentDuration = 0
                audioLevel = 0
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Pause the current recording
    func pauseRecording() {
        recordingService.pauseRecording()
        isPaused = true
        stopDurationTimer()
    }
    
    /// Resume a paused recording
    func resumeRecording() {
        recordingService.resumeRecording()
        isPaused = false
        startDurationTimer()
    }
    
    /// Toggle recording state (start/stop)
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Toggle pause state
    func togglePause() {
        if isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }
    
    // MARK: - Private Methods
    
    /// Set up Combine subscriptions for real-time updates
    private func setupSubscriptions() {
        // Subscribe to audio level updates
        recordingService.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)
        
        // Subscribe to event count updates
        recordingService.eventCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.eventCount = count
            }
            .store(in: &cancellables)
        
        // Subscribe to detected events
        recordingService.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.lastDetectedEvent = event
            }
            .store(in: &cancellables)
        
        // Subscribe to frequency spectrum updates
        recordingService.frequencyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spectrum in
                self?.dominantFrequency = spectrum.dominantFrequency
                self?.spectralCentroid = spectrum.spectralCentroid
            }
            .store(in: &cancellables)
    }
    
    /// Start the duration update timer
    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }
    }
    
    /// Stop the duration update timer
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    /// Update the current duration from the recording service
    private func updateDuration() {
        currentDuration = recordingService.currentDuration
    }
    
    /// Handle errors from recording operations
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    deinit {
        durationTimer?.invalidate()
    }
}
