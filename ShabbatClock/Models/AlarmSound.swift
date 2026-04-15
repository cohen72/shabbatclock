import Foundation

struct AlarmSound: Identifiable, Hashable {
    let id: String
    let name: String
    let category: Category
    let fileName: String
    let fileExtension: String
    let isPremium: Bool

    /// Localized display name for the sound.
    var displayName: String {
        AppLanguage.localized(name)
    }

    enum Category: String, CaseIterable {
        case shabbatMelodies = "Shabbat Melodies"
        case nature = "Nature"
        case chimesAndBells = "Chimes & Bells"
        case jazzy = "Jazzy"
        case eastern = "Eastern"
        case synthesized = "Synthesized"
        case annoying = "Just A Bit Annoying"

        /// Localized display name for the category.
        var displayName: String {
            AppLanguage.localized(rawValue)
        }

        var icon: String {
            switch self {
            case .shabbatMelodies: return "flame.fill"
            case .nature: return "leaf"
            case .chimesAndBells: return "bell"
            case .jazzy: return "music.note"
            case .eastern: return "globe.asia.australia"
            case .synthesized: return "waveform"
            case .annoying: return "exclamationmark.triangle"
            }
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: "Sounds")
    }
}

// MARK: - Sound Catalog
extension AlarmSound {
    static let allSounds: [AlarmSound] = [
        // Shabbat Melodies (FREE)
        AlarmSound(id: "lecha-dodi", name: "Lecha Dodi", category: .shabbatMelodies, fileName: "Lecha Dodi", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "ana-bekoach", name: "Ana Bekoach", category: .shabbatMelodies, fileName: "Ana Bekoach", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "el-adon", name: "El Adon", category: .shabbatMelodies, fileName: "El Adon", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "el-adon-regular", name: "El Adon (Regular)", category: .shabbatMelodies, fileName: "El Adon_regularTempo", fileExtension: "m4a", isPremium: true),

        // Nature (FREE)
        AlarmSound(id: "birds", name: "Birds", category: .nature, fileName: "Birds", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "ocean", name: "Ocean", category: .nature, fileName: "Ocean", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "rain", name: "Rain", category: .nature, fileName: "Rain", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "stream", name: "Stream", category: .nature, fileName: "Stream", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "lake", name: "Lake", category: .nature, fileName: "Lake", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "wind", name: "Wind", category: .nature, fileName: "Wind", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "whale", name: "Whale", category: .nature, fileName: "Whale", fileExtension: "m4a", isPremium: true),

        // Chimes & Bells (3 FREE, rest PREMIUM)
        AlarmSound(id: "sage-bells", name: "Sage Tyrtle Bells", category: .chimesAndBells, fileName: "Sage Tyrtle Bells", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "wine-glasses", name: "Wine Glasses", category: .chimesAndBells, fileName: "Wine Glasses", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "xylophone", name: "Xylophone", category: .chimesAndBells, fileName: "Xylophone", fileExtension: "m4a", isPremium: false),
        AlarmSound(id: "phone-ring", name: "Phone Ring", category: .chimesAndBells, fileName: "Phone Ring", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "80s-alarm", name: "80's Alarm", category: .chimesAndBells, fileName: "80's Alarm", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "oclock", name: "O'clock", category: .chimesAndBells, fileName: "O'clock", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "progressive-alarm", name: "Progressive Alarm", category: .chimesAndBells, fileName: "Progressive Alarm", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "cowbell", name: "Cowbell", category: .chimesAndBells, fileName: "Cowbell", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "bicycle", name: "Bicycle", category: .chimesAndBells, fileName: "Bicycle", fileExtension: "m4a", isPremium: true),

        // Jazzy (PREMIUM)
        AlarmSound(id: "trumpy", name: "Trumpy", category: .jazzy, fileName: "Trumpy", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "groovy", name: "Groovy", category: .jazzy, fileName: "Groovy", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "sunny", name: "Sunny", category: .jazzy, fileName: "Sunny", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "riffy", name: "Riffy", category: .jazzy, fileName: "Riffy", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "downy", name: "Downy", category: .jazzy, fileName: "Downy", fileExtension: "m4a", isPremium: true),

        // Eastern (PREMIUM)
        AlarmSound(id: "ohm", name: "Ohm", category: .eastern, fileName: "Ohm", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "chinese-birthday", name: "Chinese Birthday", category: .eastern, fileName: "Chinese Birthday", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "lute", name: "Lute", category: .eastern, fileName: "Lute", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "pluck", name: "Pluck", category: .eastern, fileName: "Pluck", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "sitar", name: "Sitar", category: .eastern, fileName: "Sitar", fileExtension: "m4a", isPremium: true),

        // Synthesized (PREMIUM)
        AlarmSound(id: "fly", name: "Fly", category: .synthesized, fileName: "Fly", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "i-am-alive", name: "I am Alive", category: .synthesized, fileName: "I am Alive", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "gan-eden", name: "Gan Eden", category: .synthesized, fileName: "Gan Eden", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "sun-shower", name: "Sun Shower", category: .synthesized, fileName: "Sun Shower", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "get-busy", name: "Get Busy", category: .synthesized, fileName: "Get Busy", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "pursuit", name: "Pursuit", category: .synthesized, fileName: "Pursuit", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "boker-tov", name: "Boker Tov", category: .synthesized, fileName: "Boker Tov", fileExtension: "m4a", isPremium: true),

        // Just A Bit Annoying (PREMIUM)
        AlarmSound(id: "fire-alarm", name: "Fire Alarm", category: .annoying, fileName: "Fire Alarm", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "honk", name: "Honk", category: .annoying, fileName: "Honk", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "airhorn", name: "Airhorn", category: .annoying, fileName: "Airhorn", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "police", name: "Police", category: .annoying, fileName: "Police", fileExtension: "m4a", isPremium: true),
        AlarmSound(id: "meltdown", name: "Meltdown", category: .annoying, fileName: "Meltdown", fileExtension: "m4a", isPremium: true),
    ]

    static var freeSounds: [AlarmSound] {
        allSounds.filter { !$0.isPremium }
    }

    static var premiumSounds: [AlarmSound] {
        allSounds.filter { $0.isPremium }
    }

    static var byCategory: [Category: [AlarmSound]] {
        Dictionary(grouping: allSounds, by: { $0.category })
    }

    static func sound(named name: String) -> AlarmSound? {
        allSounds.first { $0.name == name }
    }

    static func sound(byId id: String) -> AlarmSound? {
        allSounds.first { $0.id == id }
    }

    static let defaultSound = allSounds.first { $0.name == "Lecha Dodi" } ?? allSounds[0]
}
