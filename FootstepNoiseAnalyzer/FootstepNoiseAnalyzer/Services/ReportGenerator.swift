//
//  ReportGenerator.swift
//  FootstepNoiseAnalyzer
//
//  Generates evidence reports with statistics and visualizations for footstep events.
//  Requirements: 6.1, 6.3
//

import Foundation
import UIKit

/// Report date range type determining time granularity
enum ReportRangeType: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    
    /// Time interval in minutes for grouping events
    var intervalMinutes: Int {
        switch self {
        case .daily: return 10
        case .weekly: return 30
        case .biweekly: return 60
        }
    }
    
    /// Number of time slots in a day
    var slotsPerDay: Int {
        return 24 * 60 / intervalMinutes
    }
    
    /// Number of days in this range
    var days: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .biweekly: return 14
        }
    }
    
    /// Format label for a time slot
    func formatSlot(_ slot: Int) -> String {
        let totalMinutes = slot * intervalMinutes
        let hour = totalMinutes / 60
        let minute = totalMinutes % 60
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        
        if minute == 0 {
            return "\(displayHour)\(period)"
        } else {
            return "\(displayHour):\(String(format: "%02d", minute))"
        }
    }
}

/// Represents a generated evidence report with statistics and event data
struct EvidenceReport: Equatable {
    /// The date range covered by this report
    let dateRange: ClosedRange<Date>
    
    /// The range type used for this report
    let rangeType: ReportRangeType
    
    /// Total number of events in the report
    let totalEvents: Int
    
    /// Distribution of events by footstep type
    let eventsByType: [FootstepType: Int]
    
    /// Distribution of events by time slot and type (slot -> type -> count)
    let eventsByTimeSlotAndType: [Int: [FootstepType: Int]]
    
    /// Times when peak activity occurred
    let peakActivityTimes: [Date]
    
    /// The events included in this report
    let events: [FootstepEvent]
    
    /// When this report was generated
    let generatedAt: Date
}

/// Errors that can occur during report generation
enum ReportGeneratorError: Error, LocalizedError {
    case fetchFailed(underlying: Error)
    case pdfGenerationFailed(underlying: Error)
    case invalidDateRange
    case noEventsFound
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed(let error):
            return "Failed to fetch events for report: \(error.localizedDescription)"
        case .pdfGenerationFailed(let error):
            return "Failed to generate PDF: \(error.localizedDescription)"
        case .invalidDateRange:
            return "Invalid date range specified"
        case .noEventsFound:
            return "No events found in the specified date range"
        }
    }
}


/// Protocol defining report generation operations
protocol ReportGeneratorProtocol {
    /// Generates an evidence report for the specified range type
    /// - Parameters:
    ///   - rangeType: The type of date range (daily, weekly, biweekly)
    ///   - includeAudioClips: Whether to include audio clip references in the report
    /// - Returns: The generated evidence report
    func generateReport(rangeType: ReportRangeType, includeAudioClips: Bool) async throws -> EvidenceReport
    
    /// Exports a report to PDF format
    /// - Parameter report: The report to export
    /// - Returns: URL to the generated PDF file
    func exportToPDF(_ report: EvidenceReport) async throws -> URL
}

/// Report generator implementation
class ReportGenerator: ReportGeneratorProtocol {
    
    /// Shared instance for app-wide use
    static let shared = ReportGenerator()
    
    /// The event service for fetching events
    private let eventService: EventServiceProtocol    
    /// Date formatter for report display
    private let dateFormatter: DateFormatter
    
    /// Time formatter for hour display
    private let timeFormatter: DateFormatter
    
    /// Initializes the report generator with dependencies
    /// - Parameter eventService: The event service to use for fetching events
    init(eventService: EventServiceProtocol = EventService.shared) {
        self.eventService = eventService
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .short
        
        self.timeFormatter = DateFormatter()
        self.timeFormatter.dateFormat = "h:mm a"
    }
    
    // MARK: - ReportGeneratorProtocol Implementation
    
