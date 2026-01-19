//
//  SpectralAnalysisTests.swift
//  FootstepNoiseAnalyzerTests
//
//  Diagnostic tests to analyze frequency spectrum differences between
//  stomping and non-stomping audio files.
//

import XCTest
import AVFoundation
@testable import FootstepNoiseAnalyzer

final class SpectralAnalysisTests: XCTestCase {
    
    private let frequencyAnalyzer = FrequencyAnalyzer(fftSize: 2048, sampleRate: 44100)
    
    /// Analyze and compare spectral profiles of all test files
    func testCompareSpectralProfiles() throws {
        let stompingFiles = [
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping.m4a",
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/stomping2.m4a"
        ]
        
        let noStompingFiles = [
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping1.m4a",
            "/Users/kimsong/Desktop/NoiseAnalyzer/FootstepNoiseAnalyzer/FootstepTestFiles/no stomping2.m4a"
        ]
        
        print("\n" + String(repeating: "=", count: 80))
        print("SPECTRAL PROFILE COMPARISON")
        print(String(repeating: "=", count: 80))
        
        // Collect spectra from stomping files (use low threshold to catch all events)
        var stompingSpectra: [SpectrumData] = []
        for filePath in stompingFiles {
            let url = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: filePath) else { continue }
            let spectra = try extractLoudEventSpectra(from: url, dbThreshold: 35.0)
            stompingSpectra.append(contentsOf: spectra)
        }
        
