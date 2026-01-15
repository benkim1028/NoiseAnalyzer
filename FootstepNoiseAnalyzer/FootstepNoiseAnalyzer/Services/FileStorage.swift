//
//  FileStorage.swift
//  FootstepNoiseAnalyzer
//
//  Manages file storage for audio clips associated with footstep events.
//  Requirements: 5.2
//

import Foundation

/// Errors that can occur during file storage operations
enum FileStorageError: Error, LocalizedError {
    case directoryCreationFailed(underlying: Error)
    case saveFailed(underlying: Error)
    case loadFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case fileNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create storage directory: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save audio clip: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load audio clip: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete audio clip: \(error.localizedDescription)"
        case .fileNotFound:
            return "Audio clip file not found"
        case .invalidData:
            return "Invalid audio data"
        }
    }
}

/// Protocol defining file storage operations for audio clips
protocol FileStorageProtocol {
    /// Saves an audio clip and returns the URL where it was saved
    func saveAudioClip(_ data: Data, eventId: UUID) async throws -> URL
    
    /// Loads an audio clip from the given URL
    func loadAudioClip(from url: URL) async throws -> Data
    
    /// Deletes an audio clip at the given URL
    func deleteAudioClip(at url: URL) async throws
    
    /// Deletes all audio clips for a session
    func deleteAudioClips(for sessionId: UUID) async throws
    
    /// Returns the total storage used by audio clips in bytes
    func calculateStorageUsed() async throws -> Int64
}

/// File storage implementation for managing audio clips on disk
class FileStorage: FileStorageProtocol {
    
    /// Shared instance for app-wide use
    static let shared = FileStorage()
    
    /// The file manager instance
    private let fileManager: FileManager
    
    /// The base directory for storing audio clips
    private let audioClipsDirectory: URL
    
    /// Initializes the file storage
    /// - Parameter customDirectory: Optional custom directory for testing
    init(customDirectory: URL? = nil) {
        self.fileManager = FileManager.default
        
        if let customDir = customDirectory {
            self.audioClipsDirectory = customDir
        } else {
            // Use the app's documents directory
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.audioClipsDirectory = documentsDirectory.appendingPathComponent("AudioClips", isDirectory: true)
        }
        
        // Create the directory if it doesn't exist
        createDirectoryIfNeeded()
    }
    
    /// Creates the audio clips directory if it doesn't exist
    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: audioClipsDirectory.path) {
            try? fileManager.createDirectory(at: audioClipsDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - FileStorageProtocol Implementation
    
    /// Saves an audio clip and returns the URL where it was saved
    /// - Parameters:
    ///   - data: The audio data to save
    ///   - eventId: The ID of the event this clip belongs to
    /// - Returns: The URL where the clip was saved
    func saveAudioClip(_ data: Data, eventId: UUID) async throws -> URL {
        guard !data.isEmpty else {
            throw FileStorageError.invalidData
        }
        
        // Create a unique filename using the event ID
        let filename = "\(eventId.uuidString).m4a"
        let fileURL = audioClipsDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw FileStorageError.saveFailed(underlying: error)
        }
    }
    
    /// Loads an audio clip from the given URL
    /// - Parameter url: The URL of the audio clip
    /// - Returns: The audio data
    func loadAudioClip(from url: URL) async throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileStorageError.fileNotFound
        }
        
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileStorageError.loadFailed(underlying: error)
        }
    }
    
    /// Deletes an audio clip at the given URL
    /// - Parameter url: The URL of the audio clip to delete
    func deleteAudioClip(at url: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else {
            // File doesn't exist, nothing to delete
            return
        }
        
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileStorageError.deleteFailed(underlying: error)
        }
    }
    
    /// Deletes all audio clips for a session
    /// - Parameter sessionId: The session ID
    func deleteAudioClips(for sessionId: UUID) async throws {
        // Get all files in the audio clips directory
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: audioClipsDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw FileStorageError.deleteFailed(underlying: error)
        }
        
        // Delete files that match the session pattern
        // Note: In a real implementation, we'd need to track which clips belong to which session
        // For now, this method is provided for future use when session-clip mapping is implemented
        for fileURL in contents {
            if fileURL.lastPathComponent.hasPrefix(sessionId.uuidString) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    /// Returns the total storage used by audio clips in bytes
    /// - Returns: Total bytes used
    func calculateStorageUsed() async throws -> Int64 {
        var totalSize: Int64 = 0
        
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: audioClipsDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
        } catch {
            return 0
        }
        
        for fileURL in contents {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// Returns the URL for an audio clip given an event ID
    /// - Parameter eventId: The event ID
    /// - Returns: The URL where the clip would be stored
    func audioClipURL(for eventId: UUID) -> URL {
        let filename = "\(eventId.uuidString).m4a"
        return audioClipsDirectory.appendingPathComponent(filename)
    }
    
    /// Checks if an audio clip exists for the given event ID
    /// - Parameter eventId: The event ID
    /// - Returns: True if the clip exists
    func audioClipExists(for eventId: UUID) -> Bool {
        let url = audioClipURL(for: eventId)
        return fileManager.fileExists(atPath: url.path)
    }
}
