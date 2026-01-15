//
//  RecordingView.swift
//  FootstepNoiseAnalyzer
//
//  Main recording view with audio waveform visualization and real-time event indicators.
//  Requirements: 1.1, 1.2, 1.3, 8.1, 8.2, 8.4
//

import SwiftUI

/// Main view for recording audio and displaying real-time analysis feedback
struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status indicator
                    StatusBadge(status: viewModel.statusText, isRecording: viewModel.isRecording)
                    
                    // Duration display
                    Text(viewModel.formattedDuration)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(viewModel.isRecording ? .primary : .secondary)
                    
                    // Audio waveform visualization
                    AudioWaveformView(audioLevel: viewModel.audioLevel, isRecording: viewModel.isRecording)
                        .frame(height: 120)
                        .padding(.horizontal)
                    
                    // Decibel level display
                    DecibelLevelView(audioLevel: viewModel.audioLevel)
                        .padding(.horizontal)
                    
                    // Frequency display
                    FrequencyDisplayView(
                        dominantFrequency: viewModel.dominantFrequency,
                        spectralCentroid: viewModel.spectralCentroid,
                        isRecording: viewModel.isRecording
                    )
                    .padding(.horizontal)
                    
                    // Event counter and last event indicator
                    EventIndicatorView(
                        eventCount: viewModel.eventCount,
                        lastEvent: viewModel.lastDetectedEvent
                    )
                    .padding(.horizontal)
                    
                    // Sensitivity slider
                    SensitivitySliderView(sensitivitySettings: viewModel.sensitivitySettings)
                        .padding(.horizontal)
                    
                    // Recording controls
                    RecordingControlsView(
                        isRecording: viewModel.isRecording,
                        isPaused: viewModel.isPaused,
                        onToggleRecording: viewModel.toggleRecording,
                        onTogglePause: viewModel.togglePause
                    )
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Record")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
}


// MARK: - Sensitivity Slider View

/// Slider for adjusting microphone sensitivity
struct SensitivitySliderView: View {
    @ObservedObject var sensitivitySettings: SensitivitySettings
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.blue)
                Text("Mic Sensitivity")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(sensitivitySettings.sensitivityLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.1")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $sensitivitySettings.sensitivity, in: 0...1, step: 0.05)
                    .tint(.blue)
                
                Image(systemName: "speaker.wave.3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Increase for quieter microphones (e.g., iPad)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Status Badge

/// Displays the current recording status
struct StatusBadge: View {
    let status: String
    let isRecording: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 4)
                        .scaleEffect(isRecording ? 1.5 : 1.0)
                        .opacity(isRecording ? 0 : 1)
                        .animation(
                            isRecording ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                            value: isRecording
                        )
                )
            
            Text(status)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.1))
        .cornerRadius(20)
    }
    
    private var statusColor: Color {
        switch status {
        case "Recording":
            return .red
        case "Paused":
            return .orange
        default:
            return .green
        }
    }
}

// MARK: - Audio Waveform View

/// Displays a visual representation of the audio level
struct AudioWaveformView: View {
    let audioLevel: Float
    let isRecording: Bool
    
    private let barCount = 40
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        height: barHeight(for: index, in: geometry.size.height),
                        isActive: isRecording
                    )
                }
            }
        }
    }
    
    private func barHeight(for index: Int, in maxHeight: CGFloat) -> CGFloat {
        guard isRecording else {
            return maxHeight * 0.1
        }
        
        // Create a wave pattern based on audio level
        let normalizedLevel = CGFloat(min(max(audioLevel, 0), 1))
        let centerIndex = barCount / 2
        let distanceFromCenter = abs(index - centerIndex)
        let falloff = 1.0 - (CGFloat(distanceFromCenter) / CGFloat(centerIndex))
        
        // Add some randomness for visual interest
        let randomFactor = CGFloat.random(in: 0.7...1.0)
        let height = normalizedLevel * falloff * randomFactor * maxHeight
        
        return max(height, maxHeight * 0.05)
    }
}

/// Individual bar in the waveform visualization
struct WaveformBar: View {
    let height: CGFloat
    let isActive: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
            .frame(height: height)
            .animation(.easeInOut(duration: 0.1), value: height)
    }
}

// MARK: - Decibel Level View

/// Displays the current decibel level in approximate dB SPL
struct DecibelLevelView: View {
    let audioLevel: Float
    
    private var decibelSPL: Int {
        // audioLevel is normalized 0-1 based on 30-100 dB SPL range
        // Convert back to dB SPL for display
        guard audioLevel > 0 else { return 30 }
        let minSPL: Float = 30.0
        let maxSPL: Float = 100.0
        let dbSPL = minSPL + (audioLevel * (maxSPL - minSPL))
        return Int(dbSPL)
    }
    
