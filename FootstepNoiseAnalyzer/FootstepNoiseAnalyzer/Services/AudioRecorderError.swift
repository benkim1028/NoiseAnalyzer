//
//  AudioRecorderError.swift
//  FootstepNoiseAnalyzer
//
//  Error types for audio recording operations.
//  Requirements: 1.5
//

import Foundation

/// Errors that can occur during audio recording operations.
enum AudioRecorderError: Error, LocalizedError {
    /// Microphone permission was denied by the user
    case microphonePermissionDenied
    
    /// Failed to configure the audio session
    case audioSessionConfigurationFailed(underlying: Error)
    
    /// Recording operation failed
    case recordingFailed(underlying: Error)
    
    /// Failed to write audio file to disk
    case fileWriteFailed(underlying: Error)
    
    /// Audio engine failed to start
    case audioEngineStartFailed(underlying: Error)
    
    /// No recording is currently in progress
    case noActiveRecording
    
    /// Recording is already in progress
    case recordingAlreadyInProgress
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required. Please enable it in Settings > Privacy > Microphone."
        case .audioSessionConfigurationFailed(let error):
            return "Failed to configure audio: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to save recording: \(error.localizedDescription)"
        case .audioEngineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noActiveRecording:
            return "No recording is currently in progress."
        case .recordingAlreadyInProgress:
            return "A recording is already in progress."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Open Settings and enable microphone access for this app."
        case .audioSessionConfigurationFailed:
            return "Try closing other audio apps and restart this app."
        case .recordingFailed:
            return "Please try starting a new recording."
        case .fileWriteFailed:
            return "Check available storage space and try again."
        case .audioEngineStartFailed:
            return "Try restarting the app."
        case .noActiveRecording:
            return "Start a new recording first."
        case .recordingAlreadyInProgress:
            return "Stop the current recording before starting a new one."
        }
    }
}
