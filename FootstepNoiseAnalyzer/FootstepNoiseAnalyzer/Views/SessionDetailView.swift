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
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playingEventId: UUID?
    
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
                if !viewModel.events.isEmpty {
                    EditButton()
                }
            }
        }
        .onAppear {
            viewModel.fetchEvents()
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
    }
    
    private var eventList: some View {
        List {
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
                        isPlaying: playingEventId == event.id,
                        onPlayAudio: { playAudio(for: event) },
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
    
    private func playAudio(for event: FootstepEvent) {
        guard let audioURL = event.audioClipURL else { return }
        
        // Stop current playback if any
        audioPlayer?.stop()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.play()
            playingEventId = event.id
            
            // Reset playing state when done
            DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 1.0)) {
                playingEventId = nil
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
}


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
                // Play audio button
                if event.audioClipURL != nil {
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
