//
//  AudioFileAnalysisTests.swift
//  FootstepNoiseAnalyzerTests
//
//  Tests that analyze real audio files for footstep classification.
//  Uses the same NoiseAnalyzer -> NoiseClassifier pipeline as production code.
//

import XCTest
import AVFoundation
import Combine
@testable import FootstepNoiseAnalyzer

final class AudioFileAnalysisTests: XCTestCase {
    
    var analysisService: AnalysisService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        // Reset sensitivity to default for consistent test results
        SensitivitySettings.shared.resetToDefault()
        // Use the same AnalysisService that the app uses in production
        analysisService = AnalysisService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        analysisService = nil
        cancellables = nil
        super.tearDown()
    }
    
    /// Analyze the stomping.m4a test file using the production pipeline
    /// Expected: ~15-17 events with 1 hard, 2 medium, rest mild stomping
    func testAnalyzeStompingAudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithProductionPipeline(at: fileURL)
        
        // Print detailed results for debugging
        printAnalysisResults(results, fileURL: fileURL)
        
        // Count by type
        var typeCounts: [FootstepType: Int] = [:]
        for result in results {
            typeCounts[result.classification.type, default: 0] += 1
        }
        
        let mildCount = typeCounts[.mildStomping] ?? 0
        let mediumCount = typeCounts[.mediumStomping] ?? 0
        let hardCount = typeCounts[.hardStomping] ?? 0
        let totalFootsteps = mildCount + mediumCount + hardCount
        
        // Assertions based on known audio content
        XCTAssertGreaterThanOrEqual(totalFootsteps, 11, "Should detect at least 11 footstep events")
        XCTAssertLessThanOrEqual(totalFootsteps, 25, "Should not detect more than 25 events")
        XCTAssertGreaterThanOrEqual(hardCount, 1, "Should detect at least 1 hard stomping")
        XCTAssertGreaterThanOrEqual(mediumCount, 1, "Should detect at least 1 medium stomping")
        XCTAssertGreaterThanOrEqual(mildCount, 8, "Should detect at least 8 mild stomping")
    }
    
    /// Analyze the stomping2.m4a test file using the production pipeline
    /// Expected: 1 hard stomping event only
    func testAnalyzeStomping2AudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping2.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithProductionPipeline(at: fileURL)
        
        // Print detailed results for debugging
        printAnalysisResults(results, fileURL: fileURL)
        
        // Count by type
        var typeCounts: [FootstepType: Int] = [:]
        for result in results {
            typeCounts[result.classification.type, default: 0] += 1
        }
        
        let hardCount = typeCounts[.hardStomping] ?? 0
        let totalFootsteps = results.count
        
        // Assertions based on known audio content - single hard stomp
        XCTAssertEqual(totalFootsteps, 1, "Should detect exactly 1 footstep event")
        XCTAssertEqual(hardCount, 1, "Should detect exactly 1 hard stomping")
    }
    
    /// Analyze the no stomping1.m4a test file using the production pipeline
    /// Expected: No footstep events detected
    func testAnalyzeNoStomping1AudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping1.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithProductionPipeline(at: fileURL)
        
        // Print detailed results for debugging
        printAnalysisResults(results, fileURL: fileURL)
        
        // Assertions - should detect no footstep events
        XCTAssertEqual(results.count, 0, "Should detect no footstep events in no stomping1.m4a")
    }
    
    /// Analyze the no stomping2.m4a test file using the production pipeline
    /// Expected: No footstep events detected
    func testAnalyzeNoStomping2AudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping2.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithProductionPipeline(at: fileURL)
        
        // Print detailed results for debugging
        printAnalysisResults(results, fileURL: fileURL)
        
        // Assertions - should detect no footstep events
        XCTAssertEqual(results.count, 0, "Should detect no footstep events in no stomping2.m4a")
    }
    
    // MARK: - Helper Methods
    
    /// Minimum gap between events to merge consecutive detections of the same footstep
    private let eventMergeWindow: TimeInterval = 0.20
    
    /// Analyze audio file using the production AnalysisService pipeline.
    /// This is the exact same code path used during real-time recording in the app.
    private func analyzeAudioFileWithProductionPipeline(at url: URL) throws -> [TestAnalysisResult] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        var results: [TestAnalysisResult] = []
        var currentFrame: AVAudioFramePosition = 0
        var pendingEvent: TestAnalysisResult?
        var pendingEventStartTime: TimeInterval?
        
        // Create a mock session for the analysis service
        let mockSession = RecordingSession(
            id: UUID(),
            startTime: Date(),
            endTime: nil,
            eventCount: 0,
            fileURLs: [url],
            status: .recording
        )
        
        // Start analysis using the production service
        analysisService.startAnalysis(for: mockSession)
        
        // Subscribe to events from the production pipeline
        analysisService.eventPublisher
            .sink { [weak self] footstepEvent in
                guard let self = self else { return }
                
                let currentTime = footstepEvent.timestampInRecording
                
                // Check if this is within the merge window of a pending event
                if let pendingStart = pendingEventStartTime, (currentTime - pendingStart) < self.eventMergeWindow {
                    // Within merge window - update pending event if this is louder
                    if let pending = pendingEvent {
                        if footstepEvent.classification.decibelLevel > pending.classification.decibelLevel {
                            pendingEvent = TestAnalysisResult(
                                timestamp: currentTime,
                                classification: footstepEvent.classification
                            )
                        }
                    }
                } else {
                    // Outside merge window - confirm pending event and start new one
                    if let pending = pendingEvent {
                        results.append(pending)
                    }
                    pendingEvent = TestAnalysisResult(
                        timestamp: currentTime,
                        classification: footstepEvent.classification
                    )
                    pendingEventStartTime = currentTime
                }
            }
            .store(in: &cancellables)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioFileAnalysisTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        
        // Process all buffers through the production AnalysisService
        while currentFrame < totalFrames {
            let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - AVAudioFrameCount(currentFrame)))
            
            audioFile.framePosition = currentFrame
            try audioFile.read(into: buffer, frameCount: framesToRead)
            
            let currentTime = Double(currentFrame) / Double(sampleRate)
            
            // Feed buffer through the production pipeline
            analysisService.processBuffer(buffer, timestamp: currentTime)
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        // Don't forget the last pending event
        if let pending = pendingEvent {
            results.append(pending)
        }
        
        // Stop analysis
        analysisService.stopAnalysis()
        
        return results
    }
    
    private func printAnalysisResults(_ results: [TestAnalysisResult], fileURL: URL) {
        print("\n" + String(repeating: "=", count: 60))
        print("AUDIO FILE ANALYSIS RESULTS")
        print(String(repeating: "=", count: 60))
        print("File: \(fileURL.lastPathComponent)")
        print("Total events detected: \(results.count)")
        print(String(repeating: "-", count: 60))
        
        // Count by type
        var typeCounts: [FootstepType: Int] = [:]
        var totalDb: Float = 0
        var totalFreq: Float = 0
        
        for result in results {
            typeCounts[result.classification.type, default: 0] += 1
            totalDb += result.classification.decibelLevel
            totalFreq += result.classification.dominantFrequency
        }
        
        print("\nCLASSIFICATION SUMMARY:")
        for type in FootstepType.allCases {
            let count = typeCounts[type] ?? 0
            if count > 0 {
                print("  \(type.displayName): \(count)")
            }
        }
        
        if !results.isEmpty {
            print("\nAVERAGES:")
            print("  Average dB: \(String(format: "%.1f", totalDb / Float(results.count)))")
            print("  Average Frequency: \(String(format: "%.0f", totalFreq / Float(results.count))) Hz")
        }
        
        print("\nDETAILED EVENTS:")
        for (index, result) in results.enumerated() {
            let num = "\(index + 1)".padding(toLength: 4, withPad: " ", startingAt: 0)
            let time = String(format: "%.2fs", result.timestamp).padding(toLength: 8, withPad: " ", startingAt: 0)
            let type = result.classification.type.displayName.padding(toLength: 16, withPad: " ", startingAt: 0)
            let db = String(format: "%.1f dB", result.classification.decibelLevel).padding(toLength: 10, withPad: " ", startingAt: 0)
            let freq = String(format: "%.0f Hz", result.classification.dominantFrequency).padding(toLength: 10, withPad: " ", startingAt: 0)
            let conf = String(format: "%.0f%%", result.classification.confidence * 100)
            print("\(num)\(time)\(type)\(db)\(freq)\(conf)")
        }
        
        print(String(repeating: "=", count: 60) + "\n")
    }
}

struct TestAnalysisResult {
    let timestamp: TimeInterval
    let classification: FootstepClassification
}
