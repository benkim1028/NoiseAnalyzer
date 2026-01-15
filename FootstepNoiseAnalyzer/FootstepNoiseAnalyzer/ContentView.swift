//
//  ContentView.swift
//  FootstepNoiseAnalyzer
//
//  Main content view with tab navigation for Recording, Sessions, and Reports.
//  Requirements: 2.1, 2.2
//

import SwiftUI

/// Main content view with tab-based navigation
struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            RecordingView()
                .tabItem {
                    Label("Record", systemImage: "waveform.circle.fill")
                }
                .tag(0)
            
            SessionListView()
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet.rectangle")
                }
                .tag(1)
            
            ReportView()
                .tabItem {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
