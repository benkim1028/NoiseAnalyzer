//
//  CoreDataStore.swift
//  FootstepNoiseAnalyzer
//
//  Manages Core Data persistence for recording sessions and footstep events.
//  Requirements: 5.1, 5.3, 7.1, 7.3, 9.1
//

import Foundation
import CoreData

/// Errors that can occur during Core Data operations
enum CoreDataError: Error, LocalizedError {
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case entityNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete data: \(error.localizedDescription)"
        case .entityNotFound:
            return "Entity not found in database"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

/// Protocol defining Core Data store operations
protocol CoreDataStoreProtocol {
    // Session operations
    func saveSession(_ session: RecordingSession) async throws
    func fetchSession(by id: UUID) async throws -> RecordingSession?
    func fetchAllSessions() async throws -> [RecordingSession]
    func deleteSession(_ session: RecordingSession) async throws
    func updateSession(_ session: RecordingSession) async throws
    
    // Event operations
    func saveEvent(_ event: FootstepEvent) async throws
    func fetchEvent(by id: UUID) async throws -> FootstepEvent?
    func fetchEvents(for sessionId: UUID) async throws -> [FootstepEvent]
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [FootstepEvent]
    func deleteEvent(_ event: FootstepEvent) async throws
    func updateEventNotes(eventId: UUID, notes: String) async throws
}

/// Core Data store implementation for persisting recording sessions and footstep events
class CoreDataStore: CoreDataStoreProtocol {
    
    /// Shared instance for app-wide use
    static let shared = CoreDataStore()
    
    /// The persistent container for Core Data
    private let persistentContainer: NSPersistentContainer
    
    /// The main view context
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    /// Initializes the Core Data store
    /// - Parameter inMemory: If true, uses an in-memory store (useful for testing)
    init(inMemory: Bool = false) {
        persistentContainer = NSPersistentContainer(name: "FootstepNoiseAnalyzer")
        
        if inMemory {
            persistentContainer.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        persistentContainer.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    
    // MARK: - Session Operations
    
    /// Saves a recording session to Core Data
    /// - Parameter session: The session to save
    func saveSession(_ session: RecordingSession) async throws {
        try await persistentContainer.performBackgroundTask { context in
            let entity = RecordingSessionEntity(context: context)
            entity.id = session.id
            entity.startTime = session.startTime
            entity.endTime = session.endTime
            entity.eventCount = Int32(session.eventCount)
            entity.status = session.status.rawValue
            entity.fileURLsData = try? JSONEncoder().encode(session.fileURLs.map { $0.absoluteString })
            
            do {
                try context.save()
            } catch {
                throw CoreDataError.saveFailed(underlying: error)
            }
        }
    }
    
    /// Fetches a recording session by ID
    /// - Parameter id: The session ID
    /// - Returns: The session if found, nil otherwise
    func fetchSession(by id: UUID) async throws -> RecordingSession? {
        try await persistentContainer.performBackgroundTask { context in
            let request = RecordingSessionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                return results.first.flatMap { self.mapToRecordingSession($0) }
            } catch {
                throw CoreDataError.fetchFailed(underlying: error)
            }
        }
    }
    
    /// Fetches all recording sessions ordered by start time (newest first)
    /// - Returns: Array of all sessions
    func fetchAllSessions() async throws -> [RecordingSession] {
        try await persistentContainer.performBackgroundTask { context in
            let request = RecordingSessionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \RecordingSessionEntity.startTime, ascending: false)]
            
            do {
                let results = try context.fetch(request)
                return results.compactMap { self.mapToRecordingSession($0) }
            } catch {
                throw CoreDataError.fetchFailed(underlying: error)
            }
        }
    }
    
    /// Deletes a recording session and all associated events
    /// - Parameter session: The session to delete
    func deleteSession(_ session: RecordingSession) async throws {
        try await persistentContainer.performBackgroundTask { context in
            let request = RecordingSessionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", session.id as CVarArg)
            
            do {
                let results = try context.fetch(request)
                guard let entity = results.first else {
                    throw CoreDataError.entityNotFound
                }
                context.delete(entity)
                try context.save()
            } catch let error as CoreDataError {
                throw error
            } catch {
                throw CoreDataError.deleteFailed(underlying: error)
            }
        }
    }
    
    /// Updates an existing recording session
    /// - Parameter session: The session with updated values
    func updateSession(_ session: RecordingSession) async throws {
        try await persistentContainer.performBackgroundTask { context in
            let request = RecordingSessionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", session.id as CVarArg)
            
            do {
                let results = try context.fetch(request)
                guard let entity = results.first else {
                    throw CoreDataError.entityNotFound
                }
                
                entity.endTime = session.endTime
                entity.eventCount = Int32(session.eventCount)
                entity.status = session.status.rawValue
                entity.fileURLsData = try? JSONEncoder().encode(session.fileURLs.map { $0.absoluteString })
                
                try context.save()
            } catch let error as CoreDataError {
                throw error
            } catch {
                throw CoreDataError.saveFailed(underlying: error)
            }
        }
    }

    
    // MARK: - Event Operations
    
