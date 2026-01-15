//
//  ReportView.swift
//  FootstepNoiseAnalyzer
//
//  Displays report generation interface with date range picker and statistics.
//  Requirements: 6.1, 6.2, 6.3
//

import SwiftUI
import Charts

/// View for generating and viewing evidence reports
struct ReportView: View {
    @StateObject private var viewModel = ReportViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Range type selection
                    RangeTypeSection(selectedRangeType: $viewModel.selectedRangeType)
                    
                    // Options
                    OptionsSection(includeAudioClips: $viewModel.includeAudioClips)
                    
                    // Generate button
                    GenerateButton(
                        isGenerating: viewModel.isGenerating,
                        onGenerate: viewModel.generateReport
                    )
                    
                    // Report content (if generated)
                    if viewModel.hasReport {
                        ReportContentSection(
                            viewModel: viewModel,
                            onExportPDF: viewModel.exportToPDF
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Reports")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let url = viewModel.exportedPDFURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
}

// MARK: - Range Type Section

/// Section for selecting the report range type
struct RangeTypeSection: View {
    @Binding var selectedRangeType: ReportRangeType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Report Period")
                .font(.headline)
            
            Picker("Range Type", selection: $selectedRangeType) {
                ForEach(ReportRangeType.allCases, id: \.self) { rangeType in
                    Text(rangeType.rawValue).tag(rangeType)
                }
            }
            .pickerStyle(.segmented)
            
            // Description of the selected range
            Text(rangeDescription(for: selectedRangeType))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }
    
    private func rangeDescription(for rangeType: ReportRangeType) -> String {
        switch rangeType {
        case .daily:
            return "Today (12:00 AM - 11:59 PM) • Events by 10-minute intervals"
        case .weekly:
            return "This week (Sunday - Saturday) • Events by 30-minute intervals"
        case .biweekly:
            return "Last 2 weeks (Sunday - Saturday) • Events by hour"
        }
    }
}

// MARK: - Options Section

/// Section for report options
struct OptionsSection: View {
    @Binding var includeAudioClips: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Include Audio Clip References", isOn: $includeAudioClips)
                
                Text("Shows audio file references in the PDF when available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Generate Button

/// Button to generate the report
struct GenerateButton: View {
    let isGenerating: Bool
    let onGenerate: () -> Void
    
    var body: some View {
        Button(action: onGenerate) {
            HStack {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Text(isGenerating ? "Generating..." : "Generate Report")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isGenerating)
    }
}

// MARK: - Report Content Section

/// Section displaying the generated report content
struct ReportContentSection: View {
    @ObservedObject var viewModel: ReportViewModel
    let onExportPDF: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Summary statistics
            SummaryStatsView(
                totalEvents: viewModel.totalEvents,
                dateRange: viewModel.formattedDateRange,
                rangeType: viewModel.rangeType.rawValue
            )
            
            // Events by type chart
            if !viewModel.eventsByType.isEmpty {
                EventsByTypeChart(
                    eventsByType: viewModel.eventsByType,
                    displayName: viewModel.displayName,
                    color: viewModel.color
                )
            }
            
            // Events by time slot chart (stacked by type)
            if !viewModel.eventsByTimeSlotAndType.isEmpty {
                EventsByTimeSlotChart(
                    eventsByTimeSlotAndType: viewModel.eventsByTimeSlotAndType,
                    rangeType: viewModel.rangeType,
                    formattedTimeSlot: viewModel.formattedTimeSlot,
                    color: viewModel.color
                )
            }
            
            // Peak activity times
            if !viewModel.peakActivityTimes.isEmpty {
                PeakActivityView(
                    peakTimes: viewModel.peakActivityTimes,
                    formattedTime: viewModel.formattedPeakTime
                )
            }
            
            // Export button
            ExportButton(
                isExporting: viewModel.isExporting,
                onExport: onExportPDF
            )
        }
    }
}

// MARK: - Summary Stats View

/// Displays summary statistics
struct SummaryStatsView: View {
    let totalEvents: Int
    let dateRange: String
    let rangeType: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)
            
            HStack {
                StatCard(title: "Total Events", value: "\(totalEvents)", icon: "waveform.badge.plus")
                StatCard(title: "Period", value: rangeType, icon: "calendar")
            }
            
