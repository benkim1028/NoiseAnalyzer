# iOS Simulator Commands

## Building the Project

```bash
xcodebuild -project FootstepNoiseAnalyzer/FootstepNoiseAnalyzer.xcodeproj -scheme FootstepNoiseAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Running on Simulator

### Boot the simulator
```bash
xcrun simctl boot "iPhone 17"
```

### Open Simulator app
```bash
open -a Simulator
```

### Install the app
```bash
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/FootstepNoiseAnalyzer-aknqcgzmpywbmxgsjzdneqmxaqzt/Build/Products/Debug-iphonesimulator/FootstepNoiseAnalyzer.app
```

### Launch the app
```bash
xcrun simctl launch booted com.footstepanalyzer.FootstepNoiseAnalyzer
```

## Useful Simulator Commands

### List available simulators
```bash
xcrun simctl list devices
```

### Shutdown simulator
```bash
xcrun simctl shutdown booted
```

### Uninstall app
```bash
xcrun simctl uninstall booted com.footstepanalyzer.FootstepNoiseAnalyzer
```
