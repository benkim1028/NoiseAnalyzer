//
//  SessionDetailView.swift
//  FootstepNoiseAnalyzer
//
//  Displays detailed event timeline for a recording session.
//  Requirements: 5.3, 5.4, 7.2
//

import SwiftUI
import AVFoundation

/// View displaying detailed events for a specific recording session
struct SessionDetailView: View {
    @StateObject private var viewModel: SessionDetailViewModel
    @State private var showingNoteEditor = false
    @State private var showingShareSheet = false
    
    init(session: RecordingSession) {
        _viewModel = StateObject(wrappedValue: SessionDetailViewModel(session: session))
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading events...")
            } else if viewModel.events.isEmpty {
                EmptyEventsView()
            } else {
                eventList
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.hasAudioFiles {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            viewModel.fetchEvents()
        }
        .onDisappear {
            viewModel.stopAudio()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingNoteEditor) {
            NoteEditorView(
                noteText: $viewModel.editingNoteText,
                onSave: {
                    viewModel.saveNote()
                    showingNoteEditor = false
                },
                onCancel: {
                    viewModel.cancelEditingNote()
                    showingNoteEditor = false
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = viewModel.getAudioFileURL() {
                ShareSheet(items: [url])
            }
        }
    }
    
    private var eventList: some View {
        List {
            // Audio playback section
            if viewModel.hasAudioFiles {
                Section("Recording") {
                    AudioPlayerView(
                        isPlaying: viewModel.isPlayingAudio,
                        progress: viewModel.playbackProgress,
                        timeString: viewModel.playbackTimeString,
                        onPlayPause: { viewModel.togglePlayback() },
                        onSeek: { viewModel.seek(to: $0) }
                    )
                }
            }
            
            // Session summary section
            Section {
                SessionSummaryView(
                    date: viewModel.formattedSessionDate(),
                    duration: viewModel.formattedSessionDuration(),
                    eventCount: viewModel.eventCount
                )
            }
            
            // Events section
            Section("Events Timeline") {
                ForEach(viewModel.events) { event in
                    EventRowView(
                        event: event,
                        formattedTime: viewModel.formattedTime(for: event),
                        typeName: viewModel.displayName(for: event.classification.type),
                        isPlaying: viewModel.isEventPlaying(event),
                        hasSessionAudio: viewModel.hasAudioFiles,
                        onPlayAudio: { viewModel.playEventAudio(for: event) },
                        onAddNote: {
                            viewModel.startEditingNote(for: event)
                            showingNoteEditor = true
                        }
                    )
                }
                .onDelete(perform: viewModel.deleteEvents)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Audio Player View

/// View for playing session audio
struct AudioPlayerView: View {
    let isPlaying: Bool
    let progress: Double
    let timeString: String
    let onPlayPause: () -> Void
    let onSeek: (Double) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress slider
            Slider(value: Binding(
                get: { progress },
                set: { onSeek($0) }
            ), in: 0...1)
            .tint(.blue)
            
            HStack {
                // Play/Pause button
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Time display
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Share Sheet (uses ShareSheet from ReportView.swift)


// MARK: - Empty Events View

/// Displayed when there are no events in the session
struct EmptyEventsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Events Detected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No footstep sounds were detected\nduring this recording session.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Session Summary View

/// Displays session summary information
struct SessionSummaryView: View {
    let date: String
    let duration: String
    let eventCount: Int
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                SummaryItem(
                    icon: "calendar",
                    title: "Date",
                    value: date
                )
                
                Spacer()
                
                SummaryItem(
                    icon: "clock",
                    title: "Duration",
                    value: duration
                )
                
                Spacer()
                
                SummaryItem(
                    icon: "waveform.badge.plus",
                    title: "Events",
                    value: "\(eventCount)"
                )
            }
        }
        .padding(.vertical, 8)
    }
}

/// Individual summary item
struct SummaryItem: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Event Row View

/// Row displaying a single event's details
struct EventRowView: View {
    let event: FootstepEvent
    let formattedTime: String
    let typeName: String
    let isPlaying: Bool
    let hasSessionAudio: Bool
    let onPlayAudio: () -> Void
    let onAddNote: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main event info
            HStack(spacing: 12) {
                // Type icon
                Image(systemName: iconName(for: event.classification.type))
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(color(for: event.classification.type))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(typeName)
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        Text(formattedTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("\(Int(event.classification.decibelLevel)) dB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("\(Int(event.classification.confidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Notes (if any)
            if let notes = event.notes, !notes.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 56)
            }
            
            // Action buttons
            HStack(spacing: 16) {
                // Play audio button (only show if session has audio)
                if hasSessionAudio {
                    Button(action: onPlayAudio) {
                        Label(
                            isPlaying ? "Playing..." : "Play",
                            systemImage: isPlaying ? "speaker.wave.2.fill" : "play.circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(isPlaying ? .green : .blue)
                }
                
                // Add note button
                Button(action: onAddNote) {
                    Label(
                        event.notes != nil ? "Edit Note" : "Add Note",
                        systemImage: "pencil"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.leading, 56)
        }
        .padding(.vertical, 4)
    }
    
    private func iconName(for type: FootstepType) -> String {
        switch type {
        case .mildStomping:
            return "figure.walk"
        case .mediumStomping:
            return "figure.walk"
        case .hardStomping:
            return "figure.walk.circle.fill"
        case .extremeStomping:
            return "figure.walk.diamond.fill"
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
        case .extremeStomping:
            return .purple
        case .running:
            return .blue
        case .unknown:
            return .gray
        }
    }
}

// MARK: - Note Editor View

/// Sheet for editing event notes
struct NoteEditorView: View {
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $noteText)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Event Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SessionDetailView(session: RecordingSession(
            id: UUID(),
            startTime: Date().addingTimeInterval(-3600),
            endTime: Date(),
            eventCount: 5,
            fileURLs: [],
            status: .completed
        ))
    }
}
