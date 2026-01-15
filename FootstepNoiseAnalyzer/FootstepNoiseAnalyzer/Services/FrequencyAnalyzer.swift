//
//  FrequencyAnalyzer.swift
//  FootstepNoiseAnalyzer
//
//  Performs FFT-based frequency spectrum analysis on audio buffers.
//

import Foundation
import Accelerate
import AVFoundation

/// Represents the frequency spectrum analysis result.
struct FrequencySpectrum: Equatable {
    /// Energy in the sub-bass/impact band (20-100 Hz)
    let impactEnergy: Float
    
    /// Energy in the low-mid band (100-300 Hz) - heel strikes
    let lowMidEnergy: Float
    
    /// Energy in the mid band (300-1000 Hz)
    let midEnergy: Float
    
    /// Energy in the high-mid band (1000-3000 Hz) - shuffling/scraping
    let highMidEnergy: Float
    
    /// Energy in the high band (3000-8000 Hz) - transients
    let highEnergy: Float
    
    /// Dominant frequency in Hz
    let dominantFrequency: Float
    
    /// Spectral centroid (brightness indicator) in Hz
    let spectralCentroid: Float
}

/// Performs FFT-based frequency analysis on audio buffers.
final class FrequencyAnalyzer {
    
    // MARK: - Private Properties
    
    /// FFT setup for Accelerate framework
    private var fftSetup: vDSP_DFT_Setup?
    
    /// FFT size (must be power of 2)
    private let fftSize: Int
    
    /// Log2 of FFT size for vDSP
    private let log2n: vDSP_Length
    
    /// Sample rate in Hz
    private let sampleRate: Float
    
    /// Frequency resolution (Hz per bin)
    private let frequencyResolution: Float
    
    /// Hanning window for reducing spectral leakage
    private var window: [Float]
    
    // MARK: - Frequency Band Definitions (in Hz)
    
    private let impactBandLow: Float = 20
    private let impactBandHigh: Float = 100
    
    private let lowMidBandLow: Float = 100
    private let lowMidBandHigh: Float = 300
    
    private let midBandLow: Float = 300
    private let midBandHigh: Float = 1000
    
    private let highMidBandLow: Float = 1000
    private let highMidBandHigh: Float = 3000
    
    private let highBandLow: Float = 3000
    private let highBandHigh: Float = 8000
    
    // MARK: - Initialization
    
    /// Initialize the frequency analyzer.
    /// - Parameters:
    ///   - fftSize: Size of FFT (must be power of 2, default 2048)
    ///   - sampleRate: Audio sample rate in Hz (default 44100)
    init(fftSize: Int = 2048, sampleRate: Float = 44100) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.sampleRate = sampleRate
        self.frequencyResolution = sampleRate / Float(fftSize)
        
        // Create Hanning window
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&self.window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Create FFT setup
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // MARK: - Public Methods
    
