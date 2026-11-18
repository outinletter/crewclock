import Foundation

struct Flight: Codable, Identifiable, Hashable {
    var id: String
    var number: String
    var from: String
    var to: String
    var departure: Date
    var arrival: Date?
}

enum AlarmKind: String, Codable {
    case flight, personal, timer, rest
}

struct AlarmRecord: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var time: Date
    var kind: AlarmKind
    var armed = true
    var dismissed = false
    var missed = false
    var flightID: String?
    var durationMinutes: Int?
    var zone: String?

    var active: Bool { armed && !dismissed && !missed }
}

struct IntervalReminder: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var minutes: Int
    var enabled: Bool
    var anchor: Date
}

struct Preset: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var minutes: Int
}

struct PrepTask: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var checkedAt: Date?
}

struct BriefingState: Codable {
    var tasks: [PrepTask]
    var note = ""

    static let defaultLabels = [
        "Roster and departure time", "Crew documents packed", "Passport & VISA", "Personal bag ready",
    ]
    static var initial: BriefingState {
        BriefingState(tasks: defaultLabels.enumerated().map { PrepTask(id: "task_\($0.offset)", label: $0.element) })
    }
}

struct Duty: Codable, Identifiable, Hashable {
    var date: String      // yyyy-MM-dd
    var label: String
    var category: String
    var id: String { "\(date)|\(label)" }
}

struct RestConfig: Codable, Equatable {
    var periods = 2
    var after = 30
    var before = 60
    var mine = 0
    var delay = 0
    var all = false
}

enum PresetGroup: String, Codable, CaseIterable, Identifiable {
    case base, dom, intl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .base: return "Home-base international"
        case .dom: return "Home-base domestic"
        case .intl: return "Overseas"
        }
    }
    var defaults: [Preset] {
        switch self {
        case .base:
            return [Preset(id: "b1", label: "Prepare for Duty", minutes: 270),
                    Preset(id: "b2", label: "Depart for Airport", minutes: 240),
                    Preset(id: "b3", label: "Boarding time", minutes: 40)]
        case .dom:
            return [Preset(id: "d1", label: "Prepare for Duty", minutes: 210),
                    Preset(id: "d2", label: "Depart for Airport", minutes: 210),
                    Preset(id: "d3", label: "Boarding time", minutes: 30)]
        case .intl:
            return [Preset(id: "i1", label: "Wake Up (Overseas)", minutes: 180),
                    Preset(id: "i2", label: "Hotel Checkout", minutes: 120),
                    Preset(id: "i3", label: "Boarding time", minutes: 40)]
        }
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable {
    var appearance = Appearance.system
    var liveActivity = false
    var baseApt = "ICN"
    var domesticBaseApt = "GMP"
    var presets: [String: [Preset]] = [:]
    var airportZones: [String: String] = [:]
    var restPlans: [String: RestConfig] = [:]
    /// Show flight times in UTC (Z) instead of airport-local time.
    var displayUTC = false
    /// Minutes before departure that duty starts; 0 hides report time and FDP.
    var reportMinutes = 0

    func presetList(_ group: PresetGroup) -> [Preset] {
        let list = presets[group.rawValue] ?? group.defaults
        return list.sorted { $0.minutes == $1.minutes ? $0.id < $1.id : $0.minutes > $1.minutes }
    }
    func codes(domestic: Bool) -> [String] {
        let raw = domestic ? domesticBaseApt : baseApt
        var seen = Set<String>()
        let parts = raw.uppercased().split(whereSeparator: { ",; \n\t".contains($0) }).map(String.init)
        let unique = parts.filter { seen.insert($0).inserted }
        return unique.isEmpty ? [domestic ? "GMP" : "ICN"] : unique
    }
}

struct DocumentItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var expiry: Date

    var daysLeft: Int { Int(ceil(expiry.timeIntervalSinceNow / 86400)) }
}

struct PersistedState: Codable {
    var flights: [Flight] = []
    var alarms: [AlarmRecord] = []
    var duties: [Duty] = []
    var settings = AppSettings()
    var briefings: [String: BriefingState] = [:]
    var documents: [DocumentItem] = []
}

// Decoders tolerate missing keys so saved data survives new fields.
extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        liveActivity = try c.decodeIfPresent(Bool.self, forKey: .liveActivity) ?? false
        baseApt = try c.decodeIfPresent(String.self, forKey: .baseApt) ?? "ICN"
        domesticBaseApt = try c.decodeIfPresent(String.self, forKey: .domesticBaseApt) ?? "GMP"
        presets = try c.decodeIfPresent([String: [Preset]].self, forKey: .presets) ?? [:]
        airportZones = try c.decodeIfPresent([String: String].self, forKey: .airportZones) ?? [:]
        restPlans = try c.decodeIfPresent([String: RestConfig].self, forKey: .restPlans) ?? [:]
        displayUTC = try c.decodeIfPresent(Bool.self, forKey: .displayUTC) ?? false
        reportMinutes = try c.decodeIfPresent(Int.self, forKey: .reportMinutes) ?? 0
    }
}

extension PersistedState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        flights = try c.decodeIfPresent([Flight].self, forKey: .flights) ?? []
        alarms = try c.decodeIfPresent([AlarmRecord].self, forKey: .alarms) ?? []
        duties = try c.decodeIfPresent([Duty].self, forKey: .duties) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        briefings = try c.decodeIfPresent([String: BriefingState].self, forKey: .briefings) ?? [:]
        documents = try c.decodeIfPresent([DocumentItem].self, forKey: .documents) ?? []
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Fmt {
    private static var cache: [String: DateFormatter] = [:]
    private static func formatter(_ pattern: String, _ zone: String?) -> DateFormatter {
        let key = pattern + "|" + (zone ?? "")
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        f.timeZone = zone.flatMap { TimeZone(identifier: $0) } ?? TimeZone(identifier: "UTC")!
        cache[key] = f
        return f
    }
    static func format(_ d: Date, _ pattern: String, zone: String?) -> String { formatter(pattern, zone).string(from: d) }
    static func time(_ d: Date, zone: String?) -> String { format(d, "HH:mm", zone: zone) }
    static func ymd(_ d: Date, zone: String?) -> String { format(d, "yyyy-MM-dd", zone: zone) }
    static func displayDate(_ d: Date, zone: String?) -> String { format(d, "yyyy-MM-dd EEE", zone: zone) }
    static func badge(_ d: Date, zone: String?) -> String { format(d, "MM/dd EEE", zone: zone) }
    static func stamp(_ d: Date, zone: String?) -> String { format(d, "yyyy-MM-dd HH:mm", zone: zone) }
    static func date(ymd: String) -> Date? { formatter("yyyy-MM-dd", "UTC").date(from: ymd) }

    /// "13h 30m"
    static func span(_ minutes: Int) -> String {
        let m = abs(minutes)
        return "\(m / 60)h \(String(format: "%02d", m % 60))m"
    }
    /// "-4h 30m" for minutes before departure.
    static func offset(_ minutesBefore: Int) -> String {
        let m = abs(minutesBefore)
        return "\(minutesBefore >= 0 ? "−" : "+")\(m / 60)h \(m % 60)m"
    }
    static func short(_ minutes: Int) -> String {
        let m = abs(minutes)
        return m >= 60 ? span(m) : "\(m)m"
    }
}
