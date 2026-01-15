//
//  FootstepNoiseAnalyzerApp.swift
//  FootstepNoiseAnalyzer
//
//  Main entry point for the Footstep Noise Analyzer iOS application.
//  This app records ambient sound and analyzes it to detect and classify
//  footstep-related noises from upstairs neighbors.
//

import SwiftUI
import AVFoundation

@main
struct FootstepNoiseAnalyzerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// App delegate to handle background audio configuration and app lifecycle events
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()
        return true
    }
    
    /// Configures the audio session for background recording capability
    /// Requirements: 2.1, 2.2 - Background recording support
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Audio session is already configured for background mode
        // The UIBackgroundModes audio key in Info.plist enables continued recording
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Requirement 2.3: Save current recording before termination
        // This will be implemented when RecordingService is created
        NotificationCenter.default.post(name: .appWillTerminate, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
