# ShabbatClock

An iOS application for setting alarms based on Jewish prayer times (Zmanim) with traditional Jewish music and a beautiful analog clock interface.

## Project Overview

ShabbatClock is a Swift/SwiftUI iOS app that combines alarm functionality with Jewish prayer time calculations. It features an adaptive light/dark theme, analog clock display, Shabbat dashboard with parasha and countdown, and custom alarm sounds tailored for Shabbat and weekday use. The app is fully localized in English and Hebrew with full RTL support.

**Platform**: iOS 26+
**Language**: Swift
**UI Framework**: SwiftUI
**Data Persistence**: SwiftData
**Package Manager**: Swift Package Manager
**Localization**: English, Hebrew (RTL)

## Architecture

### Main Components

```
ShabbatClock/
├── App/
│   ├── ShabbatClockApp.swift     # App entry point with SwiftData container + language override
│   └── ContentView.swift          # Root view container with theme/language/tab/onboarding management
├── Models/
│   ├── Alarm.swift                # SwiftData model for alarms
│   ├── AlarmSound.swift           # Alarm sound configurations with localized display names
│   └── ShabbatAlarmMetadata.swift # Metadata for AlarmKit integration (shared with widget target)
├── Views/
│   ├── Onboarding/                # First-launch onboarding flow (OnboardingView)
│   ├── MainView/                  # Main clock display (MainClockView, AnalogClockView)
│   ├── AlarmList/                 # Alarm list (AlarmListView, AlarmRowView)
│   ├── AlarmEdit/                 # Alarm creation/editing (AlarmEditView, RepeatDaysPicker, SoundPickerView)
│   ├── Zmanim/                    # Prayer times display with pull-to-refresh
│   ├── Settings/                  # App settings (SettingsView, PremiumView, DebugView)
│   └── Components/                # Reusable UI (NightSkyBackground, LocationRow, CitySearchView, PermissionPromptView)
├── Services/
│   ├── AlarmKitService.swift     # AlarmKit integration (iOS 26+) — main alarm scheduling + auto-stop
│   ├── StopAlarmIntent.swift     # App Intent for stopping alarms via Live Activity
│   ├── ZmanimService.swift        # Jewish prayer time + Shabbat dashboard calculations
│   ├── LocationManager.swift     # Location services with CLGeocoder locale support
│   ├── AudioManager.swift        # Audio playback (preview only — AlarmKit handles alarm audio)
│   └── StoreManager.swift        # StoreKit 2 subscription manager (singleton)
├── Products.storekit              # StoreKit testing configuration (weekly + yearly plans)
├── Utilities/
│   └── Theme.swift                # Adaptive theme + AppearanceMode + AppLanguage + Bundle override
├── Resources/
│   ├── Localizable.xcstrings      # String Catalog with English + Hebrew translations (270+ strings)
│   ├── InfoPlist.xcstrings        # Localized Info.plist keys (system dialog strings)
│   ├── Sounds/                    # Alarm sound files organized by category
│   └── Media.xcassets/            # App icon, accent color, launch screen background
└── widgets/                       # Widget extension target (Live Activity for Dynamic Island)
    ├── widgetsBundle.swift        # Widget bundle entry point
    ├── widgetsLiveActivity.swift  # AlarmKit Live Activity UI (Lock Screen + Dynamic Island)
    ├── ShabbatAlarmMetadata.swift # Shared metadata (copy of Models/ version)
    ├── widgets.entitlements       # App Groups entitlement
    └── Info.plist                 # Widget extension Info.plist
```

## Key Features

### 1. Alarm System
- **Model**: `Alarm.swift` - SwiftData model with properties:
  - Time (hour/minute)
  - Enable/disable state
  - Custom label (defaults to localized "Alarm" / "התראה")
  - Sound selection
  - Snooze support (enable/disable, configurable duration)
  - Repeat days (weekdays/weekends/specific days)
  - Shabbat detection
  - `alarmKitID` - links to AlarmKit system alarm
- **Service**: `AlarmKitService.swift` - AlarmKit integration (iOS 26+) for system-level alarm scheduling
  - Layered auto-stop: local notification (primary, works when app killed) + in-process Task.sleep (backup)
  - Fallback mode: if AlarmKit denied, uses critical alert notifications (30s max)
  - Auto-migration: when user grants AlarmKit later, migrates from fallback to AlarmKit
  - Custom alarm sounds via `AlertConfiguration.AlertSound.named()`
