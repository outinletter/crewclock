import Foundation
import SwiftUI
import AlarmKit
import ActivityKit
import AppIntents
import AVFoundation
import WidgetKit
import UIKit

struct CrewAlarmMetadata: AlarmMetadata { var sourceID: String }

struct AlarmStatus: Equatable {
    var state: String
    var next: Date?
}

extension Notification.Name {
    static let crewAlarmDismissed = Notification.Name("crewclock.alarmDismissed")
}

/// Reserves system alarms with AlarmKit. Source IDs are the app's record IDs;
/// the UUID AlarmKit needs is kept in UserDefaults.
enum AlarmEngine {
    static let defaults = UserDefaults.standard
    static let intervalKey = "crewclock.intervals.v2"

    static var authorized: Bool { AlarmManager.shared.authorizationState == .authorized }
    static var undetermined: Bool { AlarmManager.shared.authorizationState == .notDetermined }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        if undetermined { _ = try? await AlarmManager.shared.requestAuthorization() }
        return authorized
    }

    private static func mapping(_ key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static var sound: AlertConfiguration.AlertSound {
        defaults.string(forKey: "crewclock.sound").map { .named($0) } ?? .default
    }

    // MARK: One-shot alarms

    static func sync(_ records: [AlarmRecord], requestPermission: Bool, retryLimit: Bool = true) async throws {
        let manager = AlarmManager.shared
        if requestPermission && manager.authorizationState == .notDetermined {
            _ = try await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else {
            if requestPermission && records.contains(where: { $0.active && $0.time > Date() }) {
                throw AppError("Allow CrewClock alarms in Settings > Apps > CrewClock.")
            }
            return
        }
        var map = mapping("crewclock.alarmIDs")
        var signatures = mapping("crewclock.alarmSignatures")
        let live = try manager.alarms
        if records.isEmpty {
            for alarm in live where map.values.contains(alarm.id.uuidString) { try manager.cancel(id: alarm.id) }
            for key in ["crewclock.alarmIDs", "crewclock.alarmSignatures", "crewclock.queuedAlarmIDs", "crewclock.alarmCapacity"] {
                defaults.removeObject(forKey: key)
            }
            return
        }
        let now = Date()
        let eligible = records.filter { $0.active && $0.time > now }
            .sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        let limit = defaults.object(forKey: "crewclock.alarmCapacity") as? Int
        let protectedCount = live.filter { $0.state != .scheduled }.count
        let selected = limit.map { Array(eligible.prefix(max(0, $0 - protectedCount))) } ?? eligible
        let selectedIDs = Set(selected.map(\.id))
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (source, value) in map {
            guard let uuid = UUID(uuidString: value) else { continue }
            let record = byID[source]
            let scheduled = live.first { $0.id == uuid }?.state == .scheduled
            let stale = record == nil || record?.dismissed == true || record?.armed == false
            if stale || (scheduled && !selectedIDs.contains(source)) {
                if live.contains(where: { $0.id == uuid }) { try manager.cancel(id: uuid) }
                map.removeValue(forKey: source)
                signatures.removeValue(forKey: source)
            }
        }
        defaults.set(map, forKey: "crewclock.alarmIDs")
        defaults.set(signatures, forKey: "crewclock.alarmSignatures")
        let soundName = defaults.string(forKey: "crewclock.sound") ?? "default"
        for record in selected where record.time > Date() {
            let source = record.id
            let label = record.label.isEmpty ? "CrewClock Alarm" : record.label
            let signature = "\(record.time.timeIntervalSince1970)" + label + soundName
            let uuid = map[source].flatMap(UUID.init(uuidString:)) ?? UUID()
            if live.contains(where: { $0.id == uuid && $0.state != .scheduled }) { continue }
            if signatures[source] == signature && live.contains(where: { $0.id == uuid }) { continue }
            // Updating a scheduled alarm must not need an extra slot at capacity.
            if live.contains(where: { $0.id == uuid }) {
                try manager.cancel(id: uuid)
                signatures.removeValue(forKey: source)
                defaults.set(signatures, forKey: "crewclock.alarmSignatures")
            }
            do {
                _ = try await manager.schedule(id: uuid, configuration: config(source: source, label: label, date: record.time, uuid: uuid))
            } catch {
                let native = error as NSError
                let limitError = AlarmManager.AlarmError.maximumLimitReached as NSError
                guard native.domain == limitError.domain && native.code == limitError.code else { throw error }
                let capacity = try manager.alarms.count
                defaults.set(capacity, forKey: "crewclock.alarmCapacity")
                if retryLimit && capacity > 0 {
                    try await sync(records, requestPermission: false, retryLimit: false)
                    return
                }
                break
            }
            map[source] = uuid.uuidString
            signatures[source] = signature
            defaults.set(map, forKey: "crewclock.alarmIDs")
            defaults.set(signatures, forKey: "crewclock.alarmSignatures")
        }
        let registered = Set(try manager.alarms.map { $0.id.uuidString })
        let queued = eligible.map(\.id).filter { source in
            guard let raw = map[source] else { return true }
            return !registered.contains(raw)
        }
        defaults.set(queued, forKey: "crewclock.queuedAlarmIDs")
    }

    static func config(source: String, label: String, date: Date, uuid: UUID)
        -> AlarmManager.AlarmConfiguration<CrewAlarmMetadata> {
        let snooze = AlarmButton(text: "Snooze 5 min", textColor: .white, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = .init(title: LocalizedStringResource(stringLiteral: label),
                          secondaryButton: snooze, secondaryButtonBehavior: .custom)
        } else {
            alert = .init(title: LocalizedStringResource(stringLiteral: label),
                          stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                          secondaryButton: snooze, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: CrewAlarmMetadata(sourceID: source), tintColor: Color.blue)
        return .alarm(schedule: .fixed(date), attributes: attributes,
                      stopIntent: CrewStopIntent(alarmID: uuid.uuidString),
                      secondaryIntent: CrewSnoozeIntent(alarmID: uuid.uuidString, sourceID: source, label: label),
                      sound: sound)
    }

    static func dismiss(_ uuid: UUID) throws {
        if try AlarmManager.shared.alarms.contains(where: { $0.id == uuid }) {
            try AlarmManager.shared.stop(id: uuid)
        }
        if let source = mapping("crewclock.alarmIDs").first(where: { $0.value == uuid.uuidString })?.key {
            recordDismissal(source)
        }
    }

    static func recordDismissal(_ source: String) {
        var ids = defaults.stringArray(forKey: "crewclock.dismissed") ?? []
        if !ids.contains(source) { ids.append(source) }
        defaults.set(ids, forKey: "crewclock.dismissed")
        NotificationCenter.default.post(name: .crewAlarmDismissed, object: nil)
    }

    static func takeDismissed() -> [String] {
        let ids = defaults.stringArray(forKey: "crewclock.dismissed") ?? []
        defaults.removeObject(forKey: "crewclock.dismissed")
        return ids
    }

    /// Stops whatever is ringing right now.
    static func stopRinging() async {
        guard let live = try? AlarmManager.shared.alarms else { return }
        let intervals = mapping("crewclock.intervalAlarmIDs")
        for alarm in live where alarm.state == .alerting {
            if let source = intervals.first(where: { $0.value == alarm.id.uuidString })?.key {
                try? await advance(sourceID: source, alarmID: alarm.id.uuidString)
            } else {
                try? dismiss(alarm.id)
            }
        }
    }

    // MARK: Repeating reminders

    static func loadIntervals() -> [IntervalReminder] {
        guard let data = defaults.data(forKey: intervalKey) else { return [] }
        return (try? JSONDecoder().decode([IntervalReminder].self, from: data)) ?? []
    }

    private static func storeIntervals(_ records: [IntervalReminder]) {
        defaults.set(try? JSONEncoder().encode(records), forKey: intervalKey)
    }

    static func nextDate(_ record: IntervalReminder) -> Date {
        let step = Double(record.minutes) * 60
        let anchor = record.anchor.timeIntervalSince1970
        let elapsed = max(0, Date().timeIntervalSince1970 - anchor)
        let count = floor(elapsed / step) + 1
        return Date(timeIntervalSince1970: anchor + count * step)
    }

    static func syncIntervals(_ records: [IntervalReminder], requestPermission: Bool) async throws -> [IntervalReminder] {
        guard records.count <= 16 else { throw AppError("Up to 16 repeating reminders are allowed.") }
        for r in records {
            let label = r.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.count <= 100, (1...10080).contains(r.minutes) else {
                throw AppError("Invalid repeating reminder.")
            }
        }
        let manager = AlarmManager.shared
        if records.contains(where: \.enabled) {
            if requestPermission && manager.authorizationState == .notDetermined {
                _ = try await manager.requestAuthorization()
            }
            guard manager.authorizationState == .authorized else {
                throw AppError("Allow CrewClock alarms in Settings > Apps > CrewClock.")
            }
        }
        let previous = loadIntervals()
        var map = mapping("crewclock.intervalAlarmIDs")
        let live = (try? manager.alarms) ?? []
        var saved = records
        var added: [UUID] = []
        var replaced: [String] = []
        do {
            for index in saved.indices where saved[index].enabled {
                let record = saved[index]
                let old = previous.first { $0.id == record.id }
                let unchanged = old?.enabled == true && old?.minutes == record.minutes && old?.label == record.label
                if unchanged, let raw = map[record.id], let uuid = UUID(uuidString: raw), live.contains(where: { $0.id == uuid }) {
                    saved[index].anchor = old?.anchor ?? record.anchor
                    continue
                }
                let uuid = UUID()
                saved[index].anchor = unchanged ? (old?.anchor ?? Date()) : Date()
                let date = nextDate(saved[index])
                _ = try await manager.schedule(id: uuid, configuration: intervalConfig(saved[index], uuid: uuid, date: date))
                added.append(uuid)
                if let raw = map[record.id] { replaced.append(raw) }
                map[record.id] = uuid.uuidString
            }
        } catch {
            for uuid in added { try? manager.cancel(id: uuid) }
            throw error
        }
        let wanted = Set(saved.filter(\.enabled).map(\.id))
        for (id, raw) in map where !wanted.contains(id) {
            if let uuid = UUID(uuidString: raw), live.contains(where: { $0.id == uuid }) { try? manager.cancel(id: uuid) }
            map.removeValue(forKey: id)
        }
        for raw in replaced {
            if let uuid = UUID(uuidString: raw), live.contains(where: { $0.id == uuid }) { try? manager.cancel(id: uuid) }
        }
        defaults.set(map, forKey: "crewclock.intervalAlarmIDs")
        storeIntervals(saved)
        return saved
    }

    static func intervalConfig(_ record: IntervalReminder, uuid: UUID, date: Date)
        -> AlarmManager.AlarmConfiguration<CrewAlarmMetadata> {
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = .init(title: LocalizedStringResource(stringLiteral: record.label))
        } else {
            alert = .init(title: LocalizedStringResource(stringLiteral: record.label),
                          stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: CrewAlarmMetadata(sourceID: record.id), tintColor: Color.blue)
        return .alarm(schedule: .fixed(date), attributes: attributes,
                      stopIntent: CrewIntervalStopIntent(sourceID: record.id, alarmID: uuid.uuidString), sound: sound)
    }

    /// Reserves the next occurrence before stopping the current one.
    static func advance(sourceID: String, alarmID: String) async throws {
        var map = mapping("crewclock.intervalAlarmIDs")
        guard map[sourceID] == alarmID, let uuid = UUID(uuidString: alarmID) else { return }
        var records = loadIntervals()
        guard let index = records.firstIndex(where: { $0.id == sourceID && $0.enabled }) else { return }
        records[index].anchor = Date()
        let nextID = UUID()
        _ = try await AlarmManager.shared.schedule(
            id: nextID, configuration: intervalConfig(records[index], uuid: nextID, date: nextDate(records[index])))
        map[sourceID] = nextID.uuidString
        storeIntervals(records)
        defaults.set(map, forKey: "crewclock.intervalAlarmIDs")
        if try AlarmManager.shared.alarms.contains(where: { $0.id == uuid }) {
            try AlarmManager.shared.stop(id: uuid)
        }
        NotificationCenter.default.post(name: .crewAlarmDismissed, object: nil)
    }

    // MARK: Status

    static func statuses(sources: [String]) -> [String: AlarmStatus] {
        var status: [String: AlarmStatus] = [:]
        let allowed = authorized
        if allowed, let live = try? AlarmManager.shared.alarms {
            for key in ["crewclock.alarmIDs", "crewclock.intervalAlarmIDs"] {
                for (source, raw) in mapping(key) {
                    var entry = AlarmStatus(state: "waiting", next: nil)
                    if let alarm = live.first(where: { $0.id.uuidString == raw }) {
                        entry.state = alarm.state == .alerting ? "alerting" : "scheduled"
                        if case .fixed(let date) = alarm.schedule { entry.next = date }
                    }
                    status[source] = entry
                }
            }
        }
        for source in sources where status[source] == nil {
            status[source] = AlarmStatus(state: allowed ? "waiting" : "permission", next: nil)
        }
        return status
    }

    // MARK: Sound

    static let soundChoices: [(label: String, name: String)] = [("System Default", ""), ("CrewClock Beep", "crewclock_beep.caf")]
    private static var preview: AVAudioPlayer?

    static var soundLabel: String {
        let name = defaults.string(forKey: "crewclock.sound") ?? ""
        return soundChoices.first { $0.name == name }?.label ?? "System Default"
    }

    static func chooseSound(_ name: String) throws {
        if !name.isEmpty {
            let url = try makeSound(name)
            preview = try AVAudioPlayer(contentsOf: url)
            preview?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { preview?.stop() }
        }
        defaults.set(name.isEmpty ? nil : name, forKey: "crewclock.sound")
    }

    private static func makeSound(_ name: String) throws -> URL {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let count = AVAudioFrameCount(22050 * 28)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(count) {
            let t = Double(i) / 22050
            let phase = t.truncatingRemainder(dividingBy: 1)
            let rise = phase / 0.02
            let fall = (0.7 - phase) / 0.02
            let envelope = max(0, min(1, min(rise, fall)))
            samples[i] = Float(0.3 * envelope * sin(2 * Double.pi * 880 * t))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

struct CrewStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop CrewClock Alarm"
    @Parameter(title: "Alarm ID") var alarmID: String
    init() {}
    init(alarmID: String) { self.alarmID = alarmID }
    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: alarmID) { try AlarmEngine.dismiss(uuid) }
        return .result()
    }
}

struct CrewSnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze CrewClock Alarm"
    @Parameter(title: "Alarm ID") var alarmID: String
    @Parameter(title: "Source ID") var sourceID: String
    @Parameter(title: "Label") var label: String
    init() {}
    init(alarmID: String, sourceID: String, label: String) {
        self.alarmID = alarmID; self.sourceID = sourceID; self.label = label
    }
    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.stop(id: uuid)
        _ = try await AlarmManager.shared.schedule(
            id: uuid, configuration: AlarmEngine.config(source: sourceID, label: label,
                                                        date: Date().addingTimeInterval(300), uuid: uuid))
        return .result()
    }
}

