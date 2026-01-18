//
//  AudioRecorder.swift
//  FootstepNoiseAnalyzer
//
//  Handles microphone capture using AVFoundation with background audio support.
//  Requirements: 1.1, 1.2, 1.3, 2.1
//

import Foundation
import AVFoundation
import Combine

/// Protocol defining the interface for audio recording operations.
protocol AudioRecorderProtocol: AnyObject {
    /// Whether recording is currently active
    var isRecording: Bool { get }
    
    /// Whether recording is currently paused
    var isPaused: Bool { get }
    
    /// Whether monitoring (live audio without recording) is active
    var isMonitoring: Bool { get }
    
    /// Current duration of the recording in seconds
    var currentDuration: TimeInterval { get }
    
    /// Publisher that emits audio level updates (0.0 to 1.0)
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    
    /// Publisher that emits audio buffers for analysis
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> { get }
    
    /// Start a new recording session
    /// - Returns: The newly created RecordingSession
    /// - Throws: AudioRecorderError if recording cannot be started
    func startRecording() async throws -> RecordingSession
    
    /// Stop the current recording
    /// - Returns: The completed RecordingSession
    /// - Throws: AudioRecorderError if there's no active recording
    func stopRecording() async throws -> RecordingSession
    
    /// Pause the current recording
    func pauseRecording()
    
    /// Resume a paused recording
    func resumeRecording()
    
    /// Start monitoring audio without recording to file
    /// - Throws: AudioRecorderError if monitoring cannot be started
    func startMonitoring() async throws
    
    /// Stop monitoring audio
    func stopMonitoring()
}

/// Implementation of AudioRecorderProtocol using AVAudioEngine.
final class AudioRecorder: AudioRecorderProtocol {
    
    // MARK: - Public Properties
    
    private(set) var isRecording: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var isMonitoring: Bool = false
    
    var currentDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        if isPaused, let pauseTime = pauseStartTime {
            return pauseTime.timeIntervalSince(startTime) - totalPausedDuration
        }
        return Date().timeIntervalSince(startTime) - totalPausedDuration
    }
    
    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }
    
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        audioBufferSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentSession: RecordingSession?
    private var recordingStartTime: Date?
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    
    private let audioLevelSubject = PassthroughSubject<Float, Never>()
    private let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    
    private let bufferSize: AVAudioFrameCount = 4096
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods

    
    func startRecording() async throws -> RecordingSession {
        guard !isRecording else {
            throw AudioRecorderError.recordingAlreadyInProgress
        }
        
        // Stop monitoring if active (we'll start recording instead)
        if isMonitoring {
            stopMonitoring()
        }
        
        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw AudioRecorderError.microphonePermissionDenied
        }
        
        // Configure audio session for background recording
        try configureAudioSession()
        
        // Create new session
        let sessionId = UUID()
        let startTime = Date()
        let fileURL = try createAudioFileURL(for: sessionId)
        
        // Set up audio file for recording
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        do {
            audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: recordingFormat.settings,
                commonFormat: recordingFormat.commonFormat,
                interleaved: recordingFormat.isInterleaved
            )
        } catch {
            throw AudioRecorderError.fileWriteFailed(underlying: error)
        }
        
        // Install tap on input node for audio processing
        installAudioTap(on: inputNode, format: recordingFormat, writeToFile: true)
        
        // Start the audio engine
        do {
            try audioEngine.start()
        } catch {
            removeTap()
            throw AudioRecorderError.audioEngineStartFailed(underlying: error)
        }
        
        // Create and store session
        let session = RecordingSession(
            id: sessionId,
            startTime: startTime,
            endTime: nil,
            eventCount: 0,
            fileURLs: [fileURL],
            status: .recording
        )
        
        currentSession = session
        recordingStartTime = startTime
        totalPausedDuration = 0
        isRecording = true
        isPaused = false
        
        return session
    }
    
    func stopRecording() async throws -> RecordingSession {
        guard isRecording, var session = currentSession else {
            throw AudioRecorderError.noActiveRecording
        }
        
        // Stop the audio engine and remove tap
        audioEngine.stop()
        removeTap()
        
        // Close the audio file
        audioFile = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        // Update session
        session.endTime = Date()
        session.status = .completed
        
        // Reset state
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
        
        audioEngine.pause()
        isPaused = true
        pauseStartTime = Date()
        
        if var session = currentSession {
            session.status = .paused
            currentSession = session
        }
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        
        // Calculate paused duration
        if let pauseStart = pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }
        
        do {
            try audioEngine.start()
            isPaused = false
            pauseStartTime = nil
            
            if var session = currentSession {
                session.status = .recording
                currentSession = session
            }
        } catch {
            // Log error but don't throw - resume is best effort
            print("Failed to resume recording: \(error.localizedDescription)")
        }
    }
    
    func startMonitoring() async throws {
        guard !isRecording && !isMonitoring else { return }
        
        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw AudioRecorderError.microphonePermissionDenied
        }
        
        // Configure audio session
        try configureAudioSession()
        
        // Set up audio tap without file writing
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node for audio processing (no file writing)
        installAudioTap(on: inputNode, format: recordingFormat, writeToFile: false)
        
        // Start the audio engine
        do {
            try audioEngine.start()
            isMonitoring = true
        } catch {
            removeTap()
            throw AudioRecorderError.audioEngineStartFailed(underlying: error)
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        audioEngine.stop()
        removeTap()
        isMonitoring = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    
    // MARK: - Private Methods
    
    /// Request microphone permission from the user.
    private func requestMicrophonePermission() async -> Bool {
        let status = AVAudioApplication.shared.recordPermission
        
        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
    
    /// Configure AVAudioSession for background recording.
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioRecorderError.audioSessionConfigurationFailed(underlying: error)
        }
    }
    
    /// Create a URL for the audio file.
    private func createAudioFileURL(for sessionId: UUID) throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        // Create recordings directory if needed
        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }
        
        let fileName = "\(sessionId.uuidString)_\(Int(Date().timeIntervalSince1970)).caf"
        return recordingsPath.appendingPathComponent(fileName)
    }
    
    /// Install audio tap on the input node for processing.
    private func installAudioTap(on inputNode: AVAudioInputNode, format: AVAudioFormat, writeToFile: Bool) {
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self, !self.isPaused else { return }
            
            // Write to file only if recording (not monitoring)
            if writeToFile, let audioFile = self.audioFile {
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    print("Failed to write audio buffer: \(error.localizedDescription)")
                }
            }
            
            // Calculate and publish audio level
            let level = self.calculateAudioLevel(from: buffer)
            self.audioLevelSubject.send(level)
            
            // Publish buffer for analysis
            self.audioBufferSubject.send(buffer)
        }
    }
    
    /// Remove the audio tap from the input node.
    private func removeTap() {
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    /// Calculate the audio level (RMS) from a buffer.
    /// - Returns: Normalized audio level between 0.0 and 1.0 (based on dB SPL scale)
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        
        // Calculate RMS (Root Mean Square)
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Convert RMS to dBFS, then to approximate dB SPL
        let dbFS = 20 * log10(max(rms, 0.000001))
        let dbSPL = dbFS + DecibelCalculator.dbFSToSPLOffset
        
        // Normalize to 0-1 range using typical indoor sound range (30-100 dB SPL)
        let minSPL: Float = 30.0   // Quiet room
        let maxSPL: Float = 100.0  // Very loud
        let normalizedLevel = (dbSPL - minSPL) / (maxSPL - minSPL)
        
        return max(0, min(1, normalizedLevel))
    }
}
