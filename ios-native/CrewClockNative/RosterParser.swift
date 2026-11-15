import Foundation

struct ParsedFlight: Identifiable, Hashable {
    var id: String
    var number: String
    var from: String
    var to: String
    var departure: Date
    var arrival: Date?
    var departureZone: String?
    var arrivalZone: String?
}

struct RMatch {
    let groups: [String?]
    let range: Range<String.Index>
    subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
}

extension String {
    func rx(_ pattern: String, insensitive: Bool = false) -> [RMatch] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : []) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let whole = Range(m.range, in: self) else { return nil }
            var groups: [String?] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            return RMatch(groups: groups, range: whole)
        }
    }
    func rxFirst(_ pattern: String, insensitive: Bool = false) -> RMatch? { rx(pattern, insensitive: insensitive).first }
    func rxTest(_ pattern: String, insensitive: Bool = false) -> Bool { rxFirst(pattern, insensitive: insensitive) != nil }
    func rxReplace(_ pattern: String, _ transform: (RMatch) -> String) -> String {
        var out = self
        for m in rx(pattern).reversed() { out.replaceSubrange(m.range, with: transform(m)) }
        return out
    }
}

final class RosterParser {
    private(set) var zones: [String: String] = [:]

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                         "September", "October", "November", "December"]

    init() {
        if let url = Bundle.main.url(forResource: "airport_timezones", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            zones = map
        }
    }

    func zone(_ airport: String) -> String? { zones[airport.uppercased()] }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    /// Converts an airport-local wall time to an instant, rejecting times that
    /// do not exist or occur twice because of daylight saving.
    func localInstant(date: String, time: String, zone: String) throws -> Date {
        guard let dm = date.rxFirst(#"^(\d{4})-(\d{2})-(\d{2})$"#),
              let y = Int(dm[1] ?? ""), let mo = Int(dm[2] ?? ""), let d = Int(dm[3] ?? "") else {
            throw AppError("Enter an existing calendar date as YYYY-MM-DD.")
        }
        let parts = time.split(separator: ":").map(String.init)
        guard parts.count == 2, let h = Int(parts[0]), let mi = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(mi) else {
            throw AppError("Enter a valid date and 24-hour time.")
        }
        guard let tz = TimeZone(identifier: zone) else { throw AppError("Unknown time zone \(zone).") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        guard let at = cal.date(from: comps) else { throw AppError("Enter an existing calendar date as YYYY-MM-DD.") }
        let back = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        if back.year != y || back.month != mo || back.day != d {
            throw AppError("Enter an existing calendar date as YYYY-MM-DD.")
        }
        if back.hour != h || back.minute != mi {
            throw AppError("This local time does not exist due to a daylight-saving change. Use UTC.")
        }
        for delta in [-3600.0, 3600.0] {
            let other = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at.addingTimeInterval(delta))
            if other.year == y && other.month == mo && other.day == d && other.hour == h && other.minute == mi {
                throw AppError("This local time occurs twice due to daylight saving. Import an explicit UTC time.")
            }
        }
        return at
    }

    func parse(_ text: String) throws -> [ParsedFlight] {
        if text.utf8.count > 5_000_000 { throw AppError("Choose a roster smaller than 5 MB.") }
        if text.contains("BEGIN:VEVENT") { return try calendar(text) }
        let monthPattern = "\\b(" + Self.months.joined(separator: "|") + ")\\s+20\\d{2}"
        if text.rxTest(monthPattern, insensitive: true) { return try monthly(text) }
        return try lines(text)
    }

    func nonFlightDays(_ text: String) -> [Duty] {
        var result: [Duty] = []
        func category(_ label: String) -> String? {
            if label.rxTest("^(DO|RDO|ATDO|OFF|ALV|ALM)$") { return "Off / leave" }
            if label.rxTest("RESERVE|STANDBY|SBY") { return "Reserve" }
            if label.rxTest(#"^(LO\s*|LAYOVER)"#) { return "Layover" }
            if label.rxTest("CRM|UPRT|EMER|SAFE_MT|SIM|TRAIN") { return "Training" }
            return nil
        }
        func add(_ date: String, _ label: String) {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if let type = category(trimmed.uppercased()) {
                result.append(Duty(date: date, label: trimmed, category: type))
            }
        }
        if text.contains("BEGIN:VEVENT") {
            for event in text.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
                let summary = event.rxFirst(#"(?:^|\n)SUMMARY:([^\r\n]+)"#)?[1]
                let date = event.rxFirst(#"(?:^|\n)DTSTART[^:]*:(\d{4})(\d{2})(\d{2})"#)
                if let summary, let date, let y = date[1], let m = date[2], let d = date[3] {
                    add("\(y)-\(m)-\(d)", summary)
                }
            }
        } else {
            let titlePattern = "(" + Self.months.joined(separator: "|") + ")\\s+(20[0-9]{2})"
            guard let title = text.rxFirst(titlePattern, insensitive: true),
                  let name = title[1], let year = title[2],
                  let index = Self.months.firstIndex(where: { $0.lowercased() == name.lowercased() }) else { return result }
            let month = index + 1
            let code = String(Self.months[index].prefix(3))
            let matches = text.rx("\\b\(code)\\s+([0-9]{1,2})\\b", insensitive: true)
            for (i, m) in matches.enumerated() {
                let day = (m[1] ?? "").count == 1 ? "0" + (m[1] ?? "") : (m[1] ?? "")
                let date = "\(year)-\(String(format: "%02d", month))-\(day)"
                let end = i + 1 < matches.count ? matches[i + 1].range.lowerBound : text.endIndex
                for line in text[m.range.upperBound..<end].components(separatedBy: "\n") { add(date, line) }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private func monthly(_ raw: String) throws -> [ParsedFlight] {
        var text = raw.replacingOccurrences(of: "\u{00a0}", with: " ")
        text = text.rxReplace("[−‐‑]") { _ in "-" }
        text = text.rxReplace(#"(?<!\d)(\d{1,2})\s*[.:：]\s*(\d{2})\b"#) { m in
            let h = m[1] ?? ""
            return (h.count == 1 ? "0" + h : h) + ":" + (m[2] ?? "")
        }
        text = text.rxReplace(#"\b[Il1]CN\b"#) { _ in "ICN" }
        let titlePattern = "(" + Self.months.joined(separator: "|") + ")\\s+(20[0-9]{2})"
        guard let title = text.rxFirst(titlePattern, insensitive: true), let name = title[1],
              let year = Int(title[2] ?? ""),
              let index = Self.months.firstIndex(where: { $0.lowercased() == name.lowercased() }) else {
            throw AppError("Month and year were not recognized.")
        }
        let month = index + 1
        let code = String(Self.months[index].prefix(3))
        let headers = text.rx("\\b\(code)\\s+([0-9]{1,2})\\b", insensitive: true)
        var cells: [(day: Int, text: String)] = []
        for (i, h) in headers.enumerated() {
            let end = i + 1 < headers.count ? headers[i + 1].range.lowerBound : text.endIndex
            cells.append((Int(h[1] ?? "") ?? 0, String(text[h.range.upperBound..<end]).uppercased()))
        }
        cells.sort { $0.day < $1.day }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 31
        let usesKE = text.uppercased().rxTest(#"\bKE\s*\d"#)
        let pattern = #"\b([A-Z]{2})\s*(\d{1,4})\s*([A-Z]{3})\s*(\d{2}:\d{2})?\s*[-–—→]\s*([A-Z]{3})(?:\s*(\d{2}:\d{2}))?"#
        var flights: [ParsedFlight] = []
        var pending: [String: Int] = [:]   // flightKey -> index in flights
        for cell in cells {
            guard cell.day >= 1 && cell.day <= daysInMonth else { throw AppError("Invalid calendar date.") }
            let date = "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", cell.day))"
            for m in cell.text.rx(pattern) {
                let airline = (m[1] == "DH" && usesKE) ? "KE" : (m[1] ?? "")
                let number = airline + (m[2] ?? "")
                let from = m[3] ?? "", to = m[5] ?? ""
                guard let depZone = zone(from), let arrZone = zone(to) else {
                    throw AppError("Unknown route \(from)-\(to). Check recognized text.")
                }
                let key = "\(number)|\(from)|\(to)"
                if let depTime = m[4] {
                    if pending[key] != nil { throw AppError("Missing arrival date for \(number). Use manual entry.") }
                    let dep = try localInstant(date: date, time: depTime, zone: depZone)
                    var record = ParsedFlight(id: "\(number)|\(from)|\(iso(dep))", number: number, from: from, to: to, departure: dep)
                    if let arrTime = m[6] {
                        let arr = try localInstant(date: date, time: arrTime, zone: arrZone)
                        guard arr > dep else { throw AppError("Arrival date for \(number) is ambiguous. Use manual entry.") }
                        record.arrival = arr
                    } else {
                        pending[key] = flights.count
                    }
                    flights.append(record)
                } else if let arrTime = m[6] {
                    guard let i = pending.removeValue(forKey: key) else {
                        throw AppError("Missing departure date for \(number). Include the full calendar.")
                    }
                    let arr = try localInstant(date: date, time: arrTime, zone: arrZone)
                    guard arr > flights[i].departure else { throw AppError("Check arrival date for \(number).") }
                    flights[i].arrival = arr
                } else {
                    throw AppError("Missing times for \(number). Check recognized text.")
                }
            }
        }
        if !pending.isEmpty {
            throw AppError("Some arrival dates are missing. Include the full calendar or enter flights manually.")
        }
        return try deduplicate(flights)
    }

    private func calendar(_ raw: String) throws -> [ParsedFlight] {
        var unfolded = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        unfolded = unfolded.rxReplace(#"\n[ \t]"#) { _ in "" }
        var flights: [ParsedFlight] = []
        var event: [String: String]?
        var calendarZone: String?
        for line in unfolded.components(separatedBy: "\n") {
            if line.hasPrefix("X-WR-TIMEZONE:") {
                calendarZone = String(line.dropFirst("X-WR-TIMEZONE:".count)).trimmingCharacters(in: .whitespaces)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN:VEVENT" { event = [:]; continue }
            if trimmed == "END:VEVENT" {
                if let e = event { if let f = try flight(from: e, calendarZone: calendarZone) { flights.append(f) } }
                event = nil
                continue
            }
            guard event != nil, let colon = line.firstIndex(of: ":") else { continue }
            let header = String(line[..<colon])
            let key = (header.split(separator: ";").first.map(String.init) ?? header).uppercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\n", with: " ")
            event?[key] = value
            if let z = header.rxFirst(#"TZID="?([^;"\r\n]+)"#)?[1] { event?[key + "_ZONE"] = z }
        }
        return try deduplicate(flights)
    }

    private func flight(from event: [String: String], calendarZone: String?) throws -> ParsedFlight? {
        let summary = (event["SUMMARY"] ?? "").uppercased()
        guard let rawNumber = summary.rxFirst(#"\b([A-Z]{2,3}\s?\d{1,4})\b"#)?[1],
              let route = summary.rxFirst(#"\b([A-Z]{3})\s*(?:[-–—/→]|TO|\s)\s*([A-Z]{3})\b"#),
              let from = route[1], let to = route[2],
              !summary.rxTest(#"\b(OFF|STANDBY|SICK|RESERVE)\b"#) else { return nil }
        let number = rawNumber.replacingOccurrences(of: " ", with: "")
        if event["RRULE"] != nil { throw AppError("Recurring calendar events need individual dated flights.") }
        let dep = try icsDate(event["DTSTART"] ?? "", zone: event["DTSTART_ZONE"] ?? calendarZone ?? zone(from))
        var arrival: Date?
        if let end = event["DTEND"] {
            arrival = try icsDate(end, zone: event["DTEND_ZONE"] ?? calendarZone ?? zone(to))
        }
        if let arrival, arrival <= dep { throw AppError("\(number) arrival must be after departure.") }
        return ParsedFlight(id: event["UID"] ?? "\(number)|\(from)|\(iso(dep))", number: number, from: from, to: to,
                            departure: dep, arrival: arrival)
    }

    private func icsDate(_ value: String, zone: String?) throws -> Date {
        guard let m = value.rxFirst(#"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$"#) else {
            throw AppError("Use timed calendar flights, not all-day events.")
        }
        let date = "\(m[1] ?? "")-\(m[2] ?? "")-\(m[3] ?? "")"
        let time = "\(m[4] ?? ""):\(m[5] ?? "")"
        let seconds = Double(m[6] ?? "0") ?? 0
        if m[7] == "Z" { return try localInstant(date: date, time: time, zone: "UTC").addingTimeInterval(seconds) }
        guard let zone else {
            throw AppError("Calendar time zone is missing. Import UTC or specify the airport time zone.")
        }
        return try localInstant(date: date, time: time, zone: zone).addingTimeInterval(seconds)
    }

    private func lines(_ raw: String) throws -> [ParsedFlight] {
        var flights: [ParsedFlight] = []
        let pattern = #"^(\d{4}-\d{2}-\d{2})[\s,]+([A-Za-z]{2,3}\d{1,4})[\s,]+([A-Za-z]{3})[\s,→/-]+([A-Za-z]{3})[\s,]+(\d{2}:\d{2})(?:\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}))?\s*$"#
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let m = trimmed.rxFirst(pattern) else {
                throw AppError("Text format: YYYY-MM-DD KE955 ICN IST 13:55. Optional arrival: YYYY-MM-DD HH:mm (destination local date/time). Use manual entry for other formats.")
            }
            let from = (m[3] ?? "").uppercased(), to = (m[4] ?? "").uppercased()
            guard let z = zone(from) else {
                throw AppError("Unknown airport \(from). Use manual entry with an explicit time zone.")
            }
            let dep = try localInstant(date: m[1] ?? "", time: m[5] ?? "", zone: z)
            var arrival: Date?
            if let arrDate = m[6], let arrTime = m[7] {
                guard let az = zone(to) else { throw AppError("Unknown airport \(to).") }
                let arr = try localInstant(date: arrDate, time: arrTime, zone: az)
                guard arr > dep else { throw AppError("Arrival must be after departure.") }
                arrival = arr
            }
            let number = (m[2] ?? "").uppercased()
            flights.append(ParsedFlight(id: "\(number)|\(from)|\(iso(dep))", number: number, from: from, to: to,
                                        departure: dep, arrival: arrival))
        }
        return try deduplicate(flights)
    }

    private func deduplicate(_ flights: [ParsedFlight]) throws -> [ParsedFlight] {
        if flights.isEmpty { throw AppError("No dated flights were found. Try manual flight entry.") }
        var unique: [String: ParsedFlight] = [:]
        for f in flights { unique["\(f.number)|\(f.from)|\(f.departure.timeIntervalSince1970)"] = f }
        return unique.values.sorted { $0.departure < $1.departure }
    }
}
