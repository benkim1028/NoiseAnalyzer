//
//  ReportViewModel.swift
//  FootstepNoiseAnalyzer
//
//  ViewModel for managing report generation and export.
//  Requirements: 6.1, 6.3
//

import Foundation
import Combine
import SwiftUI

/// ViewModel for the report view, managing date range selection and report generation.
@MainActor
final class ReportViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Selected report range type
    @Published var selectedRangeType: ReportRangeType = .daily
    
    /// Whether to include audio clips in the report
    @Published var includeAudioClips: Bool = false
    
    /// The generated report (nil if not yet generated)
    @Published private(set) var report: EvidenceReport?
    
    /// Whether a report is currently being generated
    @Published private(set) var isGenerating: Bool = false
    
    /// Whether a PDF is currently being exported
    @Published private(set) var isExporting: Bool = false
    
    /// URL of the exported PDF (for sharing)
    @Published var exportedPDFURL: URL?
    
    /// Whether to show the share sheet
    @Published var showShareSheet: Bool = false
    
    /// Current error message to display
    @Published var errorMessage: String?
    
    /// Whether an error alert should be shown
    @Published var showError: Bool = false
    
    // MARK: - Computed Properties
    
    /// Whether a report has been generated
    var hasReport: Bool {
        report != nil
    }
    
    /// Formatted date range string
    var formattedDateRange: String {
        guard let report = report else {
            return ""
        }
        return "\(dateFormatter.string(from: report.dateRange.lowerBound)) - \(dateFormatter.string(from: report.dateRange.upperBound))"
    }
    
    /// Get the range type from the report
    var rangeType: ReportRangeType {
        report?.rangeType ?? selectedRangeType
    }
    
    /// Number of time slots for the current range type
    var totalTimeSlots: Int {
        rangeType.slotsPerDay
    }
    
    // MARK: - Private Properties
    
    private let reportGenerator: ReportGeneratorProtocol
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    
    // MARK: - Initialization
    
    /// Initialize the view model with a report generator
    /// - Parameter reportGenerator: The report generator to use
    init(reportGenerator: ReportGeneratorProtocol = ReportGenerator.shared) {
        self.reportGenerator = reportGenerator
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .none
        
        self.timeFormatter = DateFormatter()
        self.timeFormatter.dateFormat = "h:mm a"
    }
    
    // MARK: - Public Methods
    
    /// Generate a report for the selected range type
    func generateReport() {
        isGenerating = true
        report = nil
        
        Task {
            do {
                let generatedReport = try await reportGenerator.generateReport(
                    rangeType: selectedRangeType,
                    includeAudioClips: includeAudioClips
                )
                report = generatedReport
                isGenerating = false
            } catch {
                handleError(error)
                isGenerating = false
            }
        }
    }
    
    /// Export the current report to PDF
    func exportToPDF() {
        guard let report = report else {
            errorMessage = "No report to export. Generate a report first."
            showError = true
            return
        }
        
        isExporting = true
        
        Task {
            do {
                let pdfURL = try await reportGenerator.exportToPDF(report)
                exportedPDFURL = pdfURL
                showShareSheet = true
                isExporting = false
            } catch {
                handleError(error)
                isExporting = false
            }
        }
    }
    
    /// Clear the current report
    func clearReport() {
        report = nil
        exportedPDFURL = nil
    }
    
    // MARK: - Report Data Accessors
    
    /// Get the total event count from the report
    var totalEvents: Int {
        report?.totalEvents ?? 0
    }
    
    /// Get events by type from the report
    var eventsByType: [FootstepType: Int] {
        report?.eventsByType ?? [:]
    }
    
    /// Get events by time slot and type from the report
    var eventsByTimeSlotAndType: [Int: [FootstepType: Int]] {
        report?.eventsByTimeSlotAndType ?? [:]
    }
    
    /// Get peak activity times from the report
    var peakActivityTimes: [Date] {
        report?.peakActivityTimes ?? []
    }
    
    /// Format a peak activity time for display
    /// - Parameter date: The date to format
    /// - Returns: Formatted time string
    func formattedPeakTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
    
    /// Get a display string for the footstep type
    /// - Parameter type: The footstep type
    /// - Returns: Human-readable type string
    func displayName(for type: FootstepType) -> String {
        type.displayName
    }
    
    /// Get a color for the footstep type
    /// - Parameter type: The footstep type
    /// - Returns: Color for the type
    func color(for type: FootstepType) -> Color {
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
    
    /// Format a time slot for display
    /// - Parameter slot: The time slot index
    /// - Returns: Formatted time string
    func formattedTimeSlot(_ slot: Int) -> String {
        rangeType.formatSlot(slot)
    }
    
    // MARK: - Private Methods
    
    /// Handle errors from operations
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
