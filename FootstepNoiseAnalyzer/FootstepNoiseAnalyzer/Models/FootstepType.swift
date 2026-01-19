//
//  FootstepType.swift
//  FootstepNoiseAnalyzer
//
//  Defines the types of footstep sounds that can be detected and classified.
//

import Foundation

/// Represents the different types of footstep sounds that can be classified.
/// Classification is based on low-frequency detection and decibel levels.
/// Base thresholds (at sensitivity 0): Mild 40-45 dB, Medium 45-50 dB, Hard 50-55 dB, Extreme 55+ dB
enum FootstepType: String, Codable, CaseIterable, Equatable {
    /// Low frequency, 40-45 dB - gentle footsteps
    case mildStomping = "mild_stomping"
    
    /// Low frequency, 45-50 dB - normal walking
    case mediumStomping = "medium_stomping"
    
    /// Low frequency, 50-55 dB - heavy footsteps
    case hardStomping = "hard_stomping"
    
    /// Low frequency, 55+ dB - very heavy footsteps
    case extremeStomping = "extreme_stomping"
    
    /// Any stomping type with very short intervals between steps
    case running
    
    /// Sound detected but doesn't match footstep criteria (not low frequency)
    case unknown
    
    var displayName: String {
        switch self {
        case .mildStomping: return "Mild Stomping"
        case .mediumStomping: return "Medium Stomping"
        case .hardStomping: return "Hard Stomping"
        case .extremeStomping: return "Extreme Stomping"
        case .running: return "Running"
        case .unknown: return "Unknown"
        }
    }
}