    /// Generates an evidence report for the specified range type
    /// - Parameters:
    ///   - rangeType: The type of date range (daily, weekly, biweekly)
    ///   - includeAudioClips: Whether to include audio clip references in the report
    /// - Returns: The generated evidence report
    func generateReport(rangeType: ReportRangeType, includeAudioClips: Bool) async throws -> EvidenceReport {
        // Calculate calendar-aligned date range based on range type
        let (from, to) = calculateDateRange(for: rangeType)
        
        // Fetch events for the date range
        let events: [FootstepEvent]
        do {
            events = try await eventService.fetchEvents(from: from, to: to)
        } catch {
            throw ReportGeneratorError.fetchFailed(underlying: error)
        }
        
        // Calculate statistics
        let eventsByType = calculateEventsByType(events)
        let eventsByTimeSlotAndType = calculateEventsByTimeSlotAndType(events, rangeType: rangeType)
        let peakActivityTimes = calculatePeakActivityTimes(eventsByTimeSlot: eventsByTimeSlotAndType, rangeType: rangeType, referenceDate: from)
        
        // Process events based on includeAudioClips flag
        let reportEvents = includeAudioClips ? events : events.map { $0.withoutAudioClip() }
        
        return EvidenceReport(
            dateRange: from...to,
            rangeType: rangeType,
            totalEvents: events.count,
            eventsByType: eventsByType,
            eventsByTimeSlotAndType: eventsByTimeSlotAndType,
            peakActivityTimes: peakActivityTimes,
            events: reportEvents,
            generatedAt: Date()
        )
    }
    
    // MARK: - Date Range Calculation
    
    /// Calculates the calendar-aligned date range for a report type
    /// - Parameter rangeType: The type of date range
    /// - Returns: Tuple of (start date at 12:00 AM, end date at 11:59:59 PM)
    private func calculateDateRange(for rangeType: ReportRangeType) -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch rangeType {
        case .daily:
            // Today: 12:00 AM to 11:59:59 PM
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: startOfDay) ?? now
            return (startOfDay, endOfDay)
            
