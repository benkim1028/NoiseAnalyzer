//
//  SessionListViewModel.swift
//  FootstepNoiseAnalyzer
//
//  ViewModel for managing the list of recording sessions.
//  Requirements: 7.1, 7.3
//

import Foundation
import Combine
import SwiftUI

/// ViewModel for the session list view, managing session data and actions.
@MainActor
final class SessionListViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// List of all recording sessions
    @Published private(set) var sessions: [RecordingSession] = []
    
    /// Whether data is currently being loaded
    @Published private(set) var isLoading: Bool = false
    
    /// Current error message to display
    @Published var errorMessage: String?
    
    /// Whether an error alert should be shown
    @Published var showError: Bool = false
    
    // MARK: - Computed Properties
    
    /// Total number of sessions
    var sessionCount: Int {
        sessions.count
    }
    
    /// Whether there are any sessions
    var hasSessions: Bool {
        !sessions.isEmpty
    }
    
    // MARK: - Private Properties
    
    private let coreDataStore: CoreDataStoreProtocol
    private let fileStorage: FileStorageProtocol
    
    // MARK: - Initialization
    
    /// Initialize the view model with dependencies
    /// - Parameters:
    ///   - coreDataStore: The Core Data store for session persistence
    ///   - fileStorage: The file storage for audio clips
    init(
        coreDataStore: CoreDataStoreProtocol = CoreDataStore.shared,
        fileStorage: FileStorageProtocol = FileStorage.shared
    ) {
        self.coreDataStore = coreDataStore
        self.fileStorage = fileStorage
    }
    
    // MARK: - Public Methods
    
    /// Fetch all recording sessions from storage
    func fetchSessions() {
        isLoading = true
        
        Task {
            do {
                let fetchedSessions = try await coreDataStore.fetchAllSessions()
                sessions = fetchedSessions
                isLoading = false
            } catch {
                handleError(error)
                isLoading = false
            }
        }
    }
    
    /// Delete a session and all associated data
    /// - Parameter session: The session to delete
    func deleteSession(_ session: RecordingSession) {
        Task {
            do {
                // Delete associated audio files
                for fileURL in session.fileURLs {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                
                // Delete events and their audio clips for this session
                let events = try await coreDataStore.fetchEvents(for: session.id)
                for event in events {
                    if let clipURL = event.audioClipURL {
                        try? await fileStorage.deleteAudioClip(at: clipURL)
                    }
                    try await coreDataStore.deleteEvent(event)
                }
                
                // Delete the session from Core Data
                try await coreDataStore.deleteSession(session)
                
                // Update local list
                sessions.removeAll { $0.id == session.id }
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Delete sessions at the specified index set
    /// - Parameter offsets: The index set of sessions to delete
    func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            deleteSession(session)
        }
    }
    
    /// Format a session's duration for display
    /// - Parameter session: The session to format
    /// - Returns: Formatted duration string
    func formattedDuration(for session: RecordingSession) -> String {
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
    
    /// Format a session's date for display
    /// - Parameter session: The session to format
    /// - Returns: Formatted date string
    func formattedDate(for session: RecordingSession) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.startTime)
    }
    
    // MARK: - Private Methods
    
    /// Handle errors from operations
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
