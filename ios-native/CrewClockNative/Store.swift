import Foundation
import SwiftUI
import Observation

struct RibbonAxis: Identifiable {
    let label: String
    let ticks: [(x: Double, text: String)]
    var id: String { label }
}

struct DutyRibbon {
    var dep = 0.0
    var arr: Double?
    var prep = 0.0
    var steps: [Double] = []
    var axes: [RibbonAxis] = []
    var wocl: [(from: Double, to: Double)] = []
    var home = ""
    var woclFlightMinutes: Int?
    var blockMinutes: Int?
    var now: Double?
}

struct RestPlan {
    var periods: [(start: Date, end: Date)]
    var alarms: [AlarmRecord]
}

@MainActor @Observable
final class AppStore {
    let parser = RosterParser()
    var flights: [Flight] = []
    var alarms: [AlarmRecord] = []
    var intervals: [IntervalReminder] = []
    var duties: [Duty] = []
    var documents: [DocumentItem] = []
    var settings = AppSettings()
    var briefings: [String: BriefingState] = [:]
    var statuses: [String: AlarmStatus] = [:]
    var alarmAllowed = true
    var notice: String?
    var surfaceError: String?
    var busy = false
    var selectedFlightID: String?
    var rosterDay = ""
    var followUpcoming = true
    var tab = 0

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("crewclock_state.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            flights = state.flights
            alarms = state.alarms
            duties = state.duties
            settings = state.settings
            briefings = state.briefings
            documents = state.documents
        }
        intervals = AlarmEngine.loadIntervals()
        rosterDay = Fmt.ymd(Date(), zone: deviceZone)
    }

    private func persist() {
        let state = PersistedState(flights: flights, alarms: alarms, duties: duties, settings: settings, briefings: briefings, documents: documents)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: fileURL, options: .atomic) }
    }

    func newID() -> String { String(Int(Date().timeIntervalSince1970 * 1_000_000)) }

    // MARK: Lookup

    var deviceZone: String { TimeZone.current.identifier }
    var home: String { settings.codes(domestic: false)[0] }
    var homeZone: String { zone(home) ?? "UTC" }
    func zone(_ airport: String) -> String? { settings.airportZones[airport] ?? parser.zone(airport) }

    /// Zone used to display flight times: UTC when the Z switch is on.
    func shown(_ airport: String) -> String? { settings.displayUTC ? "UTC" : zone(airport) }
    var suffix: String { settings.displayUTC ? "Z" : "L" }

    /// Time on the ground between the previous arrival and this departure.
    func groundGap(before f: Flight) -> (minutes: Int, previous: Flight)? {
        guard let previous = sortedFlights.last(where: { $0.departure < f.departure }),
              let arrival = previous.arrival else { return nil }
        let minutes = Int(f.departure.timeIntervalSince(arrival) / 60)
        return minutes >= 0 ? (minutes, previous) : nil
    }

    /// Layover at the destination until the next flight leaves from there.
    func layover(after f: Flight) -> (minutes: Int, next: Flight)? {
        guard let arrival = f.arrival,
              let next = sortedFlights.first(where: { $0.departure > f.departure }),
              next.from == f.to else { return nil }
        let minutes = Int(next.departure.timeIntervalSince(arrival) / 60)
        return minutes >= 0 ? (minutes, next) : nil
    }

    static func gapText(_ minutes: Int) -> String {
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        return days > 0 ? "\(days)d \(hours)h \(mins)m" : "\(hours)h \(mins)m"
    }

    var expiringDocuments: [DocumentItem] {
        documents.filter { $0.daysLeft <= 90 }.sorted { $0.expiry < $1.expiry }
    }

    func saveDocument(_ item: DocumentItem) {
        documents.removeAll { $0.id == item.id }
        documents.append(item)
        documents.sort { $0.expiry < $1.expiry }
        persist()
    }

    func deleteDocument(_ id: String) {
        documents.removeAll { $0.id == id }
        persist()
    }

    var sortedFlights: [Flight] { flights.sorted { $0.departure < $1.departure } }
    func flight(_ id: String?) -> Flight? { flights.first { $0.id == id } }
    var upcomingFlight: Flight? { sortedFlights.first { $0.departure > Date() } }
    var briefingFlight: Flight? {
        if let f = flight(selectedFlightID), f.departure > Date() { return f }
        return upcomingFlight
    }

    func flightAlarms(_ f: Flight) -> [AlarmRecord] {
        alarms.filter { $0.kind == .flight && $0.flightID == f.id }.sorted { $0.time < $1.time }
    }

    func flightLabel(_ f: Flight) -> String {
        "\(Fmt.ymd(f.departure, zone: zone(f.from))) \(f.number) \(f.from) → \(f.to)"
    }

    func group(_ f: Flight, _ s: AppSettings) -> PresetGroup {
        if s.codes(domestic: true).contains(f.from) { return .dom }
        if s.codes(domestic: false).contains(f.from) { return .base }
        return .intl
    }

    func buildFlightAlarms(_ f: Flight) -> [AlarmRecord] {
        settings.presetList(group(f, settings)).map { p in
            AlarmRecord(id: "\(f.id)_\(p.id)", label: p.label,
                        time: f.departure.addingTimeInterval(-Double(p.minutes) * 60), kind: .flight, flightID: f.id)
        }
    }

    // MARK: Saving and scheduling

    /// Runs a change and reports failures in an alert.
    func run(_ work: () async throws -> Void) async {
        busy = true
        do { try await work() } catch { notice = error.localizedDescription }
        busy = false
    }

    private func commit(request: Bool = false) async throws {
        persist()
        var failure: Error?
        do { try await AlarmEngine.sync(alarms, requestPermission: request) } catch { failure = error }
        await refresh()
        if let failure {
            throw AppError("Alarms were saved but could not be reserved. \(failure.localizedDescription)")
        }
    }

    func refresh() async {
        let dismissed = Set(AlarmEngine.takeDismissed())
        var changed = false
        if !dismissed.isEmpty {
            for i in alarms.indices where dismissed.contains(alarms[i].id) { alarms[i].dismissed = true; changed = true }
        }
        let before = alarms.count
        alarms.removeAll { $0.kind != .flight && $0.dismissed }
        if changed || alarms.count != before { persist() }
        intervals = AlarmEngine.loadIntervals()
        alarmAllowed = AlarmEngine.authorized || AlarmEngine.undetermined
        statuses = AlarmEngine.statuses(sources: alarms.map(\.id) + intervals.map(\.id))
        await publishSurfaces()
    }

    func start() async {
        try? await AlarmEngine.sync(alarms, requestPermission: false)
        await refresh()
    }

    func retryScheduling() async { await run { try await self.commit(request: true) } }

    func status(_ a: AlarmRecord) -> String {
        if a.dismissed { return "Done" }
        if a.missed { return "Missed" }
        if !a.armed { return "Paused" }
        if a.time < Date() { return "Time passed" }
        switch statuses[a.id]?.state {
        case "scheduled": return "Scheduled"
        case "alerting": return "Ringing"
        case "waiting": return "Waiting · not scheduled"
        case "permission": return "Alarm permission required"
        default: return "Not scheduled"
        }
    }

    func intervalNext(_ r: IntervalReminder) -> Date? {
        guard r.enabled, let s = statuses[r.id], ["scheduled", "alerting"].contains(s.state) else { return nil }
        return s.next
    }

    private func publishSurfaces() async {
        var upcoming: [CrewSurfaceAlarm] = []
        let now = Date()
        for a in alarms where a.time > now {
            guard let s = statuses[a.id], ["scheduled", "alerting"].contains(s.state) else { continue }
            let f = flight(a.flightID)
            let z = f.flatMap { zone($0.from) } ?? a.zone ?? homeZone
            upcoming.append(CrewSurfaceAlarm(id: a.id, label: a.label.isEmpty ? "Personal alarm" : a.label,
                                             at: a.time.timeIntervalSince1970, zone: z,
                                             flightDeparture: a.kind == .flight ? f?.departure.timeIntervalSince1970 : nil))
        }
        for r in intervals {
            guard let next = intervalNext(r) else { continue }
            upcoming.append(CrewSurfaceAlarm(id: r.id, label: r.label, at: next.timeIntervalSince1970, zone: homeZone, flightDeparture: nil))
        }
        upcoming.sort { $0.at < $1.at }
        let next = upcomingFlight
        let payload = CrewSurfacePayload(
            updatedAt: now.timeIntervalSince1970, alarms: upcoming,
            flight: next.map(flightLabel) ?? "", flightNumber: next?.number,
            departureDate: next.map { Fmt.ymd($0.departure, zone: zone($0.from)) },
            departureAirport: next?.from, arrivalAirport: next?.to,
            departureTime: next.map { Fmt.time($0.departure, zone: zone($0.from)) },
            arrivalTime: next.flatMap { f in f.arrival.map { Fmt.time($0, zone: zone(f.to)) } },
            allowed: AlarmEngine.authorized)
        do {
            try await SurfaceHub.shared.publish(payload, liveActivity: settings.liveActivity)
            surfaceError = nil
        } catch {
            surfaceError = error.localizedDescription
        }
    }

    // MARK: Roster import

    func matchingFlight(_ p: ParsedFlight) throws -> Flight? {
        if let exact = flight(p.id) { return exact }
        let day = Fmt.ymd(p.departure, zone: zone(p.from) ?? p.departureZone)
        let matches = flights.filter {
            $0.number == p.number && $0.from == p.from && $0.to == p.to && Fmt.ymd($0.departure, zone: zone($0.from)) == day
        }
        if matches.count > 1 { throw AppError("Multiple flights match. Edit those flights individually.") }
        return matches.first
    }

    func importChange(_ p: ParsedFlight) -> String {
        guard let old = try? matchingFlight(p) else { return "New" }
        return old.departure == p.departure && old.arrival == p.arrival ? "Unchanged" : "Changed"
    }

    func timesText(from: String, to: String, departure: Date, arrival: Date?) -> String {
        let dep = "\(Fmt.stamp(departure, zone: zone(from))) \(from) (L)"
        let arr = arrival.map { "\(Fmt.stamp($0, zone: zone(to))) \(to) (L)" } ?? "arrival unknown"
        return "\(dep) → \(arr)"
    }

    func importFlights(_ imported: [ParsedFlight], duties newDuties: [Duty]? = nil) async throws {
        for p in imported {
            for (airport, z) in [(p.from, p.departureZone), (p.to, p.arrivalZone)] {
                guard let z, !z.isEmpty else { continue }
                guard TimeZone(identifier: z) != nil else { throw AppError("Unknown time zone \(z).") }
                if parser.zone(airport) != z { settings.airportZones[airport] = z }
            }
            guard zone(p.from) != nil else {
                throw AppError("Confirm the departure airport time zone for \(p.from) using manual entry.")
            }
        }
        if let newDuties {
            let dates = Set(newDuties.map(\.date))
            duties.removeAll { dates.contains($0.date) }
            duties += newDuties
        }
        for p in imported {
            var f = Flight(id: p.id, number: p.number, from: p.from, to: p.to, departure: p.departure, arrival: p.arrival)
            if let old = try matchingFlight(p), let index = flights.firstIndex(where: { $0.id == old.id }) {
                f.id = old.id
                let shift = f.departure.timeIntervalSince(old.departure)
                let had = !flightAlarms(old).isEmpty
                flights[index] = f
                for i in alarms.indices where alarms[i].kind == .flight && alarms[i].flightID == old.id {
                    alarms[i].time = alarms[i].time.addingTimeInterval(shift)
                }
                if shift != 0 || old.arrival != f.arrival {
                    alarms.removeAll { $0.kind == .rest && $0.flightID == old.id }
                }
                if !had { alarms += buildFlightAlarms(f) }
            } else {
                flights.append(f)
                alarms += buildFlightAlarms(f)
            }
        }
        try await commit(request: true)
    }

    /// Moves a flight and every alarm linked to it by the same amount.
    func shiftFlight(_ f: Flight, minutes: Int) async throws {
        guard minutes != 0, let i = flights.firstIndex(where: { $0.id == f.id }) else { return }
        let shift = Double(minutes) * 60
        flights[i].departure = flights[i].departure.addingTimeInterval(shift)
        flights[i].arrival = flights[i].arrival?.addingTimeInterval(shift)
        for j in alarms.indices where alarms[j].flightID == f.id {
            alarms[j].time = alarms[j].time.addingTimeInterval(shift)
            if alarms[j].time > Date() { alarms[j].missed = false }
        }
        try await commit(request: true)
    }

    func deleteFlight(_ f: Flight) async throws {
        alarms.removeAll { $0.flightID == f.id }
        flights.removeAll { $0.id == f.id }
        briefings[f.id] = nil
        settings.restPlans[f.id] = nil
        try await commit()
    }

    func clearRoster() async throws {
        alarms.removeAll { $0.kind == .flight || $0.kind == .rest }
        flights = []
        duties = []
        briefings = [:]
        settings.restPlans = [:]
        selectedFlightID = nil
        try await commit()
    }

    // MARK: Alarms

    func saveAlarm(_ record: AlarmRecord) async throws {
        alarms.removeAll { $0.id == record.id }
        alarms.append(record)
        try await commit(request: true)
    }

    func toggleAlarm(_ id: String, armed: Bool) async throws {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].armed = armed
        if armed { alarms[i].dismissed = false; alarms[i].missed = false }
        try await commit(request: armed)
    }

    func deleteAlarm(_ id: String) async throws {
        alarms.removeAll { $0.id == id }
        try await commit()
    }

    func savePersonal(existing: AlarmRecord?, label: String, time: Date) async throws {
        guard time > Date() else { throw AppError("Choose a future reminder time.") }
        guard label.count <= 100 else { throw AppError("Use a label within 100 characters.") }
        var record = existing ?? AlarmRecord(id: newID(), label: "", time: time, kind: .personal)
        record.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        record.time = time
        record.zone = deviceZone
        record.armed = true
        record.dismissed = false
        record.missed = false
        try await saveAlarm(record)
    }

    func addTimer(label: String, minutes: Int) async throws {
        guard (1...10080).contains(minutes) else { throw AppError("Choose 1 minute to 7 days.") }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        try await saveAlarm(AlarmRecord(id: "timer_\(newID())", label: name.isEmpty ? "Timer" : name,
                                        time: Date().addingTimeInterval(Double(minutes) * 60), kind: .timer,
                                        durationMinutes: minutes))
    }

    func saveFlightReminder(_ f: Flight, existing: AlarmRecord?, label: String, minutesBefore: Int) async throws {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, (0...10080).contains(minutesBefore) else {
            throw AppError("Enter a reminder label and a valid hours/minutes offset.")
        }
        let at = f.departure.addingTimeInterval(-Double(minutesBefore) * 60)
        guard at > Date() else { throw AppError("Choose a future reminder time.") }
        var record = existing ?? AlarmRecord(id: "\(f.id)_\(newID())", label: name, time: at, kind: .flight, flightID: f.id)
        record.label = name
        record.time = at
        record.dismissed = false
        record.missed = false
        try await saveAlarm(record)
    }

    func saveIntervals(_ next: [IntervalReminder]) async throws {
        intervals = try await AlarmEngine.syncIntervals(next, requestPermission: true)
        await refresh()
    }

    // MARK: Settings

    func updateSettings(_ mutate: (inout AppSettings) -> Void) async throws {
        let previous = settings
        var next = settings
        mutate(&next)
        guard next != previous else { return }
        settings = next
        let basesChanged = previous.baseApt != next.baseApt || previous.domesticBaseApt != next.domesticBaseApt
        var alarmsChanged = false
        for f in flights {
            let g = group(f, next), oldGroup = group(f, previous)
            if previous.presetList(g) == next.presetList(g) && !basesChanged { continue }
            alarmsChanged = true
            let generated = buildFlightAlarms(f)
            let ids = Set(generated.map(\.id))
            for updated in generated {
                if let i = alarms.firstIndex(where: { $0.id == updated.id }) {
                    // Keep completion and pause state.
                    alarms[i].time = updated.time
                    alarms[i].label = updated.label
                } else if f.departure > Date() {
                    alarms.append(updated)
                }
            }
            let oldIDs = Set(previous.presetList(oldGroup).map { "\(f.id)_\($0.id)" })
            alarms.removeAll { oldIDs.contains($0.id) && !ids.contains($0.id) }
        }
        try await commit(request: alarmsChanged)
    }

    // MARK: Briefing

    func briefing(_ f: Flight) -> BriefingState { briefings[f.id] ?? .initial }

    func updateBriefing(_ f: Flight, _ mutate: (inout BriefingState) -> Void) {
        var state = briefing(f)
        mutate(&state)
        briefings[f.id] = state
        persist()
    }

    // MARK: In-flight rest

    var restFlights: [Flight] {
        let now = Date()
        return sortedFlights.filter { ($0.arrival ?? .distantPast) > now }
    }

    func restConfig(_ f: Flight) -> RestConfig { settings.restPlans[f.id] ?? RestConfig() }
    func restAlarms(_ f: Flight) -> [AlarmRecord] { alarms.filter { $0.kind == .rest && $0.flightID == f.id } }

    /// Splits the time between `after` minutes past departure and `before`
    /// minutes ahead of arrival into equal periods, rounded to five minutes.
    static func restPeriods(dep: Date, arr: Date, periods: Int, after: Int, before: Int) throws -> [(start: Date, end: Date)] {
        func five(_ t: Date, up: Bool) -> Date {
            let seconds = t.timeIntervalSince1970
            var minutes = floor(seconds / 60)
            if up && seconds.truncatingRemainder(dividingBy: 60) > 0 { minutes += 1 }
            let rounded = up ? ceil(minutes / 5) * 5 : floor(minutes / 5) * 5
            return Date(timeIntervalSince1970: rounded * 60)
        }
        let start = five(dep.addingTimeInterval(Double(after) * 60), up: true)
        let end = five(arr.addingTimeInterval(-Double(before) * 60), up: false)
        let total = Int(end.timeIntervalSince(start) / 60)
        guard (2...4).contains(periods) else { throw AppError("Choose 2 to 4 rest periods.") }
        guard total >= periods * 20 else { throw AppError("Not enough flight time for these rest periods.") }
        func edge(_ i: Int) -> Date {
            if i == 0 { return start }
            if i == periods { return end }
            let raw = start.timeIntervalSince1970 + Double(total * 60 * i / periods)
            return Date(timeIntervalSince1970: (raw / 300).rounded() * 300)
        }
        return (0..<periods).map { (edge($0), edge($0 + 1)) }
    }

    func restPlan(_ f: Flight, _ config: RestConfig) throws -> RestPlan {
        guard let arrival = f.arrival else { throw AppError("This flight has no arrival time.") }
        let delay = Double(config.delay) * 60
        let count = config.periods
        let mine = min(max(config.mine, 0), count - 1)
        let periods = try Self.restPeriods(dep: f.departure.addingTimeInterval(delay), arr: arrival.addingTimeInterval(delay),
                                           periods: count, after: config.after, before: config.before)
        var marks: [Date: String] = [:]
        if config.all {
            for i in 0..<count { marks[periods[i].start] = "Rest \(i + 1)/\(count) starts" }
            marks[periods[count - 1].end] = "Rest \(count)/\(count) ends"
        }
        marks[periods[mine].start] = "My rest starts (\(mine + 1)/\(count))"
        marks[periods[mine].end] = "My rest ends (\(mine + 1)/\(count))"
        let now = Date()
        let records = marks.keys.filter { $0 > now }.sorted().map { t in
            AlarmRecord(id: "rest_\(f.id)_\(Int(t.timeIntervalSince1970 / 60))",
                        label: "\(f.number) · \(marks[t] ?? "")", time: t, kind: .rest, flightID: f.id)
        }
        return RestPlan(periods: periods, alarms: records)
    }

    /// Replaces this flight's rest alarms; `nil` removes the plan.
    func saveRestPlan(_ f: Flight, _ config: RestConfig?) async throws {
        let next = try config.map { try restPlan(f, $0).alarms }
        if let next, next.isEmpty { throw AppError("All rest changeovers have passed.") }
        alarms.removeAll { $0.kind == .rest && $0.flightID == f.id }
        alarms += next ?? []
        let live = Set(flights.map(\.id))
        settings.restPlans = settings.restPlans.filter { live.contains($0.key) }
        settings.restPlans[f.id] = config
        try await commit(request: config != nil)
    }

    // MARK: Duty ribbon

    /// Positions are fractions (0–1) of the displayed window. The WOCL band is
    /// home-base 02:00–06:00, for reference only.
    func dutyRibbon(_ f: Flight) -> DutyRibbon {
        let dep = f.departure
        let arrival = f.arrival.flatMap { $0 > dep ? $0 : nil }
        let stepTimes = flightAlarms(f).map(\.time)
        var first = dep.addingTimeInterval(-3600)
        for t in stepTimes where t < first { first = t }
        let start = first.addingTimeInterval(-1800)
        let end = (arrival ?? dep.addingTimeInterval(7200)).addingTimeInterval(1800)
        let total = end.timeIntervalSince(start)
        func at(_ t: Date) -> Double { min(1, max(0, t.timeIntervalSince(start) / total)) }
        let hours = total / 3600
        let every = [1, 2, 3, 4, 6, 12].first { hours / Double($0) <= 7 } ?? 24
        var ribbon = DutyRibbon()
        var seen = Set<String>()
        func axis(_ label: String, _ zoneName: String?) {
            guard let zoneName, let tz = TimeZone(identifier: zoneName), seen.insert(zoneName).inserted else { return }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let comps = cal.dateComponents([.minute, .second], from: start)
            let toHour = Double((60 - (comps.minute ?? 0)) % 60) * 60 - Double(comps.second ?? 0)
            var t = start.addingTimeInterval(toHour)
            var ticks: [(x: Double, text: String)] = []
            while t <= end {
                let hour = cal.component(.hour, from: t)
                if hour % every == 0 { ticks.append((at(t), String(format: "%02d", hour))) }
                t = t.addingTimeInterval(3600)
            }
            ribbon.axes.append(RibbonAxis(label: label, ticks: ticks))
        }
        axis(f.from, zone(f.from))
        axis(f.to, zone(f.to))
        axis(home, zone(home))
        axis("UTC", "UTC")
        var woclFlight = 0.0
        if let tz = TimeZone(identifier: homeZone) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let day = cal.startOfDay(for: start)
            let days = Int(total / 86400) + 1
            for i in -1...days {
                guard let base = cal.date(byAdding: .day, value: i, to: day),
                      let from = cal.date(bySettingHour: 2, minute: 0, second: 0, of: base),
                      let to = cal.date(bySettingHour: 6, minute: 0, second: 0, of: base) else { continue }
                if to <= start || from >= end { continue }
                ribbon.wocl.append((at(from), at(to)))
                if let arrival {
                    let a = max(from, dep), b = min(to, arrival)
                    if b > a { woclFlight += b.timeIntervalSince(a) / 60 }
                }
            }
        }
        let now = Date()
        ribbon.dep = at(dep)
        ribbon.arr = arrival.map(at)
        ribbon.prep = at(first)
        ribbon.steps = stepTimes.map(at)
        ribbon.home = home
        ribbon.woclFlightMinutes = arrival == nil ? nil : Int(woclFlight)
        ribbon.blockMinutes = arrival.map { Int($0.timeIntervalSince(dep) / 60) }
        ribbon.now = now > start && now < end ? at(now) : nil
        return ribbon
    }

    // MARK: Roster day

    func flightsOn(_ day: String) -> [Flight] {
        sortedFlights.filter { Fmt.ymd($0.departure, zone: zone($0.from)) == day }
    }

    func shiftRosterDay(_ days: Int) {
        guard let date = Fmt.date(ymd: rosterDay) else { return }
        followUpcoming = false
        rosterDay = Fmt.ymd(date.addingTimeInterval(Double(days) * 86400), zone: "UTC")
    }

    func followUpcomingDay() {
        guard followUpcoming, let next = upcomingFlight else { return }
        rosterDay = Fmt.ymd(next.departure, zone: zone(next.from))
    }

    func showInRoster(_ f: Flight) {
        followUpcoming = false
        rosterDay = Fmt.ymd(f.departure, zone: zone(f.from))
        tab = 1
    }
}
