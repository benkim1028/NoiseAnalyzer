//
//  FootstepType.swift
//  FootstepNoiseAnalyzer
//
//  Defines the types of footstep sounds that can be detected and classified.
//

import Foundation

/// Represents the different types of footstep sounds that can be classified.
/// Classification is based on low-frequency detection and decibel levels.
enum FootstepType: String, Codable, CaseIterable, Equatable {
    /// Low frequency, low decibel - gentle footsteps
    case mildStomping = "mild_stomping"
    
    /// Low frequency, medium decibel - normal walking
    case mediumStomping = "medium_stomping"
    
    /// Low frequency, high decibel - heavy footsteps
    case hardStomping = "hard_stomping"
    
    /// Any stomping type with very short intervals between steps
    case running
    
    /// Sound detected but doesn't match footstep criteria (not low frequency)
    case unknown
    
    var displayName: String {
        switch self {
        case .mildStomping: return "Mild Stomping"
        case .mediumStomping: return "Medium Stomping"
        case .hardStomping: return "Hard Stomping"
        case .running: return "Running"
        case .unknown: return "Unknown"
        }
    }
}
