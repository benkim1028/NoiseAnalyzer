//
//  RecordingSession.swift
//  FootstepNoiseAnalyzer
//
//  Represents a continuous period of audio capture with associated analysis results.
//

import Foundation

/// Represents the status of a recording session.
enum SessionStatus: String, Codable, Equatable {
    case recording
    case paused
    case completed
}

/// Represents a recording session with metadata and associated events.
/// - Requirements: 7.1
struct RecordingSession: Identifiable, Codable, Equatable {
    /// Unique identifier for the session
    let id: UUID
    
    /// When the recording started
    let startTime: Date
    
    /// When the recording ended (nil if still in progress)
    var endTime: Date?
    
    /// Number of footstep events detected in this session
    var eventCount: Int
    
    /// URLs to the audio files for this session
    var fileURLs: [URL]
    
    /// Current status of the session
    var status: SessionStatus
    
    /// Computed duration of the session in seconds
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
}
