import Foundation
import CoreLocation
import Combine
import KosherSwift

/// Service for calculating Jewish Zmanim (halachic times) using KosherSwift.
@MainActor
final class ZmanimService: ObservableObject {
  static let shared = ZmanimService()
  
  @Published var todayZmanim: [Zman] = []
  @Published var isLoading: Bool = false
  @Published var lastUpdated: Date?
  @Published var candleLightingTime: Date?
  @Published var havdalahTime: Date?
  @Published var candleLightingDateLabel: String = "__friday_evening__"
  @Published var havdalahDateLabel: String = "__saturday_night__"
  @Published var sunriseTime: Date?
  @Published var sunsetTime: Date?

  // Shabbat dashboard info
  @Published var parashaHebrew: String = ""
  @Published var parashaEnglish: String = ""
  @Published var hebrewDateString: String = ""
  @Published var hebrewDateEnglish: String = ""
  @Published var daysUntilShabbat: Int = 0
  @Published var nextShabbatDate: Date?

  // Daf Yomi
  @Published var dafYomiEnglish: String = ""
  @Published var dafYomiHebrew: String = ""

  private let locationManager = LocationManager.shared
  private var locationObservation: Any?

  private init() {
    // Recalculate zmanim whenever location changes
    locationObservation = locationManager.$location
      .compactMap { $0 }
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.calculateTodayZmanim()
      }
  }
  
  // MARK: - Zman Model
  
  struct Zman: Identifiable {
    let id = UUID()
    let type: ZmanType
    let time: Date
    let hebrewName: String
    let englishName: String
    let description: String
    
    var timeString: String {
      TimeFormatter.fullTime(time)
    }
  }
  
  enum ZmanType: String, CaseIterable {
    case alotHashachar = "alot"
    case misheyakir = "misheyakir"
    case netz = "netz"
    case sofZmanShma = "shma"
    case sofZmanTefila = "tefila"
    case chatzot = "chatzot"
    case minchaGedola = "minchaGedola"
    case minchaKetana = "minchaKetana"
    case plagHamincha = "plag"
    case shkia = "shkia"
    case tzeitHakochavim = "tzeis"
    
    var hebrewName: String {
      switch self {
      case .alotHashachar: return "עלות השחר"
      case .misheyakir: return "משיכיר"
      case .netz: return "הנץ החמה"
      case .sofZmanShma: return "סוף זמן שמע"
      case .sofZmanTefila: return "סוף זמן תפילה"
      case .chatzot: return "חצות"
      case .minchaGedola: return "מנחה גדולה"
      case .minchaKetana: return "מנחה קטנה"
      case .plagHamincha: return "פלג המנחה"
      case .shkia: return "שקיעה"
      case .tzeitHakochavim: return "צאת הכוכבים"
      }
    }
    
    var englishName: String {
      switch self {
      case .alotHashachar: return "Dawn"
      case .misheyakir: return "Earliest Tallit"
      case .netz: return "Sunrise"
      case .sofZmanShma: return "Latest Shema"
      case .sofZmanTefila: return "Latest Shacharit"
      case .chatzot: return "Midday"
      case .minchaGedola: return "Earliest Mincha"
      case .minchaKetana: return "Mincha Ketana"
      case .plagHamincha: return "Plag HaMincha"
      case .shkia: return "Sunset"
      case .tzeitHakochavim: return "Nightfall"
      }
    }
    
    var description: String {
      switch self {
      case .alotHashachar: return AppLanguage.localized("72 minutes before sunrise")
      case .misheyakir: return AppLanguage.localized("Earliest time for tallit and tefillin")
      case .netz: return AppLanguage.localized("Sunrise - ideal start of Shacharit")
      case .sofZmanShma: return AppLanguage.localized("Latest time for morning Shema (GRA)")
      case .sofZmanTefila: return AppLanguage.localized("Latest time for Shacharit Amidah")
      case .chatzot: return AppLanguage.localized("Halachic midday")
      case .minchaGedola: return AppLanguage.localized("Earliest time for Mincha")
      case .minchaKetana: return AppLanguage.localized("Preferable time for Mincha")
      case .plagHamincha: return AppLanguage.localized("1.25 hours before sunset")
      case .shkia: return AppLanguage.localized("Sunset - start of evening")
      case .tzeitHakochavim: return AppLanguage.localized("Nightfall - 3 stars visible")
      }
    }
  }
  
  // MARK: - Calculate Zmanim

  /// Calculate today's zmanim for the current location using KosherSwift.
  func calculateTodayZmanim() {
    isLoading = true

    todayZmanim = calculateZmanim(for: Date())
    lastUpdated = Date()
    isLoading = false

    // Store sunrise/sunset
    let location = locationManager.currentOrDefaultLocation
    let geoLocation = GeoLocation(
      locationName: locationManager.locationName,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timeZone: locationManager.locationTimeZone
    )
    let cal = ComplexZmanimCalendar(location: geoLocation)
    cal.workingDate = Date()
    sunriseTime = cal.getSunrise()
    sunsetTime = cal.getSunset()

    // Calculate Shabbat times
    calculateShabbatTimes()
  }

  /// Calculate zmanim for a specific date and the current location.
  func calculateZmanim(for date: Date) -> [Zman] {
    let location = locationManager.currentOrDefaultLocation

    let geoLocation = GeoLocation(
      locationName: locationManager.locationName,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timeZone: locationManager.locationTimeZone
    )

    let calendar = ComplexZmanimCalendar(location: geoLocation)
    calendar.workingDate = date

    var zmanim: [Zman] = []

    if let alot = calendar.getAlos72() {
      zmanim.append(Zman(type: .alotHashachar, time: alot,
        hebrewName: ZmanType.alotHashachar.hebrewName,
        englishName: ZmanType.alotHashachar.englishName,
        description: ZmanType.alotHashachar.description))
    }

    if let misheyakir = calendar.getMisheyakir10Point2Degrees() {
      zmanim.append(Zman(type: .misheyakir, time: misheyakir,
        hebrewName: ZmanType.misheyakir.hebrewName,
        englishName: ZmanType.misheyakir.englishName,
        description: ZmanType.misheyakir.description))
    }

    if let sunrise = calendar.getSunrise() {
      zmanim.append(Zman(type: .netz, time: sunrise,
        hebrewName: ZmanType.netz.hebrewName,
        englishName: ZmanType.netz.englishName,
        description: ZmanType.netz.description))
    }

    if let sofShma = calendar.getSofZmanShmaGRA() {
      zmanim.append(Zman(type: .sofZmanShma, time: sofShma,
        hebrewName: ZmanType.sofZmanShma.hebrewName,
        englishName: ZmanType.sofZmanShma.englishName,
        description: ZmanType.sofZmanShma.description))
    }

    if let sofTefila = calendar.getSofZmanTfilaGRA() {
      zmanim.append(Zman(type: .sofZmanTefila, time: sofTefila,
        hebrewName: ZmanType.sofZmanTefila.hebrewName,
        englishName: ZmanType.sofZmanTefila.englishName,
        description: ZmanType.sofZmanTefila.description))
    }

    if let chatzot = calendar.getChatzos() {
      zmanim.append(Zman(type: .chatzot, time: chatzot,
        hebrewName: ZmanType.chatzot.hebrewName,
        englishName: ZmanType.chatzot.englishName,
        description: ZmanType.chatzot.description))
    }

    if let minchaGedola = calendar.getMinchaGedola() {
      zmanim.append(Zman(type: .minchaGedola, time: minchaGedola,
        hebrewName: ZmanType.minchaGedola.hebrewName,
        englishName: ZmanType.minchaGedola.englishName,
        description: ZmanType.minchaGedola.description))
    }

    if let minchaKetana = calendar.getMinchaKetana() {
      zmanim.append(Zman(type: .minchaKetana, time: minchaKetana,
        hebrewName: ZmanType.minchaKetana.hebrewName,
        englishName: ZmanType.minchaKetana.englishName,
        description: ZmanType.minchaKetana.description))
    }

    if let plag = calendar.getPlagHamincha() {
      zmanim.append(Zman(type: .plagHamincha, time: plag,
        hebrewName: ZmanType.plagHamincha.hebrewName,
        englishName: ZmanType.plagHamincha.englishName,
        description: ZmanType.plagHamincha.description))
    }

    if let sunset = calendar.getSunset() {
      zmanim.append(Zman(type: .shkia, time: sunset,
        hebrewName: ZmanType.shkia.hebrewName,
        englishName: ZmanType.shkia.englishName,
        description: ZmanType.shkia.description))
    }

    if let tzeis = calendar.getTzais() {
      zmanim.append(Zman(type: .tzeitHakochavim, time: tzeis,
        hebrewName: ZmanType.tzeitHakochavim.hebrewName,
        englishName: ZmanType.tzeitHakochavim.englishName,
        description: ZmanType.tzeitHakochavim.description))
    }

    return zmanim
  }

  // MARK: - Shabbat Times

  /// Calculate candle lighting (Friday) and havdalah (Saturday) times for the upcoming Shabbat.
  private func calculateShabbatTimes() {
    let location = locationManager.currentOrDefaultLocation
    let geoLocation = GeoLocation(
      locationName: locationManager.locationName,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timeZone: locationManager.locationTimeZone
    )

    let calendar = Calendar.current
    let today = Date()
    let weekday = calendar.component(.weekday, from: today) // 1=Sun, 7=Sat

    // Find the next Friday (weekday 6)
    let daysUntilFriday: Int
    if weekday == 7 {
      // Saturday - show this week's candle lighting (yesterday) and tonight's havdalah
      daysUntilFriday = -1
    } else if weekday == 6 {
      // Friday - show today's candle lighting
      daysUntilFriday = 0
    } else {
      // Sunday-Thursday - show upcoming Friday
      daysUntilFriday = 6 - weekday
    }

    guard let nextFriday = calendar.date(byAdding: .day, value: daysUntilFriday, to: today),
          let nextSaturday = calendar.date(byAdding: .day, value: 1, to: nextFriday) else { return }

    // Candle lighting on Friday
    let fridayCalendar = ComplexZmanimCalendar(location: geoLocation)
    fridayCalendar.workingDate = nextFriday
    candleLightingTime = fridayCalendar.getCandleLighting()

    // Havdalah on Saturday (nightfall)
    let saturdayCalendar = ComplexZmanimCalendar(location: geoLocation)
    saturdayCalendar.workingDate = nextSaturday
    havdalahTime = saturdayCalendar.getTzais()

    // Date labels
    candleLightingDateLabel = "__friday_evening__"
    havdalahDateLabel = "__saturday_night__"

    // Store the next Shabbat date
    nextShabbatDate = nextSaturday

    // Days until Shabbat (until Friday evening)
    if weekday == 7 {
      daysUntilShabbat = 0 // It's Shabbat!
    } else if weekday == 6 {
      daysUntilShabbat = 0 // It's Friday (Erev Shabbat)
    } else {
      daysUntilShabbat = daysUntilFriday
    }

    // Parasha for the upcoming Shabbat
    let jewishCal = JewishCalendar()
    jewishCal.workingDate = nextSaturday
    let parsha = jewishCal.getParshah()

    let hebrewFormatter = HebrewDateFormatter()
    hebrewFormatter.hebrewFormat = true
    parashaHebrew = hebrewFormatter.formatParsha(parsha: parsha)

    hebrewFormatter.hebrewFormat = false
    parashaEnglish = hebrewFormatter.formatParsha(parsha: parsha)

    // Hebrew date for today
    let todayJewish = JewishCalendar()
    todayJewish.workingDate = today
    let hdf = HebrewDateFormatter()
    hdf.hebrewFormat = true
    hebrewDateString = hdf.format(jewishCalendar: todayJewish)

    hdf.hebrewFormat = false
    hebrewDateEnglish = hdf.format(jewishCalendar: todayJewish)

    // Daf Yomi Bavli
    if let daf = todayJewish.getDafYomiBavli() {
      dafYomiEnglish = "\(daf.getMasechtaTransliterated()) \(daf.getDaf())"
      dafYomiHebrew = "\(daf.getMasechta()) \(daf.getDaf())"
    }

    // Reschedule pre-Shabbat reminder with updated candle lighting time
    ShabbatReminderService.shared.reschedule()
  }

  // MARK: - Helper Methods
  
  /// Get the zman for a specific type.
  func zman(for type: ZmanType) -> Zman? {
    todayZmanim.first { $0.type == type }
  }
  
  /// Get the next upcoming zman.
  func nextZman() -> Zman? {
    let now = Date()
    return todayZmanim.first { $0.time > now }
  }

  /// Format a date as a short time string ("5:12 PM" in 12h mode, "17:12" in 24h).
  func shortTimeString(from date: Date?) -> String {
    guard let date = date else { return "--:--" }
    return TimeFormatter.fullTime(date)
  }
}
