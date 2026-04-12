# ShabbatClock

An iOS application for setting alarms based on Jewish prayer times (Zmanim) with traditional Jewish music and a beautiful analog clock interface.

## Project Overview

ShabbatClock is a Swift/SwiftUI iOS app that combines alarm functionality with Jewish prayer time calculations. It features a night sky background, analog clock display, and custom alarm sounds tailored for Shabbat and weekday use.

**Platform**: iOS 17+
**Language**: Swift
**UI Framework**: SwiftUI
**Data Persistence**: SwiftData
**Package Manager**: Swift Package Manager

## Architecture

### Main Components

```
ShabbatClock/
├── App/
│   ├── ShabbatClockApp.swift     # App entry point with SwiftData container
│   └── ContentView.swift          # Root view container
├── Models/
│   ├── Alarm.swift                # SwiftData model for alarms
│   └── AlarmSound.swift           # Alarm sound configurations
├── Views/
│   ├── MainView/                  # Main clock display
│   ├── AlarmList/                 # Alarm list interface
│   ├── AlarmEdit/                 # Alarm creation/editing
│   ├── AlarmFiring/               # Active alarm view
│   ├── Zmanim/                    # Prayer times display
│   ├── Settings/                  # App settings
│   └── Components/                # Reusable UI components
├── Services/
│   ├── ZmanimService.swift        # Jewish prayer time calculations
│   ├── LocationManager.swift     # Location services
│   ├── AlarmScheduler.swift      # Alarm scheduling logic
│   ├── AudioManager.swift        # Audio playback
│   └── BackgroundKeepAlive.swift # Background processing
├── Utilities/
│   └── Theme.swift                # App theme/colors
└── Resources/                     # Assets and resources
```

## Key Features

### 1. Alarm System
- **Model**: `Alarm.swift` - SwiftData model with properties:
  - Time (hour/minute)
  - Enable/disable state
  - Custom label
  - Sound selection
  - Auto-shutoff duration
  - Repeat days (weekdays/weekends/specific days)
  - Shabbat detection
- **Scheduler**: `AlarmScheduler.swift` - Manages alarm firing and background checks
- **Audio**: `AudioManager.swift` - Plays custom alarm sounds

### 2. Zmanim (Prayer Times)
- **Service**: `ZmanimService.swift`
  - Calculates Jewish prayer times based on location using **KosherSwift**
  - Supports 11 different zmanim types (Dawn, Sunrise, Latest Shema, etc.)
  - Uses precise astronomical calculations via ComplexZmanimCalendar
  - Implements GRA (Vilna Gaon) opinions for halachic times

### 3. Location Services
- **Manager**: `LocationManager.swift`
- Tracks user location for accurate zmanim calculations
- Falls back to default location if unavailable

### 4. Background Processing
- **KeepAlive**: `BackgroundKeepAlive.swift`
- Plays quiet (not silent) audio to keep app alive in background
- Uses `quiet_tone.m4a` - a very low volume 50Hz tone at -50dB
- Integrates with Background App Refresh for additional resilience
- Health monitoring: checks every 30 seconds that playback is active
- Auto-recovery: restarts playback if failures detected
- Audio session refresh: refreshes every 5 minutes to maintain background state

## Dependencies

### KosherSwift
- **Repository**: https://github.com/Elyahu41/KosherSwift.git
- **Version**: 1.0.0+
- **Purpose**: Advanced Jewish calendar and zmanim calculations
- Provides precise astronomical calculations for prayer times

## Data Models

### Alarm Model (`Alarm.swift`)
```swift
@Model
final class Alarm {
    var id: UUID
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var label: String
    var soundName: String
    var autoShutoffSeconds: Int
    var repeatDays: [Int]  // 0=Sunday, 1=Monday, ..., 6=Saturday
    var createdAt: Date
    var lastFiredAt: Date?
}
```

**Key Methods**:
- `nextFireDate()` - Calculates when alarm will fire next
- `shouldFire(at:)` - Checks if alarm should trigger at given time
- Computed properties for formatted display strings

### Zman Types
Supported zmanim (prayer times):
- **Alot HaShachar** (Dawn) - 72 min before sunrise
- **Misheyakir** (Earliest Tallit) - 36 min before sunrise
- **Netz** (Sunrise)
- **Sof Zman Shma** (Latest Shema) - 3 halachic hours
- **Sof Zman Tefila** (Latest Shacharit) - 4 halachic hours
- **Chatzot** (Midday) - 6 halachic hours
- **Mincha Gedola** (Earliest Mincha) - 6.5 halachic hours
- **Mincha Ketana** - 9.5 halachic hours
- **Plag HaMincha** - 10.75 halachic hours
- **Shkia** (Sunset)
- **Tzeis HaKochavim** (Nightfall) - 42 min after sunset

