import Foundation
import CoreLocation
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
  @Published var candleLightingDateLabel: String = "Friday Evening"
  @Published var havdalahDateLabel: String = "Saturday Night"
  @Published var sunriseTime: Date?
  @Published var sunsetTime: Date?

  private let locationManager = LocationManager.shared
  
  private init() {}
  
  // MARK: - Zman Model
  
  struct Zman: Identifiable {
    let id = UUID()
    let type: ZmanType
    let time: Date
    let hebrewName: String
    let englishName: String
    let description: String
    
    var timeString: String {
      let formatter = DateFormatter()
      formatter.dateFormat = "h:mm a"
      return formatter.string(from: time)
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
      case .alotHashachar: return "72 minutes before sunrise"
      case .misheyakir: return "Earliest time for tallit and tefillin"
      case .netz: return "Sunrise - ideal start of Shacharit"
      case .sofZmanShma: return "Latest time for morning Shema (GRA)"
      case .sofZmanTefila: return "Latest time for Shacharit Amidah"
      case .chatzot: return "Halachic midday"
      case .minchaGedola: return "Earliest time for Mincha"
      case .minchaKetana: return "Preferable time for Mincha"
      case .plagHamincha: return "1.25 hours before sunset"
      case .shkia: return "Sunset - start of evening"
      case .tzeitHakochavim: return "Nightfall - 3 stars visible"
      }
    }
  }
  
  // MARK: - Calculate Zmanim
  
  /// Calculate today's zmanim for the current location using KosherSwift.
  func calculateTodayZmanim() {
    isLoading = true
    
    let location = locationManager.currentOrDefaultLocation
    let today = Date()
    
    // Create GeoLocation for KosherSwift
    let geoLocation = GeoLocation(
      locationName: locationManager.locationName,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timeZone: TimeZone.current
    )
    
    // Create ComplexZmanimCalendar
    let calendar = ComplexZmanimCalendar(location: geoLocation)
    calendar.workingDate = today
    
    // Calculate all zmanim
    var zmanim: [Zman] = []
    
    // Alot HaShachar (72 minutes before sunrise - GRA)
    if let alot = calendar.getAlos72() {
      zmanim.append(Zman(
        type: .alotHashachar,
        time: alot,
        hebrewName: ZmanType.alotHashachar.hebrewName,
        englishName: ZmanType.alotHashachar.englishName,
        description: ZmanType.alotHashachar.description
      ))
    }
    
    // Misheyakir (earliest tallit - 36 minutes before sunrise)
    if let misheyakir = calendar.getMisheyakir10Point2Degrees() {
      zmanim.append(Zman(
        type: .misheyakir,
        time: misheyakir,
        hebrewName: ZmanType.misheyakir.hebrewName,
        englishName: ZmanType.misheyakir.englishName,
        description: ZmanType.misheyakir.description
      ))
    }
    
    // Netz (Sunrise)
    if let sunrise = calendar.getSunrise() {
      zmanim.append(Zman(
        type: .netz,
        time: sunrise,
        hebrewName: ZmanType.netz.hebrewName,
        englishName: ZmanType.netz.englishName,
        description: ZmanType.netz.description
      ))
    }
    
    // Sof Zman Shma (Latest Shema - GRA)
    if let sofShma = calendar.getSofZmanShmaGRA() {
      zmanim.append(Zman(
        type: .sofZmanShma,
        time: sofShma,
        hebrewName: ZmanType.sofZmanShma.hebrewName,
        englishName: ZmanType.sofZmanShma.englishName,
        description: ZmanType.sofZmanShma.description
      ))
    }
    
    // Sof Zman Tefila (Latest Shacharit - GRA)
    if let sofTefila = calendar.getSofZmanTfilaGRA() {
      zmanim.append(Zman(
        type: .sofZmanTefila,
        time: sofTefila,
        hebrewName: ZmanType.sofZmanTefila.hebrewName,
        englishName: ZmanType.sofZmanTefila.englishName,
        description: ZmanType.sofZmanTefila.description
      ))
    }
    
    // Chatzot (Midday)
    if let chatzot = calendar.getChatzos() {
      zmanim.append(Zman(
        type: .chatzot,
        time: chatzot,
        hebrewName: ZmanType.chatzot.hebrewName,
        englishName: ZmanType.chatzot.englishName,
        description: ZmanType.chatzot.description
      ))
    }
    
    // Mincha Gedola (Earliest Mincha - 30 minutes after chatzot)
    if let minchaGedola = calendar.getMinchaGedola() {
      zmanim.append(Zman(
        type: .minchaGedola,
        time: minchaGedola,
        hebrewName: ZmanType.minchaGedola.hebrewName,
        englishName: ZmanType.minchaGedola.englishName,
        description: ZmanType.minchaGedola.description
      ))
    }
    
    // Mincha Ketana (Preferable Mincha time)
    if let minchaKetana = calendar.getMinchaKetana() {
      zmanim.append(Zman(
        type: .minchaKetana,
        time: minchaKetana,
        hebrewName: ZmanType.minchaKetana.hebrewName,
        englishName: ZmanType.minchaKetana.englishName,
        description: ZmanType.minchaKetana.description
      ))
    }
    
    // Plag HaMincha
    if let plag = calendar.getPlagHamincha() {
      zmanim.append(Zman(
        type: .plagHamincha,
        time: plag,
        hebrewName: ZmanType.plagHamincha.hebrewName,
        englishName: ZmanType.plagHamincha.englishName,
        description: ZmanType.plagHamincha.description
      ))
    }
    
    // Shkia (Sunset)
    if let sunset = calendar.getSunset() {
      zmanim.append(Zman(
        type: .shkia,
        time: sunset,
        hebrewName: ZmanType.shkia.hebrewName,
        englishName: ZmanType.shkia.englishName,
        description: ZmanType.shkia.description
      ))
    }
    
    // Tzeis HaKochavim (Nightfall - 3 medium stars)
    if let tzeis = calendar.getTzais() {
      zmanim.append(Zman(
        type: .tzeitHakochavim,
        time: tzeis,
        hebrewName: ZmanType.tzeitHakochavim.hebrewName,
        englishName: ZmanType.tzeitHakochavim.englishName,
        description: ZmanType.tzeitHakochavim.description
      ))
    }
    
    todayZmanim = zmanim
    lastUpdated = Date()
    isLoading = false

    // Store sunrise/sunset for the daylight arc
    sunriseTime = calendar.getSunrise()
    sunsetTime = calendar.getSunset()

    // Calculate Shabbat times
    calculateShabbatTimes()
  }

  // MARK: - Shabbat Times

  /// Calculate candle lighting (Friday) and havdalah (Saturday) times for the upcoming Shabbat.
  private func calculateShabbatTimes() {
    let location = locationManager.currentOrDefaultLocation
    let geoLocation = GeoLocation(
      locationName: locationManager.locationName,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timeZone: TimeZone.current
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
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    candleLightingDateLabel = formatter.string(from: nextFriday) + " Evening"
    havdalahDateLabel = formatter.string(from: nextSaturday) + " Night"
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

  /// Format a date as a short time string (e.g., "5:12 PM").
  func shortTimeString(from date: Date?) -> String {
    guard let date = date else { return "--:--" }
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
  }
}
