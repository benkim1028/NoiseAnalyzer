//
//  JSONSerializer.swift
//  FootstepNoiseAnalyzer
//
//  Handles JSON serialization and deserialization for session exports.
//

import Foundation

/// Represents an exported session with all associated events and metadata.
/// - Requirements: 9.2, 9.3, 9.4
struct SessionExport: Codable, Equatable {
    /// The recording session being exported
    let session: RecordingSession
    
    /// All footstep events associated with this session
    let events: [FootstepEvent]
    
    /// When this export was created
    let exportedAt: Date
    
    /// Version of the app that created this export
    let appVersion: String
}

/// Handles JSON serialization and deserialization for session data.
/// - Requirements: 9.2, 9.3, 9.4
class JSONSerializer {
    
    // MARK: - Properties
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public Methods
    
    /// Serializes a recording session and its events to JSON data.
    /// - Parameters:
    ///   - session: The recording session to serialize
    ///   - events: The footstep events associated with the session
    /// - Returns: JSON data representing the session export
    /// - Throws: EncodingError if serialization fails
    func serialize(_ session: RecordingSession, events: [FootstepEvent]) throws -> Data {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let export = SessionExport(
            session: session,
            events: events,
            exportedAt: Date(),
            appVersion: appVersion
        )
        return try encoder.encode(export)
    }
    
    /// Deserializes JSON data back into a SessionExport object.
    /// - Parameter data: The JSON data to deserialize
    /// - Returns: The deserialized SessionExport object
    /// - Throws: DecodingError if deserialization fails
    func deserialize(_ data: Data) throws -> SessionExport {
        return try decoder.decode(SessionExport.self, from: data)
    }
    
    /// Serializes a recording session and its events to a JSON string.
    /// - Parameters:
    ///   - session: The recording session to serialize
    ///   - events: The footstep events associated with the session
    /// - Returns: A pretty-printed JSON string
    /// - Throws: EncodingError if serialization fails
    func serializeToString(_ session: RecordingSession, events: [FootstepEvent]) throws -> String {
        let data = try serialize(session, events: events)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw SerializationError.stringEncodingFailed
        }
        return jsonString
    }
    
    /// Deserializes a JSON string back into a SessionExport object.
    /// - Parameter jsonString: The JSON string to deserialize
    /// - Returns: The deserialized SessionExport object
    /// - Throws: DecodingError if deserialization fails
    func deserialize(from jsonString: String) throws -> SessionExport {
        guard let data = jsonString.data(using: .utf8) else {
            throw SerializationError.stringDecodingFailed
        }
        return try deserialize(data)
    }
}

// MARK: - Errors

/// Errors that can occur during JSON serialization/deserialization.
enum SerializationError: Error, LocalizedError {
    case stringEncodingFailed
    case stringDecodingFailed
    
    var errorDescription: String? {
        switch self {
        case .stringEncodingFailed:
            return "Failed to encode JSON data to string"
        case .stringDecodingFailed:
            return "Failed to decode string to JSON data"
        }
    }
}
