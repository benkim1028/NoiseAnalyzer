# Requirements Document

## Introduction

An iOS application that records ambient sound and analyzes it to detect and classify footstep-related noises (stomping, heel strikes, shuffling, etc.) from upstairs neighbors. The app provides detailed reports and evidence logs to help users document noise disturbances for building a case.

## Glossary

- **Audio_Recorder**: The component responsible for capturing audio from the device microphone
- **Noise_Analyzer**: The component that processes audio data to detect and classify footstep sounds
- **Footstep_Event**: A detected instance of footstep-related noise with classification and metadata
- **Recording_Session**: A continuous period of audio capture with associated analysis results
- **Evidence_Report**: A generated document summarizing detected noise events over a time period
- **Noise_Classifier**: The ML model or algorithm that categorizes detected sounds into footstep types

## Requirements

### Requirement 1: Audio Recording

**User Story:** As a user, I want to record ambient sound from my environment, so that I can capture footstep noises from upstairs.

#### Acceptance Criteria

1. WHEN the user taps the record button, THE Audio_Recorder SHALL begin capturing audio from the device microphone
2. WHEN the user taps the stop button, THE Audio_Recorder SHALL stop capturing and save the recording
3. WHILE recording is active, THE Audio_Recorder SHALL display a visual indicator showing recording status and duration
4. WHEN a recording exceeds 4 hours, THE Audio_Recorder SHALL automatically split into separate files to manage storage
5. IF microphone permission is denied, THEN THE Audio_Recorder SHALL display a clear message explaining how to enable permissions

### Requirement 2: Background Recording

**User Story:** As a user, I want the app to continue recording when in the background, so that I can capture noise while using other apps or when the phone is locked.

#### Acceptance Criteria

1. WHEN the app enters the background, THE Audio_Recorder SHALL continue capturing audio
2. WHILE recording in background mode, THE Audio_Recorder SHALL display a persistent notification indicating active recording
3. IF the system terminates the app due to resource constraints, THEN THE Audio_Recorder SHALL save the current recording before termination

### Requirement 3: Footstep Detection

**User Story:** As a user, I want the app to automatically detect footstep sounds, so that I don't have to manually review hours of recordings.

#### Acceptance Criteria

1. WHEN audio is being recorded, THE Noise_Analyzer SHALL continuously analyze the audio stream for footstep patterns
2. WHEN a footstep sound is detected, THE Noise_Analyzer SHALL create a Footstep_Event with timestamp and audio snippet
3. THE Noise_Analyzer SHALL detect footstep sounds with at least 80% accuracy in typical indoor environments
4. WHEN ambient noise levels are high, THE Noise_Analyzer SHALL adjust detection sensitivity to reduce false positives

### Requirement 4: Footstep Classification

**User Story:** As a user, I want footstep sounds to be classified by type (stomping, heel strike, shuffling), so that I can document the specific nature of the disturbance.

#### Acceptance Criteria

1. WHEN a footstep is detected, THE Noise_Classifier SHALL categorize it as one of: stomping, heel_strike, shuffling, running, or unknown
2. THE Noise_Classifier SHALL assign a confidence score (0-100%) to each classification
3. WHEN confidence is below 50%, THE Noise_Classifier SHALL mark the event as "unknown" for manual review
4. THE Noise_Classifier SHALL provide intensity level (low, medium, high) for each detected footstep

### Requirement 5: Event Logging

**User Story:** As a user, I want all detected footstep events to be logged with details, so that I have a comprehensive record of disturbances.

#### Acceptance Criteria

1. WHEN a Footstep_Event is created, THE System SHALL persist it with: timestamp, classification, confidence, intensity, and audio clip reference
2. THE System SHALL store audio clips of detected events for playback and evidence
3. WHEN viewing the event log, THE System SHALL display events in chronological order with filtering options
4. THE System SHALL allow users to add notes or annotations to individual events

### Requirement 6: Evidence Report Generation

**User Story:** As a user, I want to generate reports summarizing noise events, so that I can present evidence to landlords or authorities.

#### Acceptance Criteria

1. WHEN the user requests a report, THE System SHALL generate a summary including: total events, events by type, peak activity times, and date range
2. THE Evidence_Report SHALL include visual charts showing noise frequency over time
3. THE Evidence_Report SHALL be exportable as PDF format
4. THE Evidence_Report SHALL include options to attach selected audio clips as evidence

### Requirement 7: Recording Session Management

**User Story:** As a user, I want to manage my recording sessions, so that I can organize and review captured data.

#### Acceptance Criteria

1. THE System SHALL display a list of all recording sessions with date, duration, and event count
2. WHEN the user selects a session, THE System SHALL show detailed event timeline for that session
3. THE System SHALL allow users to delete sessions and associated data
4. THE System SHALL display storage usage and warn when device storage is low

### Requirement 8: Real-time Feedback

**User Story:** As a user, I want to see real-time feedback during recording, so that I know the app is detecting sounds correctly.

#### Acceptance Criteria

1. WHILE recording, THE System SHALL display a live audio waveform visualization
2. WHEN a footstep is detected in real-time, THE System SHALL display a visual indicator with the classification
3. THE System SHALL show a running count of detected events during the current session
4. THE System SHALL display current decibel level of ambient sound

### Requirement 9: Data Persistence

**User Story:** As a user, I want my recordings and analysis data to be safely stored, so that I don't lose my evidence.

#### Acceptance Criteria

1. THE System SHALL store all data locally on the device using Core Data
2. THE System SHALL serialize Recording_Session and Footstep_Event objects to JSON for export
3. WHEN exporting data, THE System SHALL parse the JSON format correctly when re-importing
4. THE System SHALL provide a pretty-printed JSON export option for human readability
5. FOR ALL valid Recording_Session objects, serializing then deserializing SHALL produce an equivalent object (round-trip property)