- **Intent**: `StopAlarmIntent.swift` - LiveActivityIntent for stopping alarms
- **Audio**: `AudioManager.shared` - Sound preview only (AlarmKit handles alarm audio)

### 2. Zmanim (Prayer Times)
- **Service**: `ZmanimService.swift`
  - Calculates Jewish prayer times based on location using **KosherSwift**
  - Supports 11 different zmanim types (Dawn, Sunrise, Latest Shema, etc.)
  - Uses precise astronomical calculations via ComplexZmanimCalendar
  - Implements GRA (Vilna Gaon) opinions for halachic times
  - Zmanim row shows Hebrew name, English name, time, and alarm button
  - "Next" badge highlights the upcoming zman
  - Pull-to-refresh support

### 3. Shabbat Dashboard (Main Clock Screen)
- **Hebrew date**: Today's date in the Hebrew calendar (e.g., "י״ד ניסן תשפ״ו")
- **Parashat Hashavua**: Weekly Torah portion — Hebrew or English based on app language
  - Uses KosherSwift's `JewishCalendar.getParshah()` + `HebrewDateFormatter.formatParsha()`
- **Shabbat countdown**: "In X days" / "Tomorrow" / "Shabbat Shalom!" based on day of week
- **Candle Lighting**: Time for the upcoming Friday candle lighting
- **Havdalah**: Time for Saturday night havdalah
- **Location**: Tappable row showing current city, opens CitySearchView

### 4. Location Services
- **Manager**: `LocationManager.shared`
- Device GPS location with reverse geocoding (locale-aware via `CLGeocoder`)
- Manual city selection via `CitySearchView` (MapKit search)
- Location name stored as `"__unknown__"` sentinel, resolved to localized "Unknown Location" at display time
- Timezone resolution for manual locations

### 5. Localization (English + Hebrew)
- **String Catalog**: `Resources/Localizable.xcstrings` — 270+ strings with Hebrew translations
- **Info.plist localization**: `Resources/InfoPlist.xcstrings` — system dialog strings (location, alarms)
- **In-app language switching**: System / English / עברית picker in Settings
- **Bundle override**: `OverriddenBundle` swizzles `Bundle.main` for immediate language switching
  - `AppLanguage.applyBundleOverride()` called on app init and language change
  - `.id("lang-\(appLanguage)")` on root TabView forces full view rebuild
- **RTL support**: `.environment(\.layoutDirection, .rightToLeft)` applied at root + all sheets
- **Non-SwiftUI contexts**: `AppLanguage.localized("key")` resolves from correct `.lproj` bundle
- **DateFormatters**: Use `AppLanguage.current.effectiveLocale` for locale-aware formatting
- **Reverse geocoding**: Uses `CLGeocoder(preferredLocale:)` for localized place names
- **Directional icons**: All chevrons use `chevron.forward` (auto-flips for RTL)
- **Sheets**: Each `.sheet()` must include `.applyLanguageOverride(AppLanguage.current)` since sheets create a new presentation context
- **Sound names**: `AlarmSound.displayName` and `Category.displayName` use `AppLanguage.localized()` for Hebrew translations
- **Sentinel pattern**: Services store sentinel strings (e.g., `"__unknown__"`, `"__friday_evening__"`) and views resolve them to `Text("localized key")` which auto-resolves via the environment

