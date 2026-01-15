//
//  EventService.swift
//  FootstepNoiseAnalyzer
//
//  Manages persistence and retrieval of footstep events, coordinating
//  between Core Data storage and file storage for audio clips.
//  Requirements: 5.1, 5.2, 5.3, 5.4
//

import Foundation

/// Errors that can occur during event service operations
enum EventServiceError: Error, LocalizedError {
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case eventNotFound
    case audioClipSaveFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save event: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch events: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete event: \(error.localizedDescription)"
        case .eventNotFound:
            return "Event not found"
        case .audioClipSaveFailed(let error):
            return "Failed to save audio clip: \(error.localizedDescription)"
        }
    }
}

/// Protocol defining event service operations
protocol EventServiceProtocol {
    /// Saves a footstep event with optional audio clip data
    /// - Parameters:
    ///   - event: The event to save
    ///   - audioClipData: Optional audio data to store
    /// - Returns: The saved event with updated audioClipURL if audio was provided
    func save(event: FootstepEvent, audioClipData: Data?) async throws -> FootstepEvent
    
    /// Fetches all events for a specific session, ordered chronologically
    /// - Parameter sessionId: The session ID
    /// - Returns: Array of events sorted by timestamp (ascending)
    func fetchEvents(for sessionId: UUID) async throws -> [FootstepEvent]
    
    /// Fetches events within a date range, ordered chronologically
    /// - Parameters:
    ///   - from: Start of the date range
    ///   - to: End of the date range
    /// - Returns: Array of events sorted by timestamp (ascending)
    func fetchEvents(from: Date, to: Date) async throws -> [FootstepEvent]
    
    /// Deletes a footstep event and its associated audio clip
    /// - Parameter event: The event to delete
    func deleteEvent(_ event: FootstepEvent) async throws
    
    /// Adds or updates a note on an event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - note: The note text to add
    func addNote(to eventId: UUID, note: String) async throws
    
    /// Fetches a single event by ID
    /// - Parameter id: The event ID
    /// - Returns: The event if found
    func fetchEvent(by id: UUID) async throws -> FootstepEvent?
}

/// Event service implementation coordinating Core Data and file storage
class EventService: EventServiceProtocol {
    
    /// Shared instance for app-wide use
    static let shared = EventService()
    
    /// The Core Data store for event persistence
    private let coreDataStore: CoreDataStoreProtocol
    
    /// The file storage for audio clips
    private let fileStorage: FileStorageProtocol
    
    /// Initializes the event service with dependencies
    /// - Parameters:
    ///   - coreDataStore: The Core Data store to use
    ///   - fileStorage: The file storage to use
    init(
        coreDataStore: CoreDataStoreProtocol = CoreDataStore.shared,
        fileStorage: FileStorageProtocol = FileStorage.shared
    ) {
        self.coreDataStore = coreDataStore
        self.fileStorage = fileStorage
    }

    
    // MARK: - EventServiceProtocol Implementation
    
    /// Saves a footstep event with optional audio clip data
    /// - Parameters:
    ///   - event: The event to save
    ///   - audioClipData: Optional audio data to store
    /// - Returns: The saved event with updated audioClipURL if audio was provided
    func save(event: FootstepEvent, audioClipData: Data? = nil) async throws -> FootstepEvent {
        var eventToSave = event
        
        // Save audio clip if provided
        if let audioData = audioClipData, !audioData.isEmpty {
            do {
                let clipURL = try await fileStorage.saveAudioClip(audioData, eventId: event.id)
                eventToSave.audioClipURL = clipURL
            } catch {
                throw EventServiceError.audioClipSaveFailed(underlying: error)
            }
        }
        
        // Save event to Core Data
        do {
            try await coreDataStore.saveEvent(eventToSave)
            return eventToSave
        } catch {
            // If Core Data save fails and we saved an audio clip, clean it up
            if let clipURL = eventToSave.audioClipURL {
                try? await fileStorage.deleteAudioClip(at: clipURL)
            }
            throw EventServiceError.saveFailed(underlying: error)
        }
    }
    
    /// Fetches all events for a specific session, ordered chronologically
    /// - Parameter sessionId: The session ID
    /// - Returns: Array of events sorted by timestamp (ascending)
    func fetchEvents(for sessionId: UUID) async throws -> [FootstepEvent] {
        do {
            return try await coreDataStore.fetchEvents(for: sessionId)
        } catch {
            throw EventServiceError.fetchFailed(underlying: error)
        }
    }
    
    /// Fetches events within a date range, ordered chronologically
    /// - Parameters:
    ///   - from: Start of the date range
    ///   - to: End of the date range
    /// - Returns: Array of events sorted by timestamp (ascending)
    func fetchEvents(from: Date, to: Date) async throws -> [FootstepEvent] {
        do {
            return try await coreDataStore.fetchEvents(from: from, to: to)
        } catch {
            throw EventServiceError.fetchFailed(underlying: error)
        }
    }
    
    /// Deletes a footstep event and its associated audio clip
    /// - Parameter event: The event to delete
    func deleteEvent(_ event: FootstepEvent) async throws {
        // Delete audio clip if it exists
        if let clipURL = event.audioClipURL {
            try? await fileStorage.deleteAudioClip(at: clipURL)
        }
        
        // Delete from Core Data
        do {
            try await coreDataStore.deleteEvent(event)
        } catch {
            throw EventServiceError.deleteFailed(underlying: error)
        }
    }
    
    /// Adds or updates a note on an event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - note: The note text to add
    func addNote(to eventId: UUID, note: String) async throws {
        do {
            try await coreDataStore.updateEventNotes(eventId: eventId, notes: note)
        } catch {
            throw EventServiceError.saveFailed(underlying: error)
        }
    }
    
    /// Fetches a single event by ID
    /// - Parameter id: The event ID
    /// - Returns: The event if found
    func fetchEvent(by id: UUID) async throws -> FootstepEvent? {
        do {
            return try await coreDataStore.fetchEvent(by: id)
        } catch {
            throw EventServiceError.fetchFailed(underlying: error)
        }
    }
}