struct CrewIntervalStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop and repeat interval reminder"
    @Parameter(title: "Source ID") var sourceID: String
    @Parameter(title: "Alarm ID") var alarmID: String
    init() {}
    init(sourceID: String, alarmID: String) { self.sourceID = sourceID; self.alarmID = alarmID }
    func perform() async throws -> some IntentResult {
        try await AlarmEngine.advance(sourceID: sourceID, alarmID: alarmID)
        return .result()
    }
}

/// Publishes the next alarms to the widget and the Lock Screen Live Activity.
@MainActor
final class SurfaceHub {
    static let shared = SurfaceHub()
    private var timer: Timer?

    private func displayStart(for alarm: CrewSurfaceAlarm) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: alarm.zone) ?? TimeZone(secondsFromGMT: 0)!
        let previousDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: alarm.date))!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: previousDay)!
    }

    func publish(_ payload: CrewSurfacePayload, liveActivity enabled: Bool) async throws {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults(suiteName: CrewSurfacePayload.group)?.set(data, forKey: CrewSurfacePayload.key)
        }
        WidgetCenter.shared.reloadAllTimelines()
        if enabled && !ActivityAuthorizationInfo().areActivitiesEnabled {
            throw AppError("Enable Live Activities for CrewClock in iPhone Settings.")
        }
        let upcoming = payload.alarms.filter { $0.date > Date() }
        let candidate = upcoming.filter { $0.flightDeparture != nil }.min { $0.at < $1.at } ?? payload.next
        let start = candidate.map { displayStart(for: $0) }
        let next: CrewSurfaceAlarm? = (start.map { Date() >= $0 } == true) ? candidate : nil
        timer?.invalidate()
        if enabled, let start, start > Date() {
            timer = Timer.scheduledTimer(withTimeInterval: start.timeIntervalSinceNow, repeats: false) { _ in
                NotificationCenter.default.post(name: .crewAlarmDismissed, object: nil)
            }
        }
        func state(_ alarm: CrewSurfaceAlarm) -> CrewNextAlarmAttributes.ContentState {
            .init(label: alarm.label, date: alarm.date, zone: alarm.zone, flight: payload.flight,
                  flightNumber: payload.flightNumber, departureDate: payload.departureDate,
                  departureAirport: payload.departureAirport, arrivalAirport: payload.arrivalAirport,
                  departureTime: payload.departureTime, arrivalTime: payload.arrivalTime,
                  flightDeparture: alarm.flightDeparture.map(Date.init(timeIntervalSince1970:)))
        }
        for activity in Activity<CrewNextAlarmAttributes>.activities {
            if !enabled || !payload.allowed || next?.id != activity.attributes.alarmID {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else if let next {
                await activity.update(ActivityContent(state: state(next), staleDate: next.date))
            }
        }
        if enabled, payload.allowed, let next, UIApplication.shared.applicationState == .active,
           !Activity<CrewNextAlarmAttributes>.activities.contains(where: { $0.attributes.alarmID == next.id }) {
            _ = try Activity.request(attributes: CrewNextAlarmAttributes(alarmID: next.id),
                                     content: ActivityContent(state: state(next), staleDate: next.date), pushType: nil)
        }
    }
}