### 6. Theme System (Light/Dark Mode)
- **Adaptive colors**: `Color(light:dark:)` pattern using `UIColor` dynamic provider
- **Semantic colors**: `backgroundPrimary`, `backgroundSecondary`, `surfaceCard`, `surfaceBorder`, `surfaceSubtle`, `textPrimary`, `textSecondary`, `clockFaceFill`, `clockHand`, etc.
- **Light mode**: Warm cream (#F5F2EC) backgrounds, dark navy text, gold accents
- **Dark mode**: Deep navy (#141833) backgrounds, white text, gold/amber accents
- **Gold accent** (`#F4A261`) consistent in both modes for interactive elements
- **Launch screen**: `LaunchScreenBackground` color in asset catalog — adapts to light/dark
- **Night sky**: Stars/moon/clouds only shown in dark mode; light mode is clean gradient
- **Appearance setting**: `AppearanceMode` enum (system/light/dark) in `@AppStorage("appearanceMode")`
- **Tab bar**: Uses system material (floating tab bar in iOS 18+), `.preferredColorScheme()` ensures dark materials

### 7. Onboarding (First Launch)
- **View**: `OnboardingView.swift` — 4-page paged TabView with dot indicators
- **Flow**: Welcome → Alarms → Notifications → Location (ordered by importance)
- **Gating**: `@AppStorage("hasCompletedOnboarding")` — shows once, set to true on completion
- **Permission pages**: Each educates then triggers the system dialog; "Not Now" skips
- **Already-granted detection**: Button turns green with checkmark if permission already approved
- **Notifications page**: Custom layout with red warning card previewing the Critical Alerts dialog
- **RTL**: Inherits language override from ContentView fullScreenCover
- **Debug**: Previewable and resettable from Settings > Debug > Onboarding

### 8. Permission System
- **Pre-permission prompts**: `PermissionPromptView.swift` — full-screen education before system dialogs
- **Just-in-time**: Permissions are NEVER requested at launch; always contextual
- **Onboarding**: Primary path — handles alarms, notifications, location during first launch
- **Fallback**: `AlarmEditView` catches missing permissions when saving first alarm
- **Location**: `LocationRow` shows pre-permission prompt when tapped without authorization
- **Denied handling**: Settings deep-link offered when permission was previously denied

### 9. Premium / Subscription System
- **StoreManager**: `StoreManager.shared` - Centralized StoreKit 2 subscription manager
- **Plans**: Weekly ($0.99/week) and Yearly ($14.99/year, ~71% savings)
- **Product IDs**: `com.shabbatclock.app.premium.weekly`, `com.shabbatclock.app.premium.yearly`
- **Free tier**: Limited to 3 alarms; can preview but not select premium sounds
- **Premium state**: `StoreManager.shared.isPremium` is source of truth
- **UI**: Toolbar capsule badge "1/3" with lock icon; + button shows lock when limit reached

## Dependencies

### KosherSwift
- **Repository**: https://github.com/Elyahu41/KosherSwift.git
- **Version**: 2.0.0+
- **Purpose**: Jewish calendar, zmanim calculations, parasha lookup
- **Key classes used**:
  - `ComplexZmanimCalendar` — prayer time calculations
  - `JewishCalendar` — parasha, Hebrew date, holidays
  - `HebrewDateFormatter` — Hebrew date formatting, parsha names
  - `GeoLocation` — location wrapper for calculations

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
    var repeatDays: [Int]  // 0=Sunday, 1=Monday, ..., 6=Saturday
    var createdAt: Date
    var lastFiredAt: Date?
    var alarmKitID: UUID?
    var snoozeDurationSecondsValue: Int?
    var snoozeEnabledValue: Bool?
    var alarmDurationSecondsValue: Int?
    var zmanTypeRawValue: String?
    var zmanMinutesBefore: Int?
}
```

**Key Methods**:
- `nextFireDate()` - Calculates when alarm will fire next
- `shouldFire(at:)` - Checks if alarm should trigger at given time
- `repeatDaysString` - Locale-aware repeat days display using `AppLanguage.current.effectiveLocale`
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
- **MainClockView** - Analog clock + Shabbat dashboard (parasha, countdown, candle lighting, havdalah)
- **AlarmListView** - List of all alarms with premium tier badge
- **AlarmEditView** - Create/edit alarm with NavigationStack (sound picker, repeat picker via NavigationLink)
- **ZmanimView** - Prayer times display with pull-to-refresh and location toolbar button
- **SettingsView** - App configuration (location, appearance, language, premium, defaults, about)
- **PremiumView** - Premium subscription upsell screen

### Reusable Components
- **NightSkyBackground** - Animated starry background (dark mode only)
- **AnalogClockView** - Custom Canvas-based analog clock
- **AlarmRowView** - Individual alarm list item
- **RepeatDaysPicker** - Day selection with locale-aware day names
- **SoundPickerView** - Categorized alarm sound selection with preview
- **LocationRow** - Tappable location display (resolves `"__unknown__"` sentinel to localized text)
- **CitySearchView** - MapKit-powered city search
- **PermissionPromptView** - Pre-permission education (location, alarms, notifications variants)
- **OnboardingView** - First-launch paged flow with permission requests
- **DebugView** - DEBUG-only tools: permission previews, onboarding reset, AlarmKit state
- **SectionHeader** - Settings section header (uses `LocalizedStringKey`)
- **ShabbatTimeCard** - Compact candle lighting / havdalah time display

## Development Guidelines

### Localization (MANDATORY)
**All user-facing strings MUST use localization.** This is non-negotiable for every change:
- SwiftUI `Text("literal")` auto-localizes via `LocalizedStringKey` + bundle swizzle
- Use `String(localized:)` for computed strings in SwiftUI contexts
- Use `AppLanguage.localized("key")` for non-SwiftUI code (services, models) — resolves from correct `.lproj`
- **Never** use `Locale.current` for formatting — use `AppLanguage.current.effectiveLocale`
- Add new strings to `Resources/Localizable.xcstrings` for both `en` and `he`
- Test both LTR (English) and RTL (Hebrew) layouts for any UI changes
- Use `chevron.forward` (not `chevron.right`) for directional icons — auto-flips for RTL
- Apply `.applyLanguageOverride(AppLanguage.current)` to every `.sheet()` content
- For services storing display strings: use sentinel values (e.g., `"__unknown__"`) and resolve in views
- **Picker labels**: Use `Text("literal")` directly (not `Text(variable)`) for proper LocalizedStringKey resolution
- Language picker shows: "מערכת" / "English" / "עברית" — English stays in English since users selecting it can read it

### Working with Alarms
1. Alarms use SwiftData for persistence
2. Access via `@Query` in views or `AlarmKitService.shared`
3. Alarm scheduling is handled by AlarmKit (iOS 26+) — never use UNUserNotificationCenter for alarm delivery
4. Auto-stop uses a layered approach: local notification (primary, works when app killed) + in-process Task.sleep (backup)
5. If AlarmKit denied, fallback mode uses critical alert notifications (30s max duration)
6. Repeat days use 0-based week indexing (0=Sunday, 6=Saturday)
7. Default alarm label uses `String(localized: "Alarm")` for locale-aware defaults
8. New SwiftData properties must use optional backing (`propertyValue: Type?`) with computed getters for defaults — required for lightweight migration

### Zmanim Calculations
1. `ZmanimService.shared` is the main interface
2. Call `calculateTodayZmanim()` to refresh times
3. Uses KosherSwift's `ComplexZmanimCalendar` for precise calculations
4. Times automatically adjust for user location and timezone
5. All calculations follow GRA (Vilna Gaon) opinions
6. Shabbat info (parasha, countdown, candle lighting, havdalah) calculated via `calculateShabbatTimes()`
7. Hebrew date formatted via KosherSwift's `HebrewDateFormatter`
8. Zman descriptions are localized via `AppLanguage.localized()`

### Theme and Styling
- Colors defined in `Theme.swift` with adaptive light/dark mode support via `Color(light:dark:)`
- Light mode: warm cream/white backgrounds, dark text, gold accents
- Dark mode: deep navy backgrounds, white text, gold/amber accents
- Gold accent (`#F4A261`) used for interactive elements, badges, and premium indicators
- Appearance mode (system/light/dark) configurable via `AppearanceMode` in Settings
- Use `.themeCard()` modifier for standard card backgrounds
- Use `.settingsCard()` for settings-style card backgrounds

### Audio Management
- Custom alarm sounds stored in Resources/Sounds/ organized by category
- 47 sounds across 7 categories (Shabbat Melodies, Nature, Chimes & Bells, Jazzy, Eastern, Synthesized, Just A Bit Annoying)
- Default sound: "Lecha Dodi" (traditional Shabbat song)
- `AlarmSound.displayName` returns localized name; `Category.displayName` returns localized category
- Sound names are proper nouns — Hebrew translations use Hebrew spellings (e.g., "לכה דודי")
- Audio playback managed by `AudioManager.shared`

## Building and Running

### Requirements
- Xcode 26+
- iOS 26.0+ target device/simulator (AlarmKit dependency)
- Swift 6+

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
2. Select target device/simulator (iOS 26+)
3. Build and run (⌘R)

### Build command (CLI)
```bash
xcodebuild -project ShabbatClock.xcodeproj -scheme ShabbatClock -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Key Technical Notes

### SwiftData Usage
- Container initialized in `ShabbatClockApp.swift`
- Alarm model uses `@Model` macro
- Views use `@Query` for reactive data fetching

### AlarmKit Integration
- Alarms are scheduled via AlarmKit (iOS 26+), which provides system-level alarm behavior
- AlarmKit alarms override Do Not Disturb and work without the app running
- `AlarmKitService.shared` is the main interface for scheduling/canceling alarms
- Live Activity / Dynamic Island support via widget extension (`widgets/` target)
- Auto-stop: layered approach — UNNotification at `fireTime + duration` (works when app killed) + in-process Task.sleep
- Fallback mode: if user denies AlarmKit, uses critical alert notifications (limited to 30s sound)
- Custom sounds: `AlertConfiguration.AlertSound.named("FileName.m4a")`
- Widget extension requires App Groups (`group.com.shabbatclock.app`) for shared data
- `ShabbatAlarmMetadata` must be kept in sync between `ShabbatClock/Models/` and `widgets/`

### Permissions (Just-in-Time)
- **Never request permissions at launch** — always contextual
- Onboarding handles first-launch permissions (Alarms → Notifications → Location)
- AlarmEditView catches missing permissions as fallback when saving
- LocationRow shows pre-permission prompt when location not authorized
- `AlarmKitService.configure()` only checks existing state, never prompts
- Info.plist system dialog strings localized via `Resources/InfoPlist.xcstrings`

### In-App Language Switching
- `OverriddenBundle` class swizzles `Bundle.main` to intercept `localizedString(forKey:value:table:)`
- Routes string lookups to the correct `.lproj` bundle based on `AppLanguage.current`
- `AppLanguage.applyBundleOverride()` activates the swizzle on app launch
- `.id("lang-\(appLanguage)")` on root TabView forces complete view hierarchy rebuild on language change
- `AppleLanguages` UserDefaults key also set for next cold launch consistency

### Location Privacy
- Requires location permissions for accurate zmanim
- Falls back to manual city selection or default location if denied
- Uses `CLGeocoder` with `preferredLocale` for localized place names
- Location used only for solar calculations and timezone resolution

### Shabbat Mode
- Alarms detect if they're set for Saturday (Shabbat)
- Special handling may be needed for Shabbat compliance
- Audio and background tasks respect Jewish law considerations

## Future Enhancements

### Planned Features
- [x] Full KosherSwift integration for precise zmanim
- [x] AlarmKit migration (iOS 26+) with auto-stop and fallback mode
- [x] Onboarding flow with contextual permissions
- [x] Live Activity / Dynamic Island support via widget extension
- [x] Light/dark mode support with user override
- [x] Custom location selection (CitySearchView)
- [x] Premium/subscription tier system
- [x] Hebrew localization with in-app language switching
- [x] RTL layout support
- [x] Hebrew calendar display on main dashboard
- [x] Parashat Hashavua on main dashboard
- [x] Shabbat countdown
- [ ] Zmanim-based alarms (e.g., "30 min before sunset")
- [ ] Widget support for quick zmanim view
- [ ] Shabbat mode enhancements
- [ ] Multiple opinion support (Magen Avraham vs. GRA)
- [ ] Additional language support

### Code Improvements
- Add unit tests for alarm scheduling logic
- Implement proper error handling for location failures
- Add accessibility labels for VoiceOver support

## References

### Related Files
- Main app: `ShabbatClock/App/ShabbatClockApp.swift`
- Alarm model: `ShabbatClock/Models/Alarm.swift`
- AlarmKit service: `ShabbatClock/Services/AlarmKitService.swift`
- Zmanim service: `ShabbatClock/Services/ZmanimService.swift`
- Location manager: `ShabbatClock/Services/LocationManager.swift`
- Store manager: `ShabbatClock/Services/StoreManager.swift`
- Theme + language: `ShabbatClock/Utilities/Theme.swift`
- String catalog: `ShabbatClock/Resources/Localizable.xcstrings`

### External Resources
- KosherSwift Documentation: https://github.com/Elyahu41/KosherSwift
- SwiftData: https://developer.apple.com/documentation/swiftdata
- SwiftUI: https://developer.apple.com/documentation/swiftui
