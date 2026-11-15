import Foundation
struct CrewSurfaceAlarm: Codable, Identifiable {
  var id: String
  var label: String
  var at: Double
  var zone: String
  var flightDeparture: Double?
  var date: Date { Date(timeIntervalSince1970: at) }
  var clockText: String { Self.format(date, zone: zone, pattern: "HH:mm") }
  var dayText: String { Self.format(date, zone: zone, pattern: "MM/dd EEE") }
  static func displayDay(_ value: String?) -> String {
    guard let value = value else { return "" }
    let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: value) else { return value }
    return format(date, zone: "UTC", pattern: "MM/dd EEE")
  }
  static func format(_ date: Date, zone: String, pattern: String) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!; formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
struct CrewSurfacePayload: Codable {
  var updatedAt: Double
  var alarms: [CrewSurfaceAlarm]
  var flight: String
  var flightNumber: String?
  var departureDate: String?
  var departureAirport: String?
  var arrivalAirport: String?
  var departureTime: String?
  var arrivalTime: String?
  var allowed: Bool
  var next: CrewSurfaceAlarm? { alarms.filter { $0.date > Date() }.min { $0.at < $1.at } }
  static let empty = CrewSurfacePayload(updatedAt: 0, alarms: [], flight: "", flightNumber: nil, departureAirport: nil, arrivalAirport: nil, departureTime: nil, arrivalTime: nil, allowed: false)
  static let key = "crewclock.surface.payload"
  static let group = "group.com.addvalue.crewclock"
}
#if os(iOS)
import ActivityKit
@available(iOS 16.2, *)
struct CrewNextAlarmAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var label: String
    var date: Date
    var zone: String
    var flight: String
    var flightNumber: String?
    var departureDate: String?
    var departureAirport: String?
    var arrivalAirport: String?
    var departureTime: String?
    var arrivalTime: String?
    var flightDeparture: Date?
  }
  var alarmID: String
}
#endif