            Text(dateRange)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

/// Individual stat card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Events By Type Chart

/// Chart showing distribution of events by type
struct EventsByTypeChart: View {
    let eventsByType: [FootstepType: Int]
    let displayName: (FootstepType) -> String
    let color: (FootstepType) -> Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Events by Type")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(eventsByType.keys.sorted { eventsByType[$0]! > eventsByType[$1]! }), id: \.self) { type in
                        BarMark(
                            x: .value("Count", eventsByType[type] ?? 0),
                            y: .value("Type", displayName(type))
                        )
                        .foregroundStyle(color(type))
                    }
                }
                .frame(height: CGFloat(eventsByType.count * 40 + 20))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                // Fallback for iOS 15
                VStack(spacing: 8) {
                    ForEach(Array(eventsByType.keys.sorted { eventsByType[$0]! > eventsByType[$1]! }), id: \.self) { type in
                        HStack {
                            Text(displayName(type))
                                .font(.caption)
                                .frame(width: 80, alignment: .leading)
                            
                            GeometryReader { geometry in
                                let maxCount = eventsByType.values.max() ?? 1
                                let width = CGFloat(eventsByType[type] ?? 0) / CGFloat(maxCount) * geometry.size.width
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color(type))
                                    .frame(width: max(width, 4))
                            }
                            .frame(height: 20)
                            
                            Text("\(eventsByType[type] ?? 0)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Events By Time Slot Chart

/// Chart showing distribution of events by time slot with stacked bars by type
struct EventsByTimeSlotChart: View {
    let eventsByTimeSlotAndType: [Int: [FootstepType: Int]]
    let rangeType: ReportRangeType
    let formattedTimeSlot: (Int) -> String
    let color: (FootstepType) -> Color
    
    /// Type order for consistent stacking
    private let typeOrder: [FootstepType] = [.mildStomping, .mediumStomping, .hardStomping, .running, .unknown]
    
    /// Calculate max total for scaling
    private var maxTotal: Int {
        var max = 0
        for slot in 0..<rangeType.slotsPerDay {
            let slotData = eventsByTimeSlotAndType[slot] ?? [:]
            let total = slotData.values.reduce(0, +)
            if total > max { max = total }
        }
        return max > 0 ? max : 1
    }
    
    private var chartTitle: String {
        switch rangeType {
        case .daily:
            return "Events by Time (10 min intervals)"
        case .weekly:
            return "Events by Time (30 min intervals)"
        case .biweekly:
            return "Events by Hour"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chartTitle)
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(0..<rangeType.slotsPerDay, id: \.self) { slot in
                        let slotData = eventsByTimeSlotAndType[slot] ?? [:]
                        ForEach(typeOrder, id: \.self) { type in
                            let count = slotData[type] ?? 0
                            if count > 0 {
                                BarMark(
                                    x: .value("Time", formattedTimeSlot(slot)),
                                    y: .value("Count", count)
                                )
                                .foregroundStyle(color(type))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Legend
                HStack(spacing: 12) {
                    ForEach([FootstepType.mildStomping, .mediumStomping, .hardStomping, .running], id: \.self) { type in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color(type))
                                .frame(width: 8, height: 8)
                            Text(type.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                // Fallback for iOS 15
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<rangeType.slotsPerDay, id: \.self) { slot in
                            let slotData = eventsByTimeSlotAndType[slot] ?? [:]
                            
                            VStack(spacing: 0) {
                                // Stacked bars
                                VStack(spacing: 0) {
                                    ForEach(typeOrder.reversed(), id: \.self) { type in
                                        let count = slotData[type] ?? 0
                                        if count > 0 {
                                            let height = CGFloat(count) / CGFloat(maxTotal) * 100
                                            Rectangle()
                                                .fill(color(type))
                                                .frame(width: 8, height: height)
                                        }
                                    }
                                }
                                .frame(height: 100, alignment: .bottom)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Peak Activity View

/// Displays peak activity times
struct PeakActivityView: View {
    let peakTimes: [Date]
    let formattedTime: (Date) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peak Activity Times")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(Array(peakTimes.enumerated()), id: \.offset) { index, time in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(rankColor(for: index))
                            .cornerRadius(12)
                        
                        Text(formattedTime(time))
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Image(systemName: "clock.fill")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0:
            return .red
        case 1:
            return .orange
        case 2:
            return .yellow
        default:
            return .gray
        }
    }
}

// MARK: - Export Button

/// Button to export report as PDF
struct ExportButton: View {
    let isExporting: Bool
    let onExport: () -> Void
    
    var body: some View {
        Button(action: onExport) {
            HStack {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Image(systemName: "square.and.arrow.up")
                Text(isExporting ? "Exporting..." : "Export as PDF")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isExporting)
    }
}

// MARK: - Share Sheet

/// UIKit share sheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ReportView()
}
