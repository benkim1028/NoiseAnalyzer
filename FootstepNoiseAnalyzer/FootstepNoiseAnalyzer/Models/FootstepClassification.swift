//
//  FootstepClassification.swift
//  FootstepNoiseAnalyzer
//
//  Represents the classification result for a detected footstep sound.
//

import Foundation

/// Contains the classification details for a detected footstep event.
struct FootstepClassification: Codable, Equatable {
    /// The type of footstep detected
    let type: FootstepType
    
    /// Confidence score for the classification (0.0 to 1.0)
    let confidence: Float
    
    /// The measured decibel level
    let decibelLevel: Float
    
    /// The dominant frequency in Hz
    let dominantFrequency: Float
    
    /// Time interval since the previous footstep (nil if first detection)
    let intervalFromPrevious: TimeInterval?
}