    /// Saves a footstep event to Core Data
    /// - Parameter event: The event to save
    func saveEvent(_ event: FootstepEvent) async throws {
        try await persistentContainer.performBackgroundTask { context in
            let entity = FootstepEventEntity(context: context)
            entity.id = event.id
            entity.sessionId = event.sessionId
            entity.timestamp = event.timestamp
            entity.classificationType = event.classification.type.rawValue
            entity.confidence = event.classification.confidence
            // Store decibelLevel and dominantFrequency in notes as JSON for now
            // until Core Data model is updated
            entity.audioClipPath = event.audioClipURL?.path
            entity.notes = event.notes
            
            // Link to session if exists
            let sessionRequest = RecordingSessionEntity.fetchRequest()
            sessionRequest.predicate = NSPredicate(format: "id == %@", event.sessionId as CVarArg)
            if let sessionEntity = try? context.fetch(sessionRequest).first {
                entity.session = sessionEntity
            }
            
            do {
                try context.save()
            } catch {
                throw CoreDataError.saveFailed(underlying: error)
            }
        }
    }
    
    /// Fetches a footstep event by ID
    /// - Parameter id: The event ID
    /// - Returns: The event if found, nil otherwise
    func fetchEvent(by id: UUID) async throws -> FootstepEvent? {
        try await persistentContainer.performBackgroundTask { context in
            let request = FootstepEventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                return results.first.flatMap { self.mapToFootstepEvent($0) }
            } catch {
                throw CoreDataError.fetchFailed(underlying: error)
            }
        }
    }
    
    /// Fetches all events for a specific session, ordered chronologically
    /// - Parameter sessionId: The session ID
    /// - Returns: Array of events for the session
    func fetchEvents(for sessionId: UUID) async throws -> [FootstepEvent] {
        try await persistentContainer.performBackgroundTask { context in
            let request = FootstepEventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \FootstepEventEntity.timestamp, ascending: true)]
            
            do {
                let results = try context.fetch(request)
                return results.compactMap { self.mapToFootstepEvent($0) }
            } catch {
                throw CoreDataError.fetchFailed(underlying: error)
            }
        }
    }
    
    /// Fetches events within a date range, ordered chronologically
    /// - Parameters:
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of events within the range
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [FootstepEvent] {
        try await persistentContainer.performBackgroundTask { context in
            let request = FootstepEventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", 
                                           startDate as CVarArg, endDate as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \FootstepEventEntity.timestamp, ascending: true)]
            
            do {
                let results = try context.fetch(request)
                return results.compactMap { self.mapToFootstepEvent($0) }
            } catch {
                throw CoreDataError.fetchFailed(underlying: error)
            }
        }
    }
    
    /// Deletes a footstep event
    /// - Parameter event: The event to delete
    func deleteEvent(_ event: FootstepEvent) async throws {
        try await persistentContainer.performBackgroundTask { context in
            let request = FootstepEventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", event.id as CVarArg)
            
            do {
                let results = try context.fetch(request)
                guard let entity = results.first else {
                    throw CoreDataError.entityNotFound
                }
                context.delete(entity)
                try context.save()
            } catch let error as CoreDataError {
                throw error
            } catch {
                throw CoreDataError.deleteFailed(underlying: error)
            }
        }
    }
    
    /// Updates the notes for a footstep event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - notes: The new notes string
    func updateEventNotes(eventId: UUID, notes: String) async throws {
        try await persistentContainer.performBackgroundTask { context in
            let request = FootstepEventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
            
            do {
                let results = try context.fetch(request)
                guard let entity = results.first else {
                    throw CoreDataError.entityNotFound
                }
                entity.notes = notes
                try context.save()
            } catch let error as CoreDataError {
                throw error
            } catch {
                throw CoreDataError.saveFailed(underlying: error)
            }
        }
    }

    
    // MARK: - Mapping Helpers
    
    /// Maps a Core Data entity to a RecordingSession model
    private func mapToRecordingSession(_ entity: RecordingSessionEntity) -> RecordingSession? {
        guard let id = entity.id,
              let startTime = entity.startTime,
              let statusString = entity.status,
              let status = SessionStatus(rawValue: statusString) else {
            return nil
        }
        
        var fileURLs: [URL] = []
        if let data = entity.fileURLsData,
           let urlStrings = try? JSONDecoder().decode([String].self, from: data) {
            fileURLs = urlStrings.compactMap { URL(string: $0) }
        }
        
        return RecordingSession(
            id: id,
            startTime: startTime,
            endTime: entity.endTime,
            eventCount: Int(entity.eventCount),
            fileURLs: fileURLs,
            status: status
        )
    }
    
    /// Maps a Core Data entity to a FootstepEvent model
    private func mapToFootstepEvent(_ entity: FootstepEventEntity) -> FootstepEvent? {
        guard let id = entity.id,
              let sessionId = entity.sessionId,
              let timestamp = entity.timestamp,
              let typeString = entity.classificationType,
              let type = FootstepType(rawValue: typeString) else {
            return nil
        }
        
        // Use default values for decibelLevel and dominantFrequency
        // since they're not stored in the current Core Data model
        let classification = FootstepClassification(
            type: type,
            confidence: entity.confidence,
            decibelLevel: 50.0,  // Default value
            dominantFrequency: 100.0,  // Default value
            intervalFromPrevious: nil
        )
        
        var audioClipURL: URL? = nil
        if let path = entity.audioClipPath {
            audioClipURL = URL(fileURLWithPath: path)
        }
        
        return FootstepEvent(
            id: id,
            sessionId: sessionId,
            timestamp: timestamp,
            classification: classification,
            audioClipURL: audioClipURL,
            notes: entity.notes
        )
    }
}
