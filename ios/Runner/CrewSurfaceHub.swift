import Foundation
import UIKit
import WidgetKit
import ActivityKit
import AppIntents
import AlarmKit

@available(iOS 16.2, *)
final class CrewSurfaceHub: NSObject {
  static let shared = CrewSurfaceHub()
  private var payload = CrewSurfacePayload.empty
  private var activationTimer: Timer?
  private func displayStart(for alarm: CrewSurfaceAlarm) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: alarm.zone) ?? TimeZone(secondsFromGMT: 0)!
    let previousDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: alarm.date))!
    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: previousDay)!
  }
  override init() {
    super.init()
  }
  @MainActor func publish(_ raw: [String: Any]) async throws {
    let data = try JSONSerialization.data(withJSONObject: raw["payload"] as? [String: Any] ?? [:])
    payload = try JSONDecoder().decode(CrewSurfacePayload.self, from: data)
    UserDefaults(suiteName: CrewSurfacePayload.group)?.set(data, forKey: CrewSurfacePayload.key)
    WidgetCenter.shared.reloadAllTimelines()
    let enabled = raw["liveActivity"] as? Bool == true
    UserDefaults.standard.set(enabled, forKey: "crewclock.liveActivity")
    if enabled && !ActivityAuthorizationInfo().areActivitiesEnabled {
      throw NSError(domain: "CrewClock", code: 7, userInfo: [NSLocalizedDescriptionKey: "Enable Live Activities for CrewClock in iPhone Settings."])
    }
    let upcoming = payload.alarms.filter { $0.date > Date() }
    let candidate = upcoming.filter { $0.flightDeparture != nil }.min { $0.at < $1.at } ?? payload.next
    let start = candidate.map { displayStart(for: $0) }
    let next = start.map { Date() >= $0 } == true ? candidate : nil
    activationTimer?.invalidate()
    if enabled, let start, start > Date() {
      activationTimer = Timer.scheduledTimer(withTimeInterval: start.timeIntervalSinceNow, repeats: false) { _ in
        Task { @MainActor in await self.refreshFromSystem() }
      }
    }
    for activity in Activity<CrewNextAlarmAttributes>.activities {
      if !enabled || !payload.allowed || next?.id != activity.attributes.alarmID {
        await activity.end(nil, dismissalPolicy: .immediate)
      } else if let next {
        await activity.update(ActivityContent(state: state(next), staleDate: next.date))
      }
    }
    if enabled, payload.allowed, let next, ActivityAuthorizationInfo().areActivitiesEnabled,
      UIApplication.shared.applicationState == .active,
      !Activity<CrewNextAlarmAttributes>.activities.contains(where: { $0.attributes.alarmID == next.id }) {
      _ = try Activity.request(attributes: CrewNextAlarmAttributes(alarmID: next.id), content: ActivityContent(state: state(next), staleDate: next.date), pushType: nil)
    }
  }
  @MainActor func refreshFromSystem() async {
    guard #available(iOS 26.0, *) else { return }
    let defaults = UserDefaults.standard
    guard let data = UserDefaults(suiteName: CrewSurfacePayload.group)?.data(forKey: CrewSurfacePayload.key),
      var cached = try? JSONDecoder().decode(CrewSurfacePayload.self, from: data),
      let live = try? AlarmManager.shared.alarms else { return }
    let mappings = (defaults.dictionary(forKey: "crewclock.alarmIDs") as? [String: String] ?? [:]).merging(defaults.dictionary(forKey: "crewclock.intervalAlarmIDs") as? [String: String] ?? [:]) { _, right in right }
    cached.alarms = cached.alarms.compactMap { entry in
      guard let raw = mappings[entry.id], let alarm = live.first(where: { $0.id.uuidString == raw }), case .fixed(let date) = alarm.schedule else { return nil }
      var updated = entry; updated.at = date.timeIntervalSince1970; return updated
    }
    cached.allowed = AlarmManager.shared.authorizationState == .authorized
    cached.updatedAt = Date().timeIntervalSince1970
    guard let updatedData = try? JSONEncoder().encode(cached), let json = try? JSONSerialization.jsonObject(with: updatedData) else { return }
    try? await publish(["payload": json, "liveActivity": defaults.bool(forKey: "crewclock.liveActivity")])
  }
  private func state(_ alarm: CrewSurfaceAlarm) -> CrewNextAlarmAttributes.ContentState {
    .init(label: alarm.label, date: alarm.date, zone: alarm.zone,
          flight: payload.flight, flightNumber: payload.flightNumber,
          departureDate: payload.departureDate,
          departureAirport: payload.departureAirport,
          arrivalAirport: payload.arrivalAirport,
          departureTime: payload.departureTime,
          arrivalTime: payload.arrivalTime,
          flightDeparture: alarm.flightDeparture.map(Date.init(timeIntervalSince1970:)))
  }
}

@available(iOS 16.2, *)
struct OpenCrewClockAlarmIntent: AppIntent {
  static var title: LocalizedStringResource = "View next CrewClock alarm"
  static var openAppWhenRun = true
  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set(true, forKey: "crewclock.openAlarms")
    NotificationCenter.default.post(name: Notification.Name("crewclock.openAlarms"), object: nil)
    return .result()
  }
}
@available(iOS 16.2, *)
struct CrewClockShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: OpenCrewClockAlarmIntent(), phrases: ["Show my next alarm in \(.applicationName)"], shortTitle: "Next alarm", systemImageName: "alarm")
  }
}