        // Collect spectra from non-stomping files (use same low threshold)
        var noStompingSpectra: [SpectrumData] = []
        for filePath in noStompingFiles {
            let url = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: filePath) else { continue }
            let spectra = try extractLoudEventSpectra(from: url, dbThreshold: 35.0)
            noStompingSpectra.append(contentsOf: spectra)
        }
        
        // Print summary statistics
        print("\n--- STOMPING FILES (\(stompingSpectra.count) events) ---")
        printSpectrumStats(stompingSpectra)
        
        print("\n--- NON-STOMPING FILES (\(noStompingSpectra.count) events) ---")
        printSpectrumStats(noStompingSpectra)
        
        // Print individual events for detailed comparison
        print("\n--- DETAILED STOMPING EVENTS (first 10) ---")
        for (i, spectrum) in stompingSpectra.prefix(10).enumerated() {
            printSpectrumDetail(spectrum, index: i + 1)
        }
        
        print("\n--- DETAILED NON-STOMPING EVENTS (first 10) ---")
        for (i, spectrum) in noStompingSpectra.prefix(10).enumerated() {
            printSpectrumDetail(spectrum, index: i + 1)
        }
        
        print("\n" + String(repeating: "=", count: 80))
    }
    
    // MARK: - Helper Types
    
    struct SpectrumData {
        let timestamp: TimeInterval
        let dbLevel: Float
        let dominantFreq: Float
        let spectralCentroid: Float
        let impactRatio: Float      // impact / total
        let lowMidRatio: Float      // lowMid / total
        let midRatio: Float         // mid / total
        let highMidRatio: Float     // highMid / total
        let highRatio: Float        // high / total
        let crestFactor: Float      // peak / RMS (transient indicator)
        let fileName: String
    }
    
    // MARK: - Helper Methods
    
    private func extractLoudEventSpectra(from url: URL, dbThreshold: Float) throws -> [SpectrumData] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        var spectra: [SpectrumData] = []
        var currentFrame: AVAudioFramePosition = 0
        var lastEventTime: TimeInterval = -0.3
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            return []
        }
        
        while currentFrame < totalFrames {
            let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - AVAudioFrameCount(currentFrame)))
            audioFile.framePosition = currentFrame
            try audioFile.read(into: buffer, frameCount: framesToRead)
            
            guard let channelData = buffer.floatChannelData?[0] else {
                currentFrame += AVAudioFramePosition(framesToRead)
                continue
            }
            
            let frameCount = Int(buffer.frameLength)
            let currentTime = Double(currentFrame) / Double(sampleRate)
            
            // Calculate dB level
            let dbLevel = calculateDbLevel(channelData, frameCount: frameCount)
            
            // Only analyze loud events with minimum time gap
            if dbLevel >= dbThreshold && (currentTime - lastEventTime) >= 0.25 {
                if let spectrum = frequencyAnalyzer.analyze(buffer: buffer) {
                    let totalEnergy = spectrum.impactEnergy + spectrum.lowMidEnergy + 
                                     spectrum.midEnergy + spectrum.highMidEnergy + spectrum.highEnergy
                    
                    let crestFactor = calculateCrestFactor(channelData, frameCount: frameCount)
                    
                    let data = SpectrumData(
                        timestamp: currentTime,
                        dbLevel: dbLevel,
                        dominantFreq: spectrum.dominantFrequency,
                        spectralCentroid: spectrum.spectralCentroid,
                        impactRatio: totalEnergy > 0 ? spectrum.impactEnergy / totalEnergy : 0,
                        lowMidRatio: totalEnergy > 0 ? spectrum.lowMidEnergy / totalEnergy : 0,
                        midRatio: totalEnergy > 0 ? spectrum.midEnergy / totalEnergy : 0,
                        highMidRatio: totalEnergy > 0 ? spectrum.highMidEnergy / totalEnergy : 0,
                        highRatio: totalEnergy > 0 ? spectrum.highEnergy / totalEnergy : 0,
                        crestFactor: crestFactor,
                        fileName: url.lastPathComponent
                    )
                    spectra.append(data)
                    lastEventTime = currentTime
                }
            }
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        return spectra
    }
    
    private func calculateDbLevel(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(frameCount))
        guard rms > 0 else { return 0 }
        return 20 * log10(rms) + 75  // dB SPL approximation
    }
    
    private func calculateCrestFactor(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        var peak: Float = 0
        for i in 0..<frameCount {
            let sample = abs(data[i])
            sum += data[i] * data[i]
            peak = max(peak, sample)
        }
        let rms = sqrt(sum / Float(frameCount))
        guard rms > 0 else { return 0 }
        return peak / rms
    }
    
    private func printSpectrumStats(_ spectra: [SpectrumData]) {
        guard !spectra.isEmpty else {
            print("  No events found")
            return
        }
        
        let avgDb = spectra.map { $0.dbLevel }.reduce(0, +) / Float(spectra.count)
        let avgDomFreq = spectra.map { $0.dominantFreq }.reduce(0, +) / Float(spectra.count)
        let avgCentroid = spectra.map { $0.spectralCentroid }.reduce(0, +) / Float(spectra.count)
        let avgImpact = spectra.map { $0.impactRatio }.reduce(0, +) / Float(spectra.count)
        let avgLowMid = spectra.map { $0.lowMidRatio }.reduce(0, +) / Float(spectra.count)
        let avgMid = spectra.map { $0.midRatio }.reduce(0, +) / Float(spectra.count)
        let avgHighMid = spectra.map { $0.highMidRatio }.reduce(0, +) / Float(spectra.count)
        let avgHigh = spectra.map { $0.highRatio }.reduce(0, +) / Float(spectra.count)
        let avgCrest = spectra.map { $0.crestFactor }.reduce(0, +) / Float(spectra.count)
        
        print("  Avg dB Level:        \(String(format: "%.1f", avgDb)) dB")
        print("  Avg Dominant Freq:   \(String(format: "%.0f", avgDomFreq)) Hz")
        print("  Avg Spectral Centroid: \(String(format: "%.0f", avgCentroid)) Hz")
        print("  Avg Crest Factor:    \(String(format: "%.2f", avgCrest))")
        print("  Energy Distribution:")
        print("    Impact (20-100 Hz):   \(String(format: "%.1f", avgImpact * 100))%")
        print("    LowMid (100-300 Hz):  \(String(format: "%.1f", avgLowMid * 100))%")
        print("    Mid (300-1000 Hz):    \(String(format: "%.1f", avgMid * 100))%")
        print("    HighMid (1-3 kHz):    \(String(format: "%.1f", avgHighMid * 100))%")
        print("    High (3-8 kHz):       \(String(format: "%.1f", avgHigh * 100))%")
    }
    
    private func printSpectrumDetail(_ spectrum: SpectrumData, index: Int) {
        print("  \(index). [\(spectrum.fileName)] @ \(String(format: "%.2f", spectrum.timestamp))s")
        print("     dB: \(String(format: "%.1f", spectrum.dbLevel)), DomFreq: \(String(format: "%.0f", spectrum.dominantFreq)) Hz, Centroid: \(String(format: "%.0f", spectrum.spectralCentroid)) Hz, Crest: \(String(format: "%.2f", spectrum.crestFactor))")
        print("     Impact: \(String(format: "%.0f", spectrum.impactRatio * 100))%, LowMid: \(String(format: "%.0f", spectrum.lowMidRatio * 100))%, Mid: \(String(format: "%.0f", spectrum.midRatio * 100))%, HighMid: \(String(format: "%.0f", spectrum.highMidRatio * 100))%, High: \(String(format: "%.0f", spectrum.highRatio * 100))%")
    }
}
