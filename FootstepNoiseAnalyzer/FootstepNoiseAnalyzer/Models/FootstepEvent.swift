//
//  FootstepEvent.swift
//  FootstepNoiseAnalyzer
//
//  Represents a detected footstep event with classification and metadata.
//

import Foundation

/// Represents a single detected footstep event with all associated metadata.
/// - Requirements: 5.1
struct FootstepEvent: Identifiable, Codable, Equatable {
    /// Unique identifier for the event
    let id: UUID
    
    /// ID of the recording session this event belongs to
    let sessionId: UUID
    
    /// When the footstep was detected
    let timestamp: Date
    
    /// Time offset in seconds from the start of the recording when this event occurred
    let timestampInRecording: TimeInterval
    
    /// Classification details for this footstep
    let classification: FootstepClassification
    
    /// URL to the audio clip for this event (optional)
    var audioClipURL: URL?
    
    /// User-added notes or annotations for this event
    var notes: String?
    
    /// Returns a copy of this event without the audio clip URL.
    /// Useful for reports where audio clips are not included.
    func withoutAudioClip() -> FootstepEvent {
        var copy = self
        copy.audioClipURL = nil
        return copy
    }
}
