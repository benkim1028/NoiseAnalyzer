# Footstep Noise Analyzer

An iOS application that records ambient sound and analyzes it to detect and classify footstep-related noises (stomping, heel strikes, shuffling, etc.) from upstairs neighbors.

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Project Structure

```
FootstepNoiseAnalyzer/
├── FootstepNoiseAnalyzer/
│   ├── Models/           # Data models (FootstepEvent, RecordingSession, etc.)
│   ├── Services/         # Business logic (AudioRecorder, NoiseAnalyzer, etc.)
│   ├── Views/            # SwiftUI views
│   ├── ViewModels/       # View models for MVVM pattern
│   ├── Assets.xcassets/  # App assets
│   ├── Preview Content/  # SwiftUI preview assets
│   ├── Info.plist        # App configuration
│   ├── FootstepNoiseAnalyzerApp.swift  # App entry point
│   └── ContentView.swift # Main content view
├── FootstepNoiseAnalyzerTests/  # Unit and property-based tests
└── Package.swift         # Swift Package Manager configuration
```

## Dependencies

- **SwiftCheck** (0.12.0+) - Property-based testing framework

## Configuration

### Microphone Permission

The app requires microphone access. The permission description is configured in `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record and analyze footstep sounds from your environment.</string>
```

### Background Audio

Background recording is enabled via the `UIBackgroundModes` key in `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

## Building

1. Open `FootstepNoiseAnalyzer.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (⌘R)

## Testing

Run tests in Xcode using ⌘U or via command line:

```bash
xcodebuild test -project FootstepNoiseAnalyzer.xcodeproj -scheme FootstepNoiseAnalyzer -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Features

- **Audio Recording**: Capture ambient sound with background support
- **Footstep Detection**: Automatic detection of footstep patterns
- **Classification**: Categorize footsteps (stomping, heel strike, shuffling, running)
- **Event Logging**: Comprehensive record of detected events
- **Evidence Reports**: Generate PDF reports for documentation
- **Session Management**: Organize and review recording sessions
