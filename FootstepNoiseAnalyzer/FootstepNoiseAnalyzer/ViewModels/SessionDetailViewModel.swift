//
//  SessionDetailViewModel.swift
//  FootstepNoiseAnalyzer
//
//  ViewModel for managing session detail view with events.
//  Requirements: 5.3, 5.4, 7.2
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

/// ViewModel for the session detail view, managing events for a specific session.
@MainActor
final class SessionDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// The session being viewed
    @Published private(set) var session: RecordingSession
    
    /// List of events for this session
    @Published private(set) var events: [FootstepEvent] = []
    
    /// Whether data is currently being loaded
    @Published private(set) var isLoading: Bool = false
    
    /// Current error message to display
    @Published var errorMessage: String?
    
    /// Whether an error alert should be shown
    @Published var showError: Bool = false
    
    /// The event currently being edited (for adding notes)
    @Published var editingEvent: FootstepEvent?
    
    /// The note text being edited
    @Published var editingNoteText: String = ""
    
    /// Whether audio is currently playing
    @Published var isPlayingAudio: Bool = false
    
    /// Current playback progress (0.0 to 1.0)
    @Published var playbackProgress: Double = 0
    
    /// ID of the event currently being played (for event snippet playback)
    @Published var currentlyPlayingEventId: UUID?
    
    /// Audio player for session playback
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var eventPlaybackEndTime: TimeInterval?
    private var playingEventId: UUID?
    
    // MARK: - Computed Properties
    
    /// Total number of events in this session
    var eventCount: Int {
        events.count
    }
    
    /// Whether there are any events
    var hasEvents: Bool {
        !events.isEmpty
    }
    
    /// Events grouped by hour for timeline display
    var eventsByHour: [Int: [FootstepEvent]] {
        Dictionary(grouping: events) { event in
            Calendar.current.component(.hour, from: event.timestamp)
        }
    }
    
    /// Whether the session has audio files to play
    var hasAudioFiles: Bool {
        !session.fileURLs.isEmpty && session.fileURLs.first.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
    
    /// Formatted playback time
    var playbackTimeString: String {
        guard let player = audioPlayer else { return "0:00 / 0:00" }
        let current = formatTime(player.currentTime)
        let total = formatTime(player.duration)
        return "\(current) / \(total)"
    }
    
    // MARK: - Private Properties
    
    private let eventService: EventServiceProtocol
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    
    // MARK: - Initialization
    
    /// Initialize the view model with a session and event service
    /// - Parameters:
    ///   - session: The recording session to display
    ///   - eventService: The event service for data operations
    init(
        session: RecordingSession,
        eventService: EventServiceProtocol = EventService.shared
    ) {
        self.session = session
        self.eventService = eventService
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .short
        
        self.timeFormatter = DateFormatter()
        self.timeFormatter.dateFormat = "h:mm:ss a"
    }

    
    // MARK: - Public Methods
    
    /// Fetch all events for this session
    func fetchEvents() {
        isLoading = true
        
        Task {
            do {
                let fetchedEvents = try await eventService.fetchEvents(for: session.id)
                events = fetchedEvents
                isLoading = false
            } catch {
                handleError(error)
                isLoading = false
            }
        }
    }
    
    /// Delete an event
    /// - Parameter event: The event to delete
    func deleteEvent(_ event: FootstepEvent) {
        Task {
            do {
                try await eventService.deleteEvent(event)
                events.removeAll { $0.id == event.id }
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Delete events at the specified index set
    /// - Parameter offsets: The index set of events to delete
    func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            let event = events[index]
            deleteEvent(event)
        }
    }
    
    /// Start editing a note for an event
    /// - Parameter event: The event to edit
    func startEditingNote(for event: FootstepEvent) {
        editingEvent = event
        editingNoteText = event.notes ?? ""
    }
    
    /// Save the currently editing note
    func saveNote() {
        guard let event = editingEvent else { return }
        
        Task {
            do {
                try await eventService.addNote(to: event.id, note: editingNoteText)
                
                // Update local event
                if let index = events.firstIndex(where: { $0.id == event.id }) {
                    var updatedEvent = events[index]
                    updatedEvent.notes = editingNoteText.isEmpty ? nil : editingNoteText
                    events[index] = updatedEvent
                }
                
                // Clear editing state
                editingEvent = nil
                editingNoteText = ""
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Cancel editing the current note
    func cancelEditingNote() {
        editingEvent = nil
        editingNoteText = ""
    }
    
    // MARK: - Audio Playback Methods
    
    /// Play the session's audio recording
    func playAudio() {
        guard let fileURL = session.fileURLs.first else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.play()
            isPlayingAudio = true
            startPlaybackTimer()
        } catch {
            handleError(error)
        }
    }
    
    /// Pause audio playback
    func pauseAudio() {
        audioPlayer?.pause()
        isPlayingAudio = false
        stopPlaybackTimer()
    }
    
    /// Stop audio playback
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlayingAudio = false
        playbackProgress = 0
        eventPlaybackEndTime = nil
        playingEventId = nil
        currentlyPlayingEventId = nil
        stopPlaybackTimer()
    }
    
    /// Toggle play/pause
    func togglePlayback() {
        if isPlayingAudio {
            pauseAudio()
        } else {
            playAudio()
        }
    }
    
    /// Seek to a specific position (0.0 to 1.0)
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = player.duration * progress
        playbackProgress = progress
    }
    
    /// Play audio for a specific event (plays ~1 second snippet from the event's timestamp)
    /// - Parameter event: The event to play audio for
    func playEventAudio(for event: FootstepEvent) {
        guard let fileURL = session.fileURLs.first else { return }
        
        // Stop any current playback
        stopAudio()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            
            guard let player = audioPlayer else { return }
            
            // Calculate start time (slightly before the event to capture the full sound)
            let startTime = max(0, event.timestampInRecording - 0.2)
            
            // Set end time (~1.5 seconds of audio)
            let snippetDuration: TimeInterval = 1.5
            eventPlaybackEndTime = min(startTime + snippetDuration, player.duration)
            playingEventId = event.id
            currentlyPlayingEventId = event.id
            
            // Seek to the event's timestamp and play
            player.currentTime = startTime
            player.play()
            isPlayingAudio = true
            
            // Start timer to monitor playback and stop at end time
            startEventPlaybackTimer()
        } catch {
            handleError(error)
        }
    }
    
    /// Check if a specific event is currently playing
    func isEventPlaying(_ event: FootstepEvent) -> Bool {
        return currentlyPlayingEventId == event.id && isPlayingAudio
    }
    
    private func startEventPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateEventPlaybackProgress()
            }
        }
    }
    
    private func updateEventPlaybackProgress() {
        guard let player = audioPlayer else { return }
        
        // Check if we've reached the end time for event playback
        if let endTime = eventPlaybackEndTime {
            if player.currentTime >= endTime || !player.isPlaying {
                stopAudio()
                return
            }
        }
        
        if player.isPlaying {
            playbackProgress = player.currentTime / player.duration
        } else if player.currentTime >= player.duration - 0.1 {
            stopAudio()
        }
    }
    
    /// Export the audio file to share
    func getAudioFileURL() -> URL? {
        return session.fileURLs.first
    }
    
    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackProgress()
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackProgress() {
        guard let player = audioPlayer else { return }
        
        if player.isPlaying {
            playbackProgress = player.currentTime / player.duration
        } else if player.currentTime >= player.duration - 0.1 {
            // Playback finished
            isPlayingAudio = false
            playbackProgress = 0
            stopPlaybackTimer()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Format an event's timestamp for display
    /// - Parameter event: The event to format
    /// - Returns: Formatted time string
    func formattedTime(for event: FootstepEvent) -> String {
        timeFormatter.string(from: event.timestamp)
    }
    
    /// Format the session's date for display
    /// - Returns: Formatted date string
    func formattedSessionDate() -> String {
        dateFormatter.string(from: session.startTime)
    }
    
    /// Format the session's duration for display
    /// - Returns: Formatted duration string
    func formattedSessionDuration() -> String {
        let duration = session.duration
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    /// Get a display string for the classification type
    /// - Parameter type: The footstep type
    /// - Returns: Human-readable type string
    func displayName(for type: FootstepType) -> String {
        type.displayName
    }
    
    /// Get a color for the footstep type
    /// - Parameter type: The footstep type
    /// - Returns: Color for the type
    func color(for type: FootstepType) -> Color {
        switch type {
        case .mildStomping:
            return .green
        case .mediumStomping:
            return .orange
        case .hardStomping:
            return .red
        case .running:
            return .purple
        case .unknown:
            return .gray
        }
    }
    
    // MARK: - Private Methods
    
    /// Handle errors from operations
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