    /// Analyze the frequency spectrum of an audio buffer.
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: FrequencySpectrum containing band energies and characteristics
    func analyze(buffer: AVAudioPCMBuffer) -> FrequencySpectrum? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }
        
        return analyze(samples: channelData, count: frameCount)
    }
    
    /// Analyze the frequency spectrum of raw audio samples.
    /// - Parameters:
    ///   - samples: Pointer to audio sample data
    ///   - count: Number of samples
    /// - Returns: FrequencySpectrum containing band energies and characteristics
    func analyze(samples: UnsafeMutablePointer<Float>, count: Int) -> FrequencySpectrum? {
        guard let setup = fftSetup else { return nil }
        
        // Use minimum of available samples and FFT size
        let analysisSize = min(count, fftSize)
        
        // Prepare input with windowing
        var windowedInput = [Float](repeating: 0, count: fftSize)
        for i in 0..<analysisSize {
            windowedInput[i] = samples[i] * window[i]
        }

        // Prepare split complex arrays for FFT
        let halfSize = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)
        
        // Convert to split complex format
        windowedInput.withUnsafeBufferPointer { inputPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    
                    // Pack input into split complex
                    inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                    }
                    
                    // Perform FFT
                    vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
        }
        
        // Calculate magnitude spectrum
        var magnitudes = [Float](repeating: 0, count: halfSize)
        realPart.withUnsafeBufferPointer { realPtr in
            imagPart.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        
        // Convert to amplitude (sqrt of magnitude)
        var amplitudes = [Float](repeating: 0, count: halfSize)
        var count = Int32(halfSize)
        vvsqrtf(&amplitudes, magnitudes, &count)
        
        // Normalize
        var scale = Float(2.0 / Float(fftSize))
        vDSP_vsmul(amplitudes, 1, &scale, &amplitudes, 1, vDSP_Length(halfSize))
        
        // Calculate band energies
        let impactEnergy = calculateBandEnergy(amplitudes: amplitudes, lowFreq: impactBandLow, highFreq: impactBandHigh)
        let lowMidEnergy = calculateBandEnergy(amplitudes: amplitudes, lowFreq: lowMidBandLow, highFreq: lowMidBandHigh)
        let midEnergy = calculateBandEnergy(amplitudes: amplitudes, lowFreq: midBandLow, highFreq: midBandHigh)
        let highMidEnergy = calculateBandEnergy(amplitudes: amplitudes, lowFreq: highMidBandLow, highFreq: highMidBandHigh)
        let highEnergy = calculateBandEnergy(amplitudes: amplitudes, lowFreq: highBandLow, highFreq: highBandHigh)
        
        // Find dominant frequency
        let dominantFrequency = findDominantFrequency(amplitudes: amplitudes)
        
        // Calculate spectral centroid
        let spectralCentroid = calculateSpectralCentroid(amplitudes: amplitudes)
        
        return FrequencySpectrum(
            impactEnergy: impactEnergy,
            lowMidEnergy: lowMidEnergy,
            midEnergy: midEnergy,
            highMidEnergy: highMidEnergy,
            highEnergy: highEnergy,
            dominantFrequency: dominantFrequency,
            spectralCentroid: spectralCentroid
        )
    }
    
    // MARK: - Private Methods
    
    /// Calculate the energy in a specific frequency band.
    private func calculateBandEnergy(amplitudes: [Float], lowFreq: Float, highFreq: Float) -> Float {
        let lowBin = max(0, Int(lowFreq / frequencyResolution))
        let highBin = min(amplitudes.count - 1, Int(highFreq / frequencyResolution))
        
        guard lowBin < highBin else { return 0 }
        
        var energy: Float = 0
        for i in lowBin...highBin {
            energy += amplitudes[i] * amplitudes[i]
        }
        
        // Normalize by number of bins
        return sqrt(energy / Float(highBin - lowBin + 1))
    }
    
    /// Find the dominant (peak) frequency in the spectrum.
    private func findDominantFrequency(amplitudes: [Float]) -> Float {
        guard !amplitudes.isEmpty else { return 0 }
        
        var maxAmplitude: Float = 0
        var maxIndex: Int = 0
        
        // Skip DC component (index 0) and very low frequencies
        let startBin = max(1, Int(20 / frequencyResolution))
        
        for i in startBin..<amplitudes.count {
            if amplitudes[i] > maxAmplitude {
                maxAmplitude = amplitudes[i]
                maxIndex = i
            }
        }
        
        return Float(maxIndex) * frequencyResolution
    }
    
    /// Calculate the spectral centroid (center of mass of the spectrum).
    /// Higher values indicate brighter/higher frequency content.
    private func calculateSpectralCentroid(amplitudes: [Float]) -> Float {
        var weightedSum: Float = 0
        var totalAmplitude: Float = 0
        
        for i in 0..<amplitudes.count {
            let frequency = Float(i) * frequencyResolution
            weightedSum += frequency * amplitudes[i]
            totalAmplitude += amplitudes[i]
        }
        
        guard totalAmplitude > 0 else { return 0 }
        return weightedSum / totalAmplitude
    }
}
