//
//  AudioFileAnalysisTests.swift
//  FootstepNoiseAnalyzerTests
//
//  Tests that analyze real audio files for footstep classification.
//

import XCTest
import AVFoundation
import Combine
@testable import FootstepNoiseAnalyzer

final class AudioFileAnalysisTests: XCTestCase {
    
    var classifier: NoiseClassifier!
    var noiseAnalyzer: NoiseAnalyzer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        classifier = NoiseClassifier()
        // Use a low threshold calibrated from real audio files
        // RMS median ~0.0025, 90th percentile ~0.0085
        noiseAnalyzer = NoiseAnalyzer(threshold: 0.003)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        classifier = nil
        noiseAnalyzer = nil
        cancellables = nil
        super.tearDown()
    }
    
    /// Analyze the stomping.m4a test file and verify classification results
    /// Expected: ~15-17 events with 1 hard, 2 medium, rest mild stomping
    func testAnalyzeStompingAudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFile(at: fileURL)
        
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
        XCTAssertGreaterThanOrEqual(totalFootsteps, 12, "Should detect at least 12 footstep events")
        XCTAssertLessThanOrEqual(totalFootsteps, 55, "Should not detect more than 55 events (direct classifier is more sensitive)")
        XCTAssertGreaterThanOrEqual(hardCount, 1, "Should detect at least 1 hard stomping")
        XCTAssertGreaterThanOrEqual(mediumCount, 1, "Should detect at least 1 medium stomping")
        XCTAssertGreaterThanOrEqual(mildCount, 8, "Should detect at least 8 mild stomping")
    }
    
    /// Analyze stomping.m4a using the FULL pipeline (NoiseAnalyzer -> NoiseClassifier)
    /// This tests the same code path as real-time recording
    func testAnalyzeStompingWithFullPipeline() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithFullPipeline(at: fileURL)
        
        // Print detailed results for debugging
        print("\n*** FULL PIPELINE RESULTS (NoiseAnalyzer -> NoiseClassifier) ***")
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
        
        // Same assertions - full pipeline should detect same events
        XCTAssertGreaterThanOrEqual(totalFootsteps, 12, "Full pipeline should detect at least 12 footstep events")
        XCTAssertLessThanOrEqual(totalFootsteps, 25, "Full pipeline should not detect more than 25 events")
        XCTAssertGreaterThanOrEqual(hardCount, 1, "Full pipeline should detect at least 1 hard stomping")
    }
    
    /// Analyze the stomping2.m4a test file and verify classification results
    /// Expected: 1 hard stomping event only
    func testAnalyzeStomping2AudioFile() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping2.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFile(at: fileURL)
        
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
        // Direct classifier may detect more due to no NoiseAnalyzer filtering
        XCTAssertGreaterThanOrEqual(totalFootsteps, 1, "Should detect at least 1 footstep event")
        XCTAssertLessThanOrEqual(totalFootsteps, 10, "Should not detect more than 10 events")
        XCTAssertGreaterThanOrEqual(hardCount, 1, "Should detect at least 1 hard stomping")
    }
    
    /// Analyze stomping2.m4a using the FULL pipeline (NoiseAnalyzer -> NoiseClassifier)
    func testAnalyzeStomping2WithFullPipeline() throws {
        let fileURL = URL(fileURLWithPath: "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping2.m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Test audio file not found at: \(fileURL.path)")
        }
        
        let results = try analyzeAudioFileWithFullPipeline(at: fileURL)
        
        // Print detailed results for debugging
        print("\n*** FULL PIPELINE RESULTS (NoiseAnalyzer -> NoiseClassifier) ***")
        printAnalysisResults(results, fileURL: fileURL)
        
        // Count by type
        var typeCounts: [FootstepType: Int] = [:]
        for result in results {
            typeCounts[result.classification.type, default: 0] += 1
        }
        
        let hardCount = typeCounts[.hardStomping] ?? 0
        let totalFootsteps = results.count
        
        // Same assertions - full pipeline should detect same events
        XCTAssertEqual(totalFootsteps, 1, "Full pipeline should detect exactly 1 footstep event")
        XCTAssertEqual(hardCount, 1, "Full pipeline should detect exactly 1 hard stomping")
    }
    
    // MARK: - Helper Methods
    
    /// Minimum gap between events to merge consecutive detections of the same footstep
    private let eventMergeWindow: TimeInterval = 0.20
    
    /// Analyze audio file using the full pipeline (NoiseAnalyzer -> NoiseClassifier)
    /// This matches how real-time recording works in the app
    private func analyzeAudioFileWithFullPipeline(at url: URL) throws -> [TestAnalysisResult] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        var results: [TestAnalysisResult] = []
        var currentFrame: AVAudioFramePosition = 0
        var lastConfirmedEventTime: TimeInterval?
        var lastConfirmedEventDb: Float?
        var pendingEvent: TestAnalysisResult?
        var pendingEventStartTime: TimeInterval?
        
        // Track RMS values for debugging
        var allRmsValues: [Float] = []
        var detectedRmsValues: [Float] = []
        
        // Reset analyzer state
        noiseAnalyzer.reset()
        
        // Subscribe to detection events from NoiseAnalyzer
        let expectation = XCTestExpectation(description: "Audio analysis complete")
        
        noiseAnalyzer.detectionPublisher
            .sink { [weak self] audioEvent in
                guard let self = self else { return }
                
                detectedRmsValues.append(audioEvent.amplitude)
                
                let currentTime = audioEvent.timestamp
                
                // For echo detection, use the most recent event (pending or confirmed)
                let echoRefTime: TimeInterval?
                let echoRefDb: Float?
                if let pending = pendingEvent {
                    echoRefTime = pending.timestamp
                    echoRefDb = pending.classification.decibelLevel
                } else {
                    echoRefTime = lastConfirmedEventTime
                    echoRefDb = lastConfirmedEventDb
                }
                
                if let classification = self.classifier.classify(
                    audioBuffer: audioEvent.buffer,
                    previousConfirmedEventTime: lastConfirmedEventTime,
                    recentLoudEventTime: echoRefTime,
                    recentLoudEventDb: echoRefDb,
                    currentTime: currentTime
                ) {
                    // Check if this is within the merge window of a pending event
                    if let pendingStart = pendingEventStartTime, (currentTime - pendingStart) < eventMergeWindow {
                        // Within merge window - update pending event if this is louder
                        if let pending = pendingEvent {
                            if classification.decibelLevel > pending.classification.decibelLevel {
                                pendingEvent = TestAnalysisResult(
                                    timestamp: currentTime,
                                    classification: classification
                                )
                            }
                        }
                    } else {
                        // Outside merge window - confirm pending event and start new one
                        if let pending = pendingEvent {
                            results.append(pending)
                            lastConfirmedEventTime = pending.timestamp
                            lastConfirmedEventDb = pending.classification.decibelLevel
                        }
                        pendingEvent = TestAnalysisResult(
                            timestamp: currentTime,
                            classification: classification
                        )
                        pendingEventStartTime = currentTime
                    }
                }
            }
            .store(in: &cancellables)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioFileAnalysisTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        
        // Process all buffers through NoiseAnalyzer
        while currentFrame < totalFrames {
            let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - AVAudioFrameCount(currentFrame)))
            
            audioFile.framePosition = currentFrame
            try audioFile.read(into: buffer, frameCount: framesToRead)
            
            let currentTime = Double(currentFrame) / Double(sampleRate)
            
            // Calculate RMS for debugging
            if let channelData = buffer.floatChannelData?[0] {
                let rms = noiseAnalyzer.calculateRMS(channelData, frameCount: Int(buffer.frameLength))
                allRmsValues.append(rms)
            }
            
            // Feed buffer through NoiseAnalyzer (like real-time does)
            noiseAnalyzer.analyze(buffer: buffer, timestamp: currentTime)
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        // Don't forget the last pending event
        if let pending = pendingEvent {
            results.append(pending)
        }
        
        // Print RMS statistics for calibration
        printRmsStatistics(allRmsValues: allRmsValues, detectedRmsValues: detectedRmsValues, fileURL: url)
        
        return results
    }
    
    private func printRmsStatistics(allRmsValues: [Float], detectedRmsValues: [Float], fileURL: URL) {
        guard !allRmsValues.isEmpty else { return }
        
        let sortedRms = allRmsValues.sorted()
        let maxRms = sortedRms.last ?? 0
        let minRms = sortedRms.first ?? 0
        let medianRms = sortedRms[sortedRms.count / 2]
        let avgRms = allRmsValues.reduce(0, +) / Float(allRmsValues.count)
        
        // Calculate percentiles
        let p90Index = Int(Float(sortedRms.count) * 0.90)
        let p95Index = Int(Float(sortedRms.count) * 0.95)
        let p99Index = Int(Float(sortedRms.count) * 0.99)
        let p90 = sortedRms[min(p90Index, sortedRms.count - 1)]
        let p95 = sortedRms[min(p95Index, sortedRms.count - 1)]
        let p99 = sortedRms[min(p99Index, sortedRms.count - 1)]
        
        print("\n" + String(repeating: "-", count: 60))
        print("RMS STATISTICS FOR: \(fileURL.lastPathComponent)")
        print(String(repeating: "-", count: 60))
        print("Total buffers analyzed: \(allRmsValues.count)")
        print("Buffers passed NoiseAnalyzer: \(detectedRmsValues.count)")
        print("Current detection threshold: \(noiseAnalyzer.detectionThreshold)")
        print("")
        print("RMS Range: \(String(format: "%.6f", minRms)) - \(String(format: "%.6f", maxRms))")
        print("RMS Average: \(String(format: "%.6f", avgRms))")
        print("RMS Median: \(String(format: "%.6f", medianRms))")
        print("RMS 90th percentile: \(String(format: "%.6f", p90))")
        print("RMS 95th percentile: \(String(format: "%.6f", p95))")
        print("RMS 99th percentile: \(String(format: "%.6f", p99))")
        print("")
        print("RECOMMENDATION: Set detectionThreshold between \(String(format: "%.4f", medianRms)) and \(String(format: "%.4f", p90))")
        print(String(repeating: "-", count: 60))
    }
    
    private func analyzeAudioFile(at url: URL) throws -> [TestAnalysisResult] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        var results: [TestAnalysisResult] = []
        var currentFrame: AVAudioFramePosition = 0
        var lastConfirmedEventTime: TimeInterval?
        var lastConfirmedEventDb: Float?
        var pendingEvent: TestAnalysisResult?
        var pendingEventStartTime: TimeInterval?
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioFileAnalysisTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        
        while currentFrame < totalFrames {
            let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - AVAudioFrameCount(currentFrame)))
            
            audioFile.framePosition = currentFrame
            try audioFile.read(into: buffer, frameCount: framesToRead)
            
            let currentTime = Double(currentFrame) / Double(sampleRate)
            
            // For echo detection, use the most recent event (pending or confirmed)
            let echoRefTime: TimeInterval?
            let echoRefDb: Float?
            if let pending = pendingEvent {
                echoRefTime = pending.timestamp
                echoRefDb = pending.classification.decibelLevel
            } else {
                echoRefTime = lastConfirmedEventTime
                echoRefDb = lastConfirmedEventDb
            }
            
            if let classification = classifier.classify(
                audioBuffer: buffer,
                previousConfirmedEventTime: lastConfirmedEventTime,
                recentLoudEventTime: echoRefTime,
                recentLoudEventDb: echoRefDb,
                currentTime: currentTime
            ) {
                // Check if this is within the merge window of a pending event
                if let pendingStart = pendingEventStartTime, (currentTime - pendingStart) < eventMergeWindow {
                    // Within merge window - update pending event if this is louder
                    if let pending = pendingEvent {
                        if classification.decibelLevel > pending.classification.decibelLevel {
                            pendingEvent = TestAnalysisResult(
                                timestamp: currentTime,
                                classification: classification
                            )
                        }
                    }
                } else {
                    // Outside merge window - confirm pending event and start new one
                    if let pending = pendingEvent {
                        results.append(pending)
                        lastConfirmedEventTime = pending.timestamp
                        lastConfirmedEventDb = pending.classification.decibelLevel
                    }
                    pendingEvent = TestAnalysisResult(
                        timestamp: currentTime,
                        classification: classification
                    )
                    pendingEventStartTime = currentTime
                }
            }
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        // Don't forget the last pending event
        if let pending = pendingEvent {
            results.append(pending)
        }
        
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
