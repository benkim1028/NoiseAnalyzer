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
