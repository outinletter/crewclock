import SwiftUI
import WidgetKit
import ActivityKit

struct CrewRemainingTime: View {
  let date: Date
  var body: some View {
    let end = max(Date(), date)
    Text(timerInterval: Date()...end, countsDown: true, showsHours: true)
      .frame(width: 76).monospacedDigit()
  }
}

struct CrewAlarmEntry: TimelineEntry { var date: Date; var payload: CrewSurfacePayload }
struct CrewAlarmProvider: TimelineProvider {
  func placeholder(in context: Context) -> CrewAlarmEntry { .init(date: Date(), payload: .empty) }
  func getSnapshot(in context: Context, completion: @escaping (CrewAlarmEntry) -> Void) { completion(read()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<CrewAlarmEntry>) -> Void) {
    let current = read()
    // Re-evaluate at every known alarm expiry, without pretending to reserve another alarm.
    let dates = Set(current.payload.alarms.map(\.date)).filter { $0 > Date() }.sorted()
    let entries = [current] + dates.map { CrewAlarmEntry(date: $0.addingTimeInterval(1), payload: current.payload) }
    completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(900))))
  }
  private func read() -> CrewAlarmEntry {
    let data = UserDefaults(suiteName: CrewSurfacePayload.group)?.data(forKey: CrewSurfacePayload.key)
    let payload = data.flatMap { try? JSONDecoder().decode(CrewSurfacePayload.self, from: $0) } ?? .empty
    return .init(date: Date(), payload: payload)
  }
}
struct CrewNextAlarmView: View {
  let entry: CrewAlarmEntry
  @Environment(\.widgetFamily) var family
  var next: CrewSurfaceAlarm? { entry.payload.alarms.filter { $0.date > entry.date }.min { $0.at < $1.at } }
  var nextRoster: CrewSurfaceAlarm? { entry.payload.alarms.filter { $0.date > entry.date && $0.flightDeparture != nil }.min { $0.at < $1.at } }
  var primary: CrewSurfaceAlarm? { nextRoster ?? next }
  var flightHeader: String {
    let number = entry.payload.flightNumber ?? entry.payload.flight
    let airport = entry.payload.departureAirport ?? ""
    return airport.isEmpty ? number : "\(number) · \(airport)"
  }
  var shortDate: String { CrewSurfaceAlarm.displayDay(entry.payload.departureDate) }
  var flightDetail: String {
    let dep = entry.payload.departureTime ?? "—"
    let from = entry.payload.departureAirport ?? "—"
    let to = entry.payload.arrivalAirport ?? "—"
    let arr = entry.payload.arrivalTime ?? "—"
    return "\(dep) \(from) → \(to) \(arr)"
  }
  @ViewBuilder var content: some View {
    if family == .accessoryRectangular {
      HStack(spacing: 8) {
        Image(systemName: "alarm.fill").foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 1) {
          if entry.payload.allowed, let next = primary {
            Text("\(shortDate) · \(flightHeader.isEmpty ? next.label : flightHeader)")
              .font(.caption).lineLimit(1).minimumScaleFactor(0.6)
            Text(next.clockText).font(.headline).monospacedDigit()
          } else { Text("Open CrewClock to check alarms").font(.caption) }
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 5) {
        Label("CrewClock", systemImage: "alarm.fill").font(.caption).foregroundStyle(.blue)
          .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .leading : .center)
        if entry.payload.allowed, let next = primary {
          if family == .systemSmall {
            Text("\(shortDate) · \(entry.payload.flightNumber ?? entry.payload.flight)")
              .font(.system(size: 16, weight: .bold, design: .rounded))
              .tracking(-0.7)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
              .allowsTightening(true)
            Text(next.label).font(.caption).lineLimit(1)
            Text(next.clockText).font(.title3.bold()).monospacedDigit()
          } else {
            VStack(alignment: .center, spacing: 5) {
              Text("\(shortDate) · \(flightDetail)")
                .font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
              HStack(spacing: 4) {
                Text("\(next.label) · \(next.clockText) · -")
                CrewRemainingTime(date: next.date)
              }.font(.subheadline).lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .center)
          }
        } else {
          Text(entry.payload.allowed ? "No upcoming reservation" : "Open CrewClock to check alarms").font(.caption)
        }
      }
    }
  }
  var body: some View {
    content.foregroundStyle(Color.primary).frame(maxWidth: .infinity, alignment: .leading)
      .widgetURL(URL(string: "crewclock://briefing")).containerBackground(.background, for: .widget)
  }

}
struct CrewNextAlarmWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CrewNextAlarm", provider: CrewAlarmProvider()) { CrewNextAlarmView(entry: $0) }
      .configurationDisplayName("Next CrewClock alarm").description("The next confirmed alarm and its time zone.")
      .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}
struct CrewNextAlarmActivity: Widget {
  private func appIcon(size: CGFloat, cornerRadius: CGFloat) -> some View {
    Image("WidgetAppIcon")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private func offsetText(_ state: CrewNextAlarmAttributes.ContentState) -> String {
    guard let departure = state.flightDeparture else { return state.label }
    let total = max(0, Int((departure.timeIntervalSince(state.date) / 60).rounded()))
    return "-\(total / 60)h \(total % 60)m"
  }
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CrewNextAlarmAttributes.self) { context in
      HStack(alignment: .center, spacing: 10) {
        appIcon(size: 38, cornerRadius: 9)

        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text("CrewClock")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.primary)
            Spacer()
          }

          HStack(spacing: 4) {
            Image(systemName: "airplane")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Color.blue)
            Text("\(String((context.state.departureDate ?? "").suffix(5)).replacingOccurrences(of: "-", with: "/")) · \(context.state.departureTime ?? "—") \(context.state.departureAirport ?? "—") → \(context.state.arrivalAirport ?? "—") \(context.state.arrivalTime ?? "—")")
              .font(.system(size: 13, weight: .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          .foregroundStyle(.primary)

          HStack(spacing: 4) {
            Text("\(context.state.label) · \(CrewSurfaceAlarm.format(context.state.date, zone: context.state.zone, pattern: "HH:mm")) · -")
            CrewRemainingTime(date: context.state.date)
          }
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        }
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .environment(\.timeZone, TimeZone(identifier: context.state.zone) ?? TimeZone(secondsFromGMT: 0)!)
      .activityBackgroundTint(Color.black.opacity(0.35))
      .activitySystemActionForegroundColor(Color.blue)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          appIcon(size: 30, cornerRadius: 7)
        }
        DynamicIslandExpandedRegion(.trailing) { Text(CrewSurfaceAlarm.format(context.state.date, zone: context.state.zone, pattern: "HH:mm")).environment(\.timeZone, TimeZone(identifier: context.state.zone) ?? TimeZone(secondsFromGMT: 0)!) }
        DynamicIslandExpandedRegion(.bottom) { Text(context.state.label).lineLimit(1) }
      } compactLeading: {
        appIcon(size: 18, cornerRadius: 4)
      }
        compactTrailing: { Text(CrewSurfaceAlarm.format(context.state.date, zone: context.state.zone, pattern: "HH:mm")).environment(\.timeZone, TimeZone(identifier: context.state.zone) ?? TimeZone(secondsFromGMT: 0)!).font(.caption2) }
        minimal: {
          appIcon(size: 18, cornerRadius: 4)
        }
        .widgetURL(URL(string: "crewclock://alarms"))
        .keylineTint(Color(red: 0.65, green: 0.81, blue: 0.96))
    }
  }
}
@main struct CrewClockWidgetBundle: WidgetBundle { var body: some Widget { CrewNextAlarmWidget(); CrewNextAlarmActivity() } }
