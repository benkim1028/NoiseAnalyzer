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
    /// With ambient-relative classification:
    /// - Ambient ~41 dB, thresholds: mild 46, medium 51, hard 56, extreme 61
    /// - Expected: mix of mild, medium, hard, and possibly extreme stomping
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
        let extremeCount = typeCounts[.extremeStomping] ?? 0
        let totalFootsteps = mildCount + mediumCount + hardCount + extremeCount
        
        // Assertions based on ambient-relative classification with 70% impact energy threshold
        // The file contains multiple footsteps of varying intensity
        XCTAssertGreaterThanOrEqual(totalFootsteps, 8, "Should detect at least 8 footstep events")
        XCTAssertLessThanOrEqual(totalFootsteps, 20, "Should not detect more than 20 events")
        
        // Should have a mix of classifications (relative to ambient)
        XCTAssertGreaterThanOrEqual(mildCount + mediumCount, 5, "Should detect at least 5 mild or medium stomping")
    }
    
    /// Analyze the stomping2.m4a test file using the production pipeline
    /// Contains a single loud stomp - should be classified as hard or extreme relative to ambient
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
        let extremeCount = typeCounts[.extremeStomping] ?? 0
        let totalFootsteps = results.count
        
        // Assertions - should detect 1-2 events (may detect echo as separate event)
        XCTAssertGreaterThanOrEqual(totalFootsteps, 1, "Should detect at least 1 footstep event")
        XCTAssertLessThanOrEqual(totalFootsteps, 3, "Should not detect more than 3 events")
        XCTAssertGreaterThanOrEqual(hardCount + extremeCount, 1, "Should detect at least 1 hard or extreme stomping")
    }
    
    /// Analyze the no stomping1.m4a test file using the production pipeline
    /// This file contains non-footstep sounds - should detect few or no footstep events
    func testAnalyzeNoStomping1AudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping1.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithProductionPipeline(at: fileURL)
        
        // Print detailed results for debugging
        printAnalysisResults(results, fileURL: fileURL)
        
        // With ambient-relative classification, non-footstep sounds should mostly be filtered
        // Allow some false positives but should be minimal
        XCTAssertLessThanOrEqual(results.count, 5, "Should detect very few events in no stomping1.m4a")
    }
    
    /// Analyze the no stomping2.m4a test file using the production pipeline
    /// This file contains ambient noise - may detect some events due to ambient variations
    func testAnalyzeNoStomping2AudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping2.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithProductionPipeline(at: fileURL)
        
        // Print detailed results for debugging
        printAnalysisResults(results, fileURL: fileURL)
        
        // This file may have ambient variations that trigger detection
        // The key is that it should detect significantly fewer events than stomping files
        // and most should be mild (close to ambient threshold)
        var mildCount = 0
        for result in results {
            if result.classification.type == .mildStomping {
                mildCount += 1
            }
        }
        
        // Most detected events should be mild (if any)
        if results.count > 0 {
            let mildRatio = Float(mildCount) / Float(results.count)
            XCTAssertGreaterThanOrEqual(mildRatio, 0.5, "Most false positives should be mild stomping")
        }
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
        print("Ambient level used: \(String(format: "%.1f", AmbientLevelTracker.shared.ambientLevel)) dB")
        
        // Show thresholds
        let thresholds = SensitivitySettings.shared.getThresholds(ambientLevel: AmbientLevelTracker.shared.ambientLevel)
        print("Thresholds - Mild: \(String(format: "%.1f", thresholds.mild)), Medium: \(String(format: "%.1f", thresholds.medium)), Hard: \(String(format: "%.1f", thresholds.hard)), Extreme: \(String(format: "%.1f", thresholds.extreme))")
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

// MARK: - Ambient Level Analysis Extension

extension AudioFileAnalysisTests {
    
    /// Analyze ambient sound levels in all test audio files
    func testAnalyzeAmbientLevels() throws {
        let files = [
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping.m4a",
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping2.m4a",
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping1.m4a",
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping2.m4a"
        ]
        
        for filePath in files {
            let url = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: filePath) else {
                print("File not found: \(filePath)")
                continue
            }
            
            try analyzeAmbientLevel(at: url)
        }
    }
    
    private func analyzeAmbientLevel(at url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        var allDbValues: [Float] = []
        var currentFrame: AVAudioFramePosition = 0
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            print("Failed to create buffer")
            return
        }
        
        while currentFrame < totalFrames {
            let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - AVAudioFrameCount(currentFrame)))
            audioFile.framePosition = currentFrame
            try audioFile.read(into: buffer, frameCount: framesToRead)
            
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameCount = Int(buffer.frameLength)
            
            // Calculate RMS
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            
            // Convert to dB SPL (using 75 dB base offset)
            if rms > 0 {
                let dbFS = 20 * log10(rms)
                let dbSPL = dbFS + 75
                allDbValues.append(dbSPL)
            }
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        // Sort to find percentiles
        let sortedDb = allDbValues.sorted()
        let count = sortedDb.count
        guard count > 0 else { return }
        
        print("\n" + String(repeating: "=", count: 50))
        print("AMBIENT LEVEL ANALYSIS: \(url.lastPathComponent)")
        print(String(repeating: "=", count: 50))
        print("Total buffers analyzed: \(count)")
        print("")
        print("dB SPL Statistics:")
        print("  Min:         \(String(format: "%.1f", sortedDb.first ?? 0)) dB")
        print("  5th %ile:    \(String(format: "%.1f", sortedDb[count * 5 / 100])) dB")
        print("  10th %ile:   \(String(format: "%.1f", sortedDb[count * 10 / 100])) dB")
        print("  25th %ile:   \(String(format: "%.1f", sortedDb[count * 25 / 100])) dB")
        print("  Median:      \(String(format: "%.1f", sortedDb[count / 2])) dB")
        print("  75th %ile:   \(String(format: "%.1f", sortedDb[count * 75 / 100])) dB")
        print("  90th %ile:   \(String(format: "%.1f", sortedDb[count * 90 / 100])) dB")
        print("  95th %ile:   \(String(format: "%.1f", sortedDb[count * 95 / 100])) dB")
        print("  Max:         \(String(format: "%.1f", sortedDb.last ?? 0)) dB")
        print("")
        print("Estimated ambient (10th-25th %ile): \(String(format: "%.1f", sortedDb[count * 10 / 100])) - \(String(format: "%.1f", sortedDb[count * 25 / 100])) dB")
        print(String(repeating: "=", count: 50))
    }
}