## UI Components

### Main Views
- **MainClockView** - Analog clock display with Zmanim
- **AlarmListView** - List of all alarms
- **AlarmEditView** - Create/edit alarm interface
- **AlarmActiveView** - Full-screen alarm firing view
- **ZmanimView** - Prayer times display
- **SettingsView** - App configuration

### Reusable Components
- **NightSkyBackground** - Animated starry background
- **AnalogClockView** - Custom analog clock rendering
- **AlarmRowView** - Individual alarm list item
- **RepeatDaysPicker** - Day selection for recurring alarms
- **SoundPickerView** - Alarm sound selection

## Development Guidelines

### Working with Alarms
1. Alarms use SwiftData for persistence
2. Access via `@Query` in views or `AlarmScheduler.shared`
3. Always call `alarmScheduler.scheduleNextCheck()` after modifying alarms
4. Repeat days use 0-based week indexing (0=Sunday, 6=Saturday)

### Zmanim Calculations
1. `ZmanimService.shared` is the main interface
2. Call `calculateTodayZmanim()` to refresh times
3. Uses KosherSwift's `ComplexZmanimCalendar` for precise calculations
4. Times automatically adjust for user location and timezone
5. All calculations follow GRA (Vilna Gaon) opinions
6. Available KosherSwift methods:
   - `getAlos72()` - Dawn (72 minutes)
   - `getMisheyakir10Point2Degrees()` - Earliest tallit
   - `getSunrise()` / `getSunset()` - Sun events
   - `getSofZmanShmaGRA()` / `getSofZmanTfilaGRA()` - Latest times
   - `getChatzos()` - Midday
   - `getMinchaGedola()` / `getMinchaKetana()` - Mincha times
   - `getPlagHamincha()` - Plag time
   - `getTzais()` - Nightfall

### Theme and Styling
- Colors defined in `Theme.swift`
- App uses dark mode with celestial blue/purple theme
- Night sky background throughout

### Audio Management
- Custom alarm sounds stored in Resources
- Default sound: "Lecha Dodi" (traditional Shabbat song)
- Audio playback managed by `AudioManager.shared`

## Building and Running

### Requirements
- Xcode 15.0+
- iOS 17.0+ target device/simulator
- Swift 5.9+

### Setup
```bash
# Clone the repository
cd ShabbatClock

# Open in Xcode
open ShabbatClock.xcodeproj

# Or build with Swift Package Manager
swift build
```

### Running
1. Open project in Xcode
2. Select target device/simulator (iOS 17+)
3. Build and run (⌘R)

## Key Technical Notes

### SwiftData Usage
- Container initialized in `ShabbatClockApp.swift`
- Alarm model uses `@Model` macro
- Views use `@Query` for reactive data fetching

### Background Processing
- App uses background refresh for alarm checking
- `BackgroundKeepAlive` manages task scheduling
- Limited by iOS background execution limits

### Location Privacy
- Requires location permissions for accurate zmanim
- Falls back to default location if denied
- Location used only for solar calculations

### Shabbat Mode
- Alarms detect if they're set for Saturday (Shabbat)
- Special handling may be needed for Shabbat compliance
- Audio and background tasks respect Jewish law considerations

## Future Enhancements

### Planned Features
- [x] Full KosherSwift integration for precise zmanim ✅
- [ ] Hebrew calendar display
- [ ] Custom location selection
- [ ] More alarm sounds
- [ ] Zmanim-based alarms (e.g., "30 min before sunset")
- [ ] Widget support for quick zmanim view
- [ ] Shabbat mode enhancements
- [ ] Multiple opinion support (Magen Avraham vs. GRA)

### Code Improvements
- Add unit tests for alarm scheduling logic
- Implement proper error handling for location failures
- Add accessibility labels for VoiceOver support
- Add Hebrew calendar integration using JewishCalendar from KosherSwift

## References

### Related Files
- Main app: `ShabbatClock/App/ShabbatClockApp.swift:5`
- Alarm model: `ShabbatClock/Models/Alarm.swift:4`
- Zmanim service: `ShabbatClock/Services/ZmanimService.swift:7`
- Location manager: `ShabbatClock/Services/LocationManager.swift`
- Alarm scheduler: `ShabbatClock/Services/AlarmScheduler.swift`

### External Resources
- KosherSwift Documentation: https://github.com/Elyahu41/KosherSwift
- SwiftData: https://developer.apple.com/documentation/swiftdata
- SwiftUI: https://developer.apple.com/documentation/swiftui

## License

[License information to be added]

## Contributors

[Contributor information to be added]
