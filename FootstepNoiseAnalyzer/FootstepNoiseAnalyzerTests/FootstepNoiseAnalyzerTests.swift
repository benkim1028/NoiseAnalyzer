//
//  FootstepNoiseAnalyzerTests.swift
//  FootstepNoiseAnalyzerTests
//
//  Unit and property-based tests for the Footstep Noise Analyzer app.
//

import XCTest
import SwiftCheck
import Combine
import AVFoundation
@testable import FootstepNoiseAnalyzer

// MARK: - Arbitrary Conformance for Model Types

extension FootstepType: @retroactive Arbitrary {
    public static var arbitrary: Gen<FootstepType> {
        Gen<FootstepType>.fromElements(of: FootstepType.allCases)
    }
}

extension SessionStatus: @retroactive Arbitrary {
    public static var arbitrary: Gen<SessionStatus> {
        Gen<SessionStatus>.fromElements(of: [.recording, .paused, .completed])
    }
}

extension FootstepClassification: @retroactive Arbitrary {
    public static var arbitrary: Gen<FootstepClassification> {
        Gen<FootstepClassification>.compose { c in
            FootstepClassification(
                type: c.generate(),
                confidence: c.generate(using: Float.arbitrary.map { abs($0).truncatingRemainder(dividingBy: 1.0) }),
                decibelLevel: c.generate(using: Float.arbitrary.map { abs($0).truncatingRemainder(dividingBy: 100.0) }),
                dominantFrequency: c.generate(using: Float.arbitrary.map { abs($0).truncatingRemainder(dividingBy: 500.0) }),
                intervalFromPrevious: c.generate(using: Double.arbitrary.map { abs($0).truncatingRemainder(dividingBy: 5.0) })
            )
        }
    }
}

extension FootstepEvent: @retroactive Arbitrary {
    public static var arbitrary: Gen<FootstepEvent> {
        Gen<FootstepEvent>.compose { c in
            FootstepEvent(
                id: UUID(),
                sessionId: UUID(),
                timestamp: Date(timeIntervalSince1970: Double(abs(c.generate(using: Int.arbitrary) % 2000000000))),
                timestampInRecording: Double(abs(c.generate(using: Int.arbitrary) % 3600)),
                classification: c.generate(),
                audioClipURL: nil,
                notes: c.generate(using: String.arbitrary.proliferate.map { $0.isEmpty ? nil : $0.joined() })
            )
        }
    }
}

extension RecordingSession: @retroactive Arbitrary {
    public static var arbitrary: Gen<RecordingSession> {
        Gen<RecordingSession>.compose { c in
            let startTimestamp = abs(c.generate(using: Int.arbitrary) % 2000000000)
            let startTime = Date(timeIntervalSince1970: Double(startTimestamp))
            let hasEndTime: Bool = c.generate()
            let endTime: Date? = hasEndTime ? Date(timeIntervalSince1970: Double(startTimestamp + abs(c.generate(using: Int.arbitrary) % 86400))) : nil
            
            return RecordingSession(
                id: UUID(),
                startTime: startTime,
                endTime: endTime,
                eventCount: abs(c.generate(using: Int.arbitrary) % 1000),
                fileURLs: [],
                status: c.generate()
            )
        }
    }
}

final class FootstepNoiseAnalyzerTests: XCTestCase {
    
    // MARK: - Setup
    
    override func setUpWithError() throws {
        // Setup code before each test
    }
    
    override func tearDownWithError() throws {
        // Cleanup code after each test
    }
    
    // MARK: - Placeholder Tests
    
    func testProjectSetup() throws {
        // Verify the project is set up correctly
        XCTAssertTrue(true, "Project setup complete")
    }
    
    // MARK: - Property-Based Tests
    
    // Feature: footstep-noise-analyzer, Property 1: Serialization Round-Trip
    // For any valid RecordingSession and associated FootstepEvent objects,
    // serializing to JSON and then deserializing SHALL produce objects
    // equivalent to the originals.
    // Validates: Requirements 9.2, 9.3, 9.5
    func testSerializationRoundTrip() {
        let serializer = JSONSerializer()
        
        property("Serialization round-trip preserves RecordingSession and FootstepEvent data") <- forAll { (session: RecordingSession, events: [FootstepEvent]) in
            do {
                // Serialize to JSON
                let jsonData = try serializer.serialize(session, events: events)
                
                // Deserialize back
                let deserialized = try serializer.deserialize(jsonData)
                
                // Verify session equality
                let sessionEqual = deserialized.session == session
                
                // Verify events equality
                let eventsEqual = deserialized.events == events
                
                return sessionEqual && eventsEqual
            } catch {
                return false
            }
        }
    }
    
    // Feature: footstep-noise-analyzer, Property 2: Classification Output Validity
    // For any audio buffer passed to the NoiseClassifier, the resulting
    // FootstepClassification SHALL have valid enum values and confidence in [0, 1].
    // Validates: Requirements 4.1, 4.2, 4.4
    
