//
//  AudioFileAnalysisTests.swift
//  FootstepNoiseAnalyzerTests
//
//  Tests that analyze real audio files for footstep classification.
//

import XCTest
import AVFoundation
@testable import FootstepNoiseAnalyzer

final class AudioFileAnalysisTests: XCTestCase {
    
    var classifier: NoiseClassifier!
    
    /// Minimum gap between events to avoid counting the same footstep multiple times
    let minimumEventGap: TimeInterval = 0.20
    
    override func setUp() {
        super.setUp()
        classifier = NoiseClassifier()
    }
    
    override func tearDown() {
        classifier = nil
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
        XCTAssertLessThanOrEqual(totalFootsteps, 20, "Should not detect more than 20 events")
        XCTAssertGreaterThanOrEqual(hardCount, 1, "Should detect at least 1 hard stomping")
        XCTAssertGreaterThanOrEqual(mediumCount, 1, "Should detect at least 1 medium stomping")
        XCTAssertGreaterThanOrEqual(mildCount, 8, "Should detect at least 8 mild stomping")
    }
    
    // MARK: - Helper Methods
    
    private func analyzeAudioFile(at url: URL) throws -> [TestAnalysisResult] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        var results: [TestAnalysisResult] = []
        var currentFrame: AVAudioFramePosition = 0
        var lastEventTime: TimeInterval?
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioFileAnalysisTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        
        while currentFrame < totalFrames {
            let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - AVAudioFrameCount(currentFrame)))
            
            audioFile.framePosition = currentFrame
            try audioFile.read(into: buffer, frameCount: framesToRead)
            
            let currentTime = Double(currentFrame) / Double(sampleRate)
            
            if let classification = classifier.classify(
                audioBuffer: buffer,
                previousEventTime: lastEventTime,
                currentTime: currentTime
            ) {
                // Check if too close to last event - merge consecutive detections
                if let lastTime = lastEventTime, (currentTime - lastTime) < minimumEventGap {
                    // If this event is louder and a valid footstep, replace the last one
                    if !results.isEmpty && classification.type != .unknown {
                        let lastResult = results[results.count - 1]
                        if classification.decibelLevel > lastResult.classification.decibelLevel || lastResult.classification.type == .unknown {
                            results[results.count - 1] = TestAnalysisResult(
                                timestamp: currentTime,
                                classification: classification
                            )
                            lastEventTime = currentTime
                        }
                    }
                } else {
                    results.append(TestAnalysisResult(
                        timestamp: currentTime,
                        classification: classification
                    ))
                    lastEventTime = currentTime
                }
            }
            
            currentFrame += AVAudioFramePosition(framesToRead)
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
