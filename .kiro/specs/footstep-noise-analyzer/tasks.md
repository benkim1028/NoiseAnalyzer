# Implementation Plan: Footstep Noise Analyzer

## Overview

This plan implements an iOS app for recording ambient audio and detecting/classifying footstep sounds using AVFoundation, Core ML, and Core Data. Tasks are ordered to build foundational components first, then layer on analysis, persistence, and UI.

## Tasks

- [x] 1. Set up Xcode project and dependencies
  - Create new iOS app project with SwiftUI
  - Add SwiftCheck via Swift Package Manager for property-based testing
  - Configure Info.plist for microphone permission and background audio
  - Set up project folder structure (Models, Services, Views, ViewModels)
  - _Requirements: 1.5, 2.1, 2.2_

- [x] 2. Implement core data models
  - [x] 2.1 Create FootstepType and IntensityLevel enums
    - Define FootstepType: stomping, heelStrike, shuffling, running, unknown
    - Define IntensityLevel: low, medium, high
    - Implement Codable conformance
    - _Requirements: 4.1, 4.4_

  - [x] 2.2 Create FootstepClassification struct
    - Properties: type, confidence, intensity
    - Implement Codable and Equatable conformance
    - _Requirements: 4.1, 4.2, 4.4_

  - [x] 2.3 Create RecordingSession struct
    - Properties: id, startTime, endTime, eventCount, fileURLs, status
    - Implement computed duration property
    - Define SessionStatus enum
    - _Requirements: 7.1_

  - [x] 2.4 Create FootstepEvent struct
    - Properties: id, sessionId, timestamp, classification, audioClipURL, notes
    - Implement withoutAudioClip() method
    - _Requirements: 5.1_

  - [ ] 2.5 Write property test for serialization round-trip
    - **Property 1: Serialization Round-Trip**
    - **Validates: Requirements 9.2, 9.3, 9.5**

- [x] 3. Implement JSON serialization
  - [x] 3.1 Create SessionExport struct and JSONSerializer class
    - Configure encoder with ISO8601 dates and pretty printing
    - Implement serialize and deserialize methods
    - _Requirements: 9.2, 9.3, 9.4_

- [x] 4. Checkpoint - Verify models and serialization
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement audio recording layer
  - [x] 5.1 Create AudioRecorderProtocol and AudioRecorder class
    - Implement AVAudioSession configuration for background recording
    - Implement AVAudioEngine setup with input tap
    - Implement startRecording, stopRecording, pause, resume
    - Publish audio level updates via Combine
    - _Requirements: 1.1, 1.2, 1.3, 2.1_

  - [x] 5.2 Implement error handling for audio recording
    - Create AudioRecorderError enum with localized descriptions
    - Handle permission denied, configuration failures, recording failures
    - _Requirements: 1.5_

  - [x] 5.3 Write property test for recording state consistency
    - **Property 11: Recording State Consistency**
    - **Validates: Requirements 1.1, 1.2**

- [x] 6. Implement noise analysis layer
  - [x] 6.1 Create NoiseAnalyzerProtocol and NoiseAnalyzer class
    - Implement RMS calculation from audio buffer
    - Implement peak detection algorithm
    - Implement threshold-based event detection with minimum interval
    - Publish detected AudioEvents via Combine
    - _Requirements: 3.1, 3.2, 3.4_

  - [x] 6.2 Implement decibel calculation utility
    - Convert RMS to decibel scale
    - Handle edge cases (zero amplitude, very small values)
    - _Requirements: 8.4_

  - [ ]* 6.3 Write property test for detection event validity
    - **Property 10: Detection Event Validity**
    - **Validates: Requirements 3.1, 3.2**

  - [ ]* 6.4 Write property test for decibel calculation validity
    - **Property 14: Decibel Calculation Validity**
    - **Validates: Requirements 8.4**

- [x] 7. Implement noise classification layer
  - [x] 7.1 Create NoiseClassifierProtocol and NoiseClassifier class
    - Load Core ML model with SoundAnalysis framework
    - Implement async classification of audio buffers
    - Map model output to FootstepType and IntensityLevel
    - Apply low-confidence threshold (< 0.5 → unknown)
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 7.2 Create placeholder/mock Core ML model
    - Create FootstepClassifierModel.mlmodel placeholder
    - Implement mock classifier for testing without real model
    - _Requirements: 4.1_

  - [ ]* 7.3 Write property test for classification output validity
    - **Property 2: Classification Output Validity**
    - **Validates: Requirements 4.1, 4.2, 4.4**

  - [ ]* 7.4 Write property test for low confidence classification
    - **Property 3: Low Confidence Classification**
    - **Validates: Requirements 4.3**

- [x] 8. Checkpoint - Verify audio pipeline
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Implement Core Data persistence
  - [x] 9.1 Create Core Data model file (.xcdatamodeld)
    - Define RecordingSessionEntity with attributes
    - Define FootstepEventEntity with attributes
    - Set up relationship between session and events
    - _Requirements: 9.1_

  - [x] 9.2 Create CoreDataStore class
    - Implement persistent container setup
    - Implement save, fetch, delete operations for sessions
    - Implement save, fetch, delete operations for events
    - Implement date range filtering for events
    - _Requirements: 5.1, 5.3, 7.1, 7.3_

  - [x] 9.3 Create FileStorage class for audio clips
    - Implement saveAudioClip method
    - Implement loadAudioClip method
    - Implement deleteAudioClip method
    - _Requirements: 5.2_