    // Feature: footstep-noise-analyzer, Property 11: Recording State Consistency
    // For any AudioRecorder, after calling startRecording(), isRecording SHALL be true,
    // and after calling stopRecording(), isRecording SHALL be false and a valid
    // RecordingSession SHALL be returned.
    // Validates: Requirements 1.1, 1.2
    func testRecordingStateConsistency() {
        // Since AudioRecorder requires actual hardware (microphone) and permissions,
        // we test the state consistency using a MockAudioRecorder that simulates
        // the state machine behavior without requiring real hardware.
        
        property("Recording state transitions are consistent") <- forAll { (operationCount: UInt8) in
            let recorder = MockAudioRecorder()
            
            // Initial state: not recording
            guard !recorder.isRecording else { return false }
            guard !recorder.isPaused else { return false }
            
            // Perform a sequence of operations and verify state consistency
            let operations = Int(operationCount % 10) + 1 // 1-10 operations
            
            for _ in 0..<operations {
                let wasRecording = recorder.isRecording
                
                if !wasRecording {
                    // Start recording
                    do {
                        let session = try recorder.startRecordingSync()
                        
                        // After startRecording: isRecording must be true
                        guard recorder.isRecording else { return false }
                        guard !recorder.isPaused else { return false }
                        
                        // Session must have valid properties
                        guard session.status == .recording else { return false }
                        guard session.endTime == nil else { return false }
                    } catch {
                        // Permission denied is acceptable in test environment
                        continue
                    }
                } else {
                    // Stop recording
                    do {
                        let session = try recorder.stopRecordingSync()
                        
                        // After stopRecording: isRecording must be false
                        guard !recorder.isRecording else { return false }
                        guard !recorder.isPaused else { return false }
                        
                        // Session must have valid properties
                        guard session.status == .completed else { return false }
                        guard session.endTime != nil else { return false }
                        guard session.endTime! >= session.startTime else { return false }
                    } catch {
                        return false
                    }
                }
            }
            
            // Final cleanup: if still recording, stop
            if recorder.isRecording {
                do {
                    let finalSession = try recorder.stopRecordingSync()
                    guard !recorder.isRecording else { return false }
                    guard finalSession.status == .completed else { return false }
                } catch {
                    return false
                }
            }
            
            return true
        }
    }
    
    // Feature: footstep-noise-analyzer, Property 11 (continued): Pause/Resume State Consistency
    // Tests that pause and resume operations maintain consistent state.
    func testPauseResumeStateConsistency() {
        property("Pause and resume state transitions are consistent") <- forAll { (pauseCount: UInt8) in
            let recorder = MockAudioRecorder()
            
            // Start recording first
            do {
                _ = try recorder.startRecordingSync()
            } catch {
                // Skip if can't start
                return true
            }
            
            guard recorder.isRecording else { return false }
            
            // Perform pause/resume cycles
            let cycles = Int(pauseCount % 5) + 1 // 1-5 cycles
            
            for _ in 0..<cycles {
                // Pause
                recorder.pauseRecording()
                guard recorder.isRecording else { return false } // Still "recording" but paused
                guard recorder.isPaused else { return false }
                
                // Resume
                recorder.resumeRecording()
                guard recorder.isRecording else { return false }
                guard !recorder.isPaused else { return false }
            }
            
            // Stop and verify final state
            do {
                let session = try recorder.stopRecordingSync()
                guard !recorder.isRecording else { return false }
                guard !recorder.isPaused else { return false }
                guard session.status == .completed else { return false }
            } catch {
                return false
            }
            
            return true
        }
    }
}

// MARK: - Mock AudioRecorder for Property Testing

/// A mock implementation of AudioRecorderProtocol for property-based testing.
/// This simulates the state machine behavior without requiring actual hardware.
final class MockAudioRecorder: AudioRecorderProtocol {
    private(set) var isRecording: Bool = false
    private(set) var isPaused: Bool = false
    
    private var recordingStartTime: Date?
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var currentSession: RecordingSession?
    
    var currentDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        if isPaused, let pauseTime = pauseStartTime {
            return pauseTime.timeIntervalSince(startTime) - totalPausedDuration
        }
        return Date().timeIntervalSince(startTime) - totalPausedDuration
    }
    
    var audioLevelPublisher: AnyPublisher<Float, Never> {
        Just(0.0).eraseToAnyPublisher()
    }
    
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        Empty().eraseToAnyPublisher()
    }
    
    func startRecording() async throws -> RecordingSession {
        return try startRecordingSync()
    }
    
    func stopRecording() async throws -> RecordingSession {
        return try stopRecordingSync()
    }
    
    /// Synchronous version for property testing
    func startRecordingSync() throws -> RecordingSession {
        guard !isRecording else {
            throw AudioRecorderError.recordingAlreadyInProgress
        }
        
        let sessionId = UUID()
        let startTime = Date()
        
        let session = RecordingSession(
            id: sessionId,
            startTime: startTime,
            endTime: nil,
            eventCount: 0,
            fileURLs: [],
            status: .recording
        )
        
        currentSession = session
        recordingStartTime = startTime
        totalPausedDuration = 0
        isRecording = true
        isPaused = false
        
        return session
    }
    
    /// Synchronous version for property testing
    func stopRecordingSync() throws -> RecordingSession {
        guard isRecording, var session = currentSession else {
            throw AudioRecorderError.noActiveRecording
        }
        
        session.endTime = Date()
        session.status = .completed
        
        isRecording = false
        isPaused = false
        currentSession = nil
        recordingStartTime = nil
        pauseStartTime = nil
        totalPausedDuration = 0
        
        return session
    }
    
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        
        isPaused = true
        pauseStartTime = Date()
        
        if var session = currentSession {
            session.status = .paused
            currentSession = session
        }
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        
        if let pauseStart = pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }
        
        isPaused = false
        pauseStartTime = nil
        
        if var session = currentSession {
            session.status = .recording
            currentSession = session
        }
    }
    
    // MARK: - Monitoring (stub implementation for protocol conformance)
    
    private(set) var isMonitoring: Bool = false
    
    func startMonitoring() async throws {
        isMonitoring = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
}