        case .weekly:
            // This week: Sunday 12:00 AM to Saturday 11:59:59 PM
            let weekday = calendar.component(.weekday, from: now)
            let daysFromSunday = weekday - 1 // Sunday = 1
            let startOfWeek = calendar.date(byAdding: .day, value: -daysFromSunday, to: calendar.startOfDay(for: now)) ?? now
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? now
            let endOfWeekNight = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfWeek) ?? now
            return (startOfWeek, endOfWeekNight)
            
        case .biweekly:
            // This week and last week: Previous Sunday 12:00 AM to this Saturday 11:59:59 PM
            let weekday = calendar.component(.weekday, from: now)
            let daysFromSunday = weekday - 1
            let startOfThisWeek = calendar.date(byAdding: .day, value: -daysFromSunday, to: calendar.startOfDay(for: now)) ?? now
            let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfThisWeek) ?? now
            let endOfThisWeek = calendar.date(byAdding: .day, value: 6, to: startOfThisWeek) ?? now
            let endOfThisWeekNight = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfThisWeek) ?? now
            return (startOfLastWeek, endOfThisWeekNight)
        }
    }

    
    /// Exports a report to PDF format
    /// - Parameter report: The report to export
    /// - Returns: URL to the generated PDF file
    func exportToPDF(_ report: EvidenceReport) async throws -> URL {
        // Generate PDF data
        let pdfData = generatePDFData(for: report)
        
        // Create file URL in documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "FootstepReport_\(formatDateForFileName(report.generatedAt)).pdf"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        // Write PDF to file
        do {
            try pdfData.write(to: fileURL)
            return fileURL
        } catch {
            throw ReportGeneratorError.pdfGenerationFailed(underlying: error)
        }
    }
    
    // MARK: - Statistics Calculation
    
    /// Calculates the distribution of events by footstep type
    /// - Parameter events: The events to analyze
    /// - Returns: Dictionary mapping footstep types to their counts
    func calculateEventsByType(_ events: [FootstepEvent]) -> [FootstepType: Int] {
        var distribution: [FootstepType: Int] = [:]
        
        for event in events {
            let type = event.classification.type
            distribution[type, default: 0] += 1
        }
        
        return distribution
    }
    
    /// Calculates the distribution of events by time slot and type
    /// - Parameters:
    ///   - events: The events to analyze
    ///   - rangeType: The range type determining slot size
    /// - Returns: Dictionary mapping time slots to type distributions
    func calculateEventsByTimeSlotAndType(_ events: [FootstepEvent], rangeType: ReportRangeType) -> [Int: [FootstepType: Int]] {
        var distribution: [Int: [FootstepType: Int]] = [:]
        let calendar = Calendar.current
        
        for event in events {
            let hour = calendar.component(.hour, from: event.timestamp)
            let minute = calendar.component(.minute, from: event.timestamp)
            let totalMinutes = hour * 60 + minute
            let slot = totalMinutes / rangeType.intervalMinutes
            let type = event.classification.type
            
            if distribution[slot] == nil {
                distribution[slot] = [:]
            }
            distribution[slot]![type, default: 0] += 1
        }
        
        return distribution
    }
    
    /// Identifies peak activity times based on time slot distribution
    /// - Parameters:
    ///   - eventsByTimeSlot: The time slot event distribution
    ///   - rangeType: The range type for slot interpretation
    ///   - referenceDate: A reference date to construct peak time dates
    /// - Returns: Array of dates representing peak activity times (top 3 slots)
    func calculatePeakActivityTimes(eventsByTimeSlot: [Int: [FootstepType: Int]], rangeType: ReportRangeType, referenceDate: Date) -> [Date] {
        let calendar = Calendar.current
        
        // Calculate total events per slot
        let slotTotals = eventsByTimeSlot.mapValues { $0.values.reduce(0, +) }
        
        // Sort slots by event count (descending) and take top 3
        let peakSlots = slotTotals
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        
        // Convert slots to dates using reference date
        return peakSlots.compactMap { slot in
            let totalMinutes = slot * rangeType.intervalMinutes
            let hour = totalMinutes / 60
            let minute = totalMinutes % 60
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: referenceDate)
        }
    }

    
    // MARK: - PDF Generation
    
    /// Generates PDF data for a report
    /// - Parameter report: The report to convert to PDF
    /// - Returns: The PDF data
    private func generatePDFData(for report: EvidenceReport) -> Data {
        let pageWidth: CGFloat = 612  // US Letter width in points
        let pageHeight: CGFloat = 792 // US Letter height in points
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)
        
        let pdfMetaData = [
            kCGPDFContextCreator: "Footstep Noise Analyzer",
            kCGPDFContextAuthor: "Footstep Noise Analyzer App",
            kCGPDFContextTitle: "Footstep Evidence Report"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yPosition: CGFloat = margin
            
            // Title
            yPosition = drawTitle("Footstep Evidence Report", at: yPosition, width: contentWidth, margin: margin)
            yPosition += 20
            
            // Date range and type
            let rangeTypeText = "Report Type: \(report.rangeType.rawValue)"
            yPosition = drawText(rangeTypeText, at: yPosition, width: contentWidth, margin: margin, fontSize: 12)
            
            let dateRangeText = "Report Period: \(dateFormatter.string(from: report.dateRange.lowerBound)) - \(dateFormatter.string(from: report.dateRange.upperBound))"
            yPosition = drawText(dateRangeText, at: yPosition, width: contentWidth, margin: margin, fontSize: 12)
            
            // Generated date
            let generatedText = "Generated: \(dateFormatter.string(from: report.generatedAt))"
            yPosition = drawText(generatedText, at: yPosition, width: contentWidth, margin: margin, fontSize: 12)
            yPosition += 20
            
            // Summary section
            yPosition = drawSectionHeader("Summary", at: yPosition, width: contentWidth, margin: margin)
            yPosition = drawText("Total Events: \(report.totalEvents)", at: yPosition, width: contentWidth, margin: margin, fontSize: 12)
            yPosition += 20
            
            // Events by Type Chart
            if !report.eventsByType.isEmpty {
                yPosition = drawEventsByTypeChart(report.eventsByType, at: yPosition, width: contentWidth, margin: margin)
                yPosition += 25
            }
            
            // Check if we need a new page for the time slot chart
            if yPosition > pageHeight - 280 {
                context.beginPage()
                yPosition = margin
            }
            
            // Events by Time Slot Chart (stacked by type)
            if !report.eventsByTimeSlotAndType.isEmpty {
                yPosition = drawEventsByTimeSlotChart(report.eventsByTimeSlotAndType, rangeType: report.rangeType, at: yPosition, width: contentWidth, margin: margin)
                yPosition += 25
            }
            
            // Check if we need a new page for peak activity
            if yPosition > pageHeight - 180 {
                context.beginPage()
                yPosition = margin
            }
            
            // Peak Activity Times Chart
            if !report.peakActivityTimes.isEmpty {
                yPosition = drawPeakActivityChart(report.peakActivityTimes, at: yPosition, width: contentWidth, margin: margin)
                yPosition += 25
            }
            
            // Events list (if there's room, otherwise start new page)
            if yPosition > pageHeight - 200 {
                context.beginPage()
                yPosition = margin
            }
            
            yPosition = drawSectionHeader("Event Details", at: yPosition, width: contentWidth, margin: margin)
            
            for (index, event) in report.events.prefix(50).enumerated() {
                // Check if we need a new page
                if yPosition > pageHeight - 80 {
                    context.beginPage()
                    yPosition = margin
                }
                
                let eventText = "\(index + 1). \(dateFormatter.string(from: event.timestamp)) - \(event.classification.type.displayName) (\(Int(event.classification.decibelLevel)) dB, \(Int(event.classification.confidence * 100))% confidence)"
                yPosition = drawText(eventText, at: yPosition, width: contentWidth, margin: margin, fontSize: 10)
                
                if let notes = event.notes, !notes.isEmpty {
                    yPosition = drawText("   Notes: \(notes)", at: yPosition, width: contentWidth, margin: margin, fontSize: 9, color: .darkGray)
                }
            }
            
            if report.events.count > 50 {
                yPosition += 10
                yPosition = drawText("... and \(report.events.count - 50) more events", at: yPosition, width: contentWidth, margin: margin, fontSize: 10, color: .gray)
            }
        }
        
        return data
    }
    
    // MARK: - Chart Drawing Methods
    
    /// Draws a horizontal bar chart for events by type
    private func drawEventsByTypeChart(_ eventsByType: [FootstepType: Int], at yPosition: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var currentY = drawSectionHeader("Events by Type", at: yPosition, width: width, margin: margin)
        
        let chartHeight: CGFloat = 120
        let chartRect = CGRect(x: margin, y: currentY, width: width, height: chartHeight)
        
        // Draw chart background
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: chartRect, cornerRadius: 8).fill()
        
        // Sort types by count descending
        let sortedTypes = eventsByType.sorted { $0.value > $1.value }
        let maxCount = sortedTypes.first?.value ?? 1
        
        let barHeight: CGFloat = 18
        let barSpacing: CGFloat = 8
        let labelWidth: CGFloat = 100
        let countWidth: CGFloat = 40
        let chartPadding: CGFloat = 10
        let barAreaWidth = width - labelWidth - countWidth - (chartPadding * 2)
        
        var barY = currentY + chartPadding
        
        for (type, count) in sortedTypes {
            // Draw label
            let labelRect = CGRect(x: margin + chartPadding, y: barY, width: labelWidth - 10, height: barHeight)
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            type.displayName.draw(in: labelRect, withAttributes: labelAttributes)
            
            // Draw bar
            let barWidth = CGFloat(count) / CGFloat(maxCount) * barAreaWidth
            let barRect = CGRect(x: margin + labelWidth, y: barY + 2, width: max(barWidth, 4), height: barHeight - 4)
            colorForType(type).setFill()
            UIBezierPath(roundedRect: barRect, cornerRadius: 4).fill()
            
            // Draw count
            let countRect = CGRect(x: margin + labelWidth + barAreaWidth + 5, y: barY, width: countWidth, height: barHeight)
            let countAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            "\(count)".draw(in: countRect, withAttributes: countAttributes)
            
            barY += barHeight + barSpacing
        }
        
        return currentY + chartHeight + 10
    }
    
    /// Draws a vertical stacked bar chart for events by time slot and type
    private func drawEventsByTimeSlotChart(_ eventsByTimeSlotAndType: [Int: [FootstepType: Int]], rangeType: ReportRangeType, at yPosition: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let intervalLabel = rangeType == .daily ? "10 min" : (rangeType == .weekly ? "30 min" : "Hour")
        var currentY = drawSectionHeader("Events by Time (\(intervalLabel) intervals)", at: yPosition, width: width, margin: margin)
        
        let chartHeight: CGFloat = 200
        let chartRect = CGRect(x: margin, y: currentY, width: width, height: chartHeight)
        
        // Draw chart background
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: chartRect, cornerRadius: 8).fill()
        
        let chartPadding: CGFloat = 15
        let labelHeight: CGFloat = 20
        let legendHeight: CGFloat = 25
        let barAreaHeight = chartHeight - (chartPadding * 2) - labelHeight - legendHeight
        
        let totalSlots = rangeType.slotsPerDay
        let barWidth: CGFloat = (width - (chartPadding * 2)) / CGFloat(totalSlots) - 1
        
        // Calculate max total count for any slot
        var maxCount = 0
        for slot in 0..<totalSlots {
            let slotData = eventsByTimeSlotAndType[slot] ?? [:]
            let total = slotData.values.reduce(0, +)
            maxCount = max(maxCount, total)
        }
        if maxCount == 0 { maxCount = 1 }
        
        // Define type order for consistent stacking (bottom to top)
        let typeOrder: [FootstepType] = [.mildStomping, .mediumStomping, .hardStomping, .running, .unknown]
        
        // Determine label interval based on range type
        let labelInterval: Int
        switch rangeType {
        case .daily: labelInterval = 6  // Every hour (6 x 10min slots)
        case .weekly: labelInterval = 4  // Every 2 hours (4 x 30min slots)
        case .biweekly: labelInterval = 4  // Every 4 hours
        }
        
        for slot in 0..<totalSlots {
            let slotData = eventsByTimeSlotAndType[slot] ?? [:]
            
            let barX = margin + chartPadding + CGFloat(slot) * (barWidth + 1)
            var currentBarY = currentY + chartPadding + barAreaHeight // Start from bottom
            
            // Draw stacked segments for each type
            for type in typeOrder {
                let count = slotData[type] ?? 0
                if count > 0 {
                    let segmentHeight = CGFloat(count) / CGFloat(maxCount) * barAreaHeight
                    currentBarY -= segmentHeight
                    
                    let segmentRect = CGRect(x: barX, y: currentBarY, width: barWidth, height: segmentHeight)
                    colorForType(type).setFill()
                    UIBezierPath(roundedRect: segmentRect, cornerRadius: 1).fill()
                }
            }
            
            // Draw time label at intervals
            if slot % labelInterval == 0 {
                let labelRect = CGRect(x: barX - 10, y: currentY + chartHeight - labelHeight - legendHeight - 5, width: 40, height: labelHeight)
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 7),
                    .foregroundColor: UIColor.darkGray
                ]
                rangeType.formatSlot(slot).draw(in: labelRect, withAttributes: labelAttributes)
            }
        }
        
        // Draw legend at bottom
        let legendY = currentY + chartHeight - legendHeight
        let legendTypes: [FootstepType] = [.mildStomping, .mediumStomping, .hardStomping, .running]
        let legendItemWidth = (width - chartPadding * 2) / CGFloat(legendTypes.count)
        
        for (index, type) in legendTypes.enumerated() {
            let itemX = margin + chartPadding + CGFloat(index) * legendItemWidth
            
            // Color box
            let boxRect = CGRect(x: itemX, y: legendY + 5, width: 10, height: 10)
            colorForType(type).setFill()
            UIBezierPath(roundedRect: boxRect, cornerRadius: 2).fill()
            
            // Label
            let labelRect = CGRect(x: itemX + 14, y: legendY + 3, width: legendItemWidth - 18, height: 15)
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7),
                .foregroundColor: UIColor.darkGray
            ]
            type.displayName.draw(in: labelRect, withAttributes: labelAttributes)
        }
        
        return currentY + chartHeight + 10
    }
    
    /// Draws the peak activity times section with visual ranking
    private func drawPeakActivityChart(_ peakTimes: [Date], at yPosition: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var currentY = drawSectionHeader("Peak Activity Times", at: yPosition, width: width, margin: margin)
        
        let itemHeight: CGFloat = 35
        let chartHeight = CGFloat(peakTimes.count) * itemHeight + 20
        let chartRect = CGRect(x: margin, y: currentY, width: width, height: chartHeight)
        
        // Draw chart background
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: chartRect, cornerRadius: 8).fill()
        
        let chartPadding: CGFloat = 10
        var itemY = currentY + chartPadding
        
        for (index, time) in peakTimes.enumerated() {
            // Draw rank badge
            let badgeSize: CGFloat = 24
            let badgeRect = CGRect(x: margin + chartPadding, y: itemY + 5, width: badgeSize, height: badgeSize)
            rankColor(for: index).setFill()
            UIBezierPath(ovalIn: badgeRect).fill()
            
            // Draw rank number
            let rankAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.white
            ]
            let rankText = "#\(index + 1)"
            let rankSize = rankText.size(withAttributes: rankAttributes)
            let rankRect = CGRect(
                x: badgeRect.midX - rankSize.width / 2,
                y: badgeRect.midY - rankSize.height / 2,
                width: rankSize.width,
                height: rankSize.height
            )
            rankText.draw(in: rankRect, withAttributes: rankAttributes)
            
            // Draw time
            let timeText = timeFormatter.string(from: time)
            let timeRect = CGRect(x: margin + chartPadding + badgeSize + 15, y: itemY + 8, width: 100, height: 20)
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]
            timeText.draw(in: timeRect, withAttributes: timeAttributes)
            
            // Draw clock icon (using text as placeholder)
            let clockRect = CGRect(x: margin + width - chartPadding - 30, y: itemY + 8, width: 20, height: 20)
            let clockAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.gray
            ]
            "🕐".draw(in: clockRect, withAttributes: clockAttributes)
            
            itemY += itemHeight
        }
        
        return currentY + chartHeight + 10
    }
    
    /// Returns the color for a footstep type
    private func colorForType(_ type: FootstepType) -> UIColor {
        switch type {
        case .mildStomping:
            return .systemGreen
        case .mediumStomping:
            return .systemOrange
        case .hardStomping:
            return .systemRed
        case .running:
            return .systemPurple
        case .unknown:
            return .systemGray
        }
    }
    
    /// Returns the color for a rank position
    private func rankColor(for index: Int) -> UIColor {
        switch index {
        case 0:
            return .systemRed
        case 1:
            return .systemOrange
        case 2:
            return .systemYellow
        default:
            return .systemGray
        }
    }
    
    /// Formats an hour value for display
    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour)\(period)"
    }

    
    // MARK: - PDF Drawing Helpers
    
    /// Draws a title at the specified position
    private func drawTitle(_ text: String, at yPosition: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: 24)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: margin, y: yPosition, width: width, height: 30)
        attributedString.draw(in: textRect)
        
        return yPosition + 35
    }
    
    /// Draws a section header at the specified position
    private func drawSectionHeader(_ text: String, at yPosition: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: 14)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: margin, y: yPosition, width: width, height: 20)
        attributedString.draw(in: textRect)
        
        return yPosition + 22
    }
    
    /// Draws text at the specified position
    private func drawText(_ text: String, at yPosition: CGFloat, width: CGFloat, margin: CGFloat, fontSize: CGFloat, color: UIColor = .black) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        let textRect = CGRect(x: margin, y: yPosition, width: width, height: boundingRect.height + 5)
        attributedString.draw(in: textRect)
        
        return yPosition + boundingRect.height + 5
    }
    
    /// Formats a date for use in a filename
    private func formatDateForFileName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }
}
