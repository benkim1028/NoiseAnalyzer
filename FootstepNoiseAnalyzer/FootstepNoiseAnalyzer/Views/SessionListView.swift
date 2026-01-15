//
//  SessionListView.swift
//  FootstepNoiseAnalyzer
//
//  Displays a list of recording sessions with swipe-to-delete functionality.
//  Requirements: 7.1, 7.3
//

import SwiftUI

/// View displaying all recording sessions
struct SessionListView: View {
    @StateObject private var viewModel = SessionListViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading sessions...")
                } else if viewModel.sessions.isEmpty {
                    EmptySessionsView()
                } else {
                    sessionList
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.sessions.isEmpty {
                        EditButton()
                    }
                }
            }
            .onAppear {
                viewModel.fetchSessions()
            }
            .refreshable {
                viewModel.fetchSessions()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    private var sessionList: some View {
        List {
            ForEach(viewModel.sessions) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionRowView(
                        session: session,
                        formattedDate: viewModel.formattedDate(for: session),
                        formattedDuration: viewModel.formattedDuration(for: session)
                    )
                }
            }
            .onDelete(perform: viewModel.deleteSessions)
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Empty Sessions View

/// Displayed when there are no recording sessions
struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Sessions Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start recording to capture footstep sounds.\nYour sessions will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Session Row View

/// Row displaying a single session's summary
struct SessionRowView: View {
    let session: RecordingSession
    let formattedDate: String
    let formattedDuration: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon
                .frame(width: 44, height: 44)
                .background(statusColor.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label(formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(session.eventCount) events", systemImage: "waveform.badge.plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Event count badge
            if session.eventCount > 0 {
                Text("\(session.eventCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: some View {
        Image(systemName: statusIconName)
            .font(.title3)
            .foregroundColor(statusColor)
    }
    
    private var statusIconName: String {
        switch session.status {
        case .recording:
            return "record.circle"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch session.status {
        case .recording:
            return .red
        case .paused:
            return .orange
        case .completed:
            return .green
        }
    }
}

// MARK: - Preview

#Preview {
    SessionListView()
}