    private var levelColor: Color {
        if decibelSPL > 80 {
            return .red
        } else if decibelSPL > 60 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var levelDescription: String {
        if decibelSPL < 40 {
            return "Quiet"
        } else if decibelSPL < 60 {
            return "Normal"
        } else if decibelSPL < 80 {
            return "Loud"
        } else {
            return "Very Loud"
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Audio Level")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(decibelSPL) dB")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(levelColor)
                Text("(\(levelDescription))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Level meter
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    
                    // Level indicator
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelGradient)
                        .frame(width: levelWidth(in: geometry.size.width))
                        .animation(.easeInOut(duration: 0.1), value: audioLevel)
                }
            }
            .frame(height: 8)
        }
    }
    
    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private func levelWidth(in maxWidth: CGFloat) -> CGFloat {
        let normalizedLevel = CGFloat(min(max(audioLevel, 0), 1))
        return normalizedLevel * maxWidth
    }
}


// MARK: - Event Indicator View

/// Displays the current frequency information
struct FrequencyDisplayView: View {
    let dominantFrequency: Float
    let spectralCentroid: Float
    let isRecording: Bool
    
    private var frequencyBand: String {
        guard isRecording && dominantFrequency > 0 else { return "—" }
        
        if dominantFrequency < 100 {
            return "Sub-bass (Impact)"
        } else if dominantFrequency < 300 {
            return "Low-mid (Heel)"
        } else if dominantFrequency < 1000 {
            return "Mid"
        } else if dominantFrequency < 3000 {
            return "High-mid (Shuffle)"
        } else {
            return "High (Transient)"
        }
    }
    
    private var bandColor: Color {
        guard isRecording && dominantFrequency > 0 else { return .secondary }
        
        if dominantFrequency < 100 {
            return .red
        } else if dominantFrequency < 300 {
            return .orange
        } else if dominantFrequency < 1000 {
            return .yellow
        } else if dominantFrequency < 3000 {
            return .green
        } else {
            return .blue
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Frequency Analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack(spacing: 16) {
                // Dominant frequency
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dominant")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(isRecording && dominantFrequency > 0 ? "\(Int(dominantFrequency)) Hz" : "— Hz")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(bandColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Spectral centroid
                VStack(alignment: .leading, spacing: 4) {
                    Text("Centroid")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(isRecording && spectralCentroid > 0 ? "\(Int(spectralCentroid)) Hz" : "— Hz")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Frequency band
                VStack(alignment: .leading, spacing: 4) {
                    Text("Band")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(frequencyBand)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(bandColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

/// Displays the event count and last detected event
struct EventIndicatorView: View {
    let eventCount: Int
    let lastEvent: FootstepEvent?
    
    var body: some View {
        VStack(spacing: 12) {
            // Event counter
            HStack {
                Image(systemName: "waveform.badge.plus")
                    .foregroundColor(.blue)
                Text("Events Detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(eventCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Last event indicator
            if let event = lastEvent {
                LastEventCard(event: event)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: lastEvent?.id)
    }
}

/// Card displaying the last detected event
struct LastEventCard: View {
    let event: FootstepEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconName(for: event.classification.type))
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(color(for: event.classification.type))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.classification.type.displayName)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("\(Int(event.classification.decibelLevel)) dB")
                        .font(.caption)
                        .foregroundColor(color(for: event.classification.type))
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(event.classification.confidence * 100))% confidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text("Just now")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func iconName(for type: FootstepType) -> String {
        switch type {
        case .mildStomping:
            return "figure.walk"
        case .mediumStomping:
            return "figure.walk"
        case .hardStomping:
            return "figure.walk.circle.fill"
        case .running:
            return "figure.run"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    private func color(for type: FootstepType) -> Color {
        switch type {
        case .mildStomping:
            return .green
        case .mediumStomping:
            return .orange
        case .hardStomping:
            return .red
        case .running:
            return .purple
        case .unknown:
            return .gray
        }
    }
}

// MARK: - Recording Controls View

/// Recording control buttons (record/stop, pause/resume)
struct RecordingControlsView: View {
    let isRecording: Bool
    let isPaused: Bool
    let onToggleRecording: () -> Void
    let onTogglePause: () -> Void
    
    var body: some View {
        HStack(spacing: 40) {
            // Pause/Resume button (only visible when recording)
            if isRecording {
                Button(action: onTogglePause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.orange)
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Record/Stop button
            Button(action: onToggleRecording) {
                ZStack {
                    Circle()
                        .stroke(Color.red, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    if isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }
        }
        .animation(.spring(response: 0.3), value: isRecording)
    }
}

// MARK: - Preview

#Preview {
    RecordingView()
}