- [-] 10. Implement EventService
  - [x] 10.1 Create EventServiceProtocol and EventService class
    - Implement save event with audio clip storage
    - Implement fetch events by session ID
    - Implement fetch events by date range
    - Implement delete event
    - Implement addNote method
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [ ]* 10.2 Write property test for event persistence completeness
    - **Property 4: Event Persistence Completeness**
    - **Validates: Requirements 5.1, 5.2**

  - [ ]* 10.3 Write property test for event chronological ordering
    - **Property 5: Event Chronological Ordering**
    - **Validates: Requirements 5.3**

  - [ ]* 10.4 Write property test for note persistence
    - **Property 6: Note Persistence**
    - **Validates: Requirements 5.4**

  - [ ]* 10.5 Write property test for session event isolation
    - **Property 8: Session Event Isolation**
    - **Validates: Requirements 7.2**

  - [ ]* 10.6 Write property test for deletion completeness
    - **Property 9: Deletion Completeness**
    - **Validates: Requirements 7.3**

- [x] 11. Checkpoint - Verify persistence layer
  - Ensure all tests pass, ask the user if questions arise.

- [x] 12. Implement domain services
  - [x] 12.1 Create AnalysisService
    - Coordinate NoiseAnalyzer and NoiseClassifier
    - Subscribe to detection events and classify
    - Publish FootstepEvents via Combine
    - _Requirements: 3.1, 4.1_

  - [x] 12.2 Create RecordingService
    - Coordinate AudioRecorder and AnalysisService
    - Manage recording session lifecycle
    - Save events to EventService during recording
    - _Requirements: 1.1, 1.2, 3.1_

  - [ ]* 12.3 Write property test for event count accuracy
    - **Property 13: Event Count Accuracy**
    - **Validates: Requirements 8.3**

- [x] 13. Implement ReportGenerator
  - [x] 13.1 Create ReportGeneratorProtocol and ReportGenerator class
    - Implement generateReport with statistics calculation
    - Calculate eventsByType distribution
    - Calculate eventsByHour distribution
    - Identify peak activity times
    - _Requirements: 6.1_

  - [x] 13.2 Implement PDF export
    - Create PDF document with report data
    - Include statistics and event list
    - _Requirements: 6.3_

  - [ ]* 13.3 Write property test for report statistics accuracy
    - **Property 7: Report Statistics Accuracy**
    - **Validates: Requirements 6.1**

- [x] 14. Checkpoint - Verify services
  - Ensure all tests pass, ask the user if questions arise.

- [x] 15. Implement ViewModels
  - [x] 15.1 Create RecordingViewModel
    - Expose recording state, duration, audio level
    - Expose real-time event count and last detected event
    - Implement start/stop/pause/resume actions
    - _Requirements: 1.1, 1.2, 1.3, 8.1, 8.2, 8.3_

  - [x] 15.2 Create SessionListViewModel
    - Fetch and expose list of recording sessions
    - Implement delete session action
    - _Requirements: 7.1, 7.3_

  - [x] 15.3 Create SessionDetailViewModel
    - Fetch and expose events for selected session
    - Implement add note action
    - Implement delete event action
    - _Requirements: 5.3, 5.4, 7.2_

  - [x] 15.4 Create ReportViewModel
    - Expose date range selection
    - Generate and expose report data
    - Implement PDF export action
    - _Requirements: 6.1, 6.3_

- [x] 16. Implement SwiftUI Views
  - [x] 16.1 Create RecordingView
    - Display record/stop/pause buttons
    - Display audio waveform visualization
    - Display real-time event indicators
    - Display current decibel level
    - _Requirements: 1.1, 1.2, 1.3, 8.1, 8.2, 8.4_

  - [x] 16.2 Create SessionListView
    - Display list of sessions with date, duration, event count
    - Implement swipe-to-delete
    - Navigate to session detail
    - _Requirements: 7.1, 7.3_

  - [x] 16.3 Create SessionDetailView
    - Display event timeline for session
    - Display event classification and intensity
    - Allow playback of audio clips
    - Allow adding notes to events
    - _Requirements: 5.3, 5.4, 7.2_

  - [x] 16.4 Create ReportView
    - Display date range picker
    - Display statistics summary
    - Display charts for events by type and hour
    - Implement PDF export button
    - _Requirements: 6.1, 6.2, 6.3_

  - [x] 16.5 Create main navigation and app entry point
    - Set up TabView with Recording, Sessions, Reports tabs
    - Configure app delegate for background audio
    - _Requirements: 2.1, 2.2_

- [ ] 17. Final checkpoint - Full integration
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- SwiftCheck is used for property-based testing
- A placeholder ML model is created initially; replace with trained model later
- Background audio requires proper Info.plist configuration and audio session setup
