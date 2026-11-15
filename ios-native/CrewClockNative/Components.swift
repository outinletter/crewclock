import SwiftUI

extension View {
    /// A full-width card inside an inset-grouped list.
    func cardRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
    func plainRow() -> some View { listRowBackground(Color.ccCard) }
}

struct DurationPicker: View {
    @Binding var minutes: Int
    var maxHours = 23

    var body: some View {
        HStack(spacing: 0) {
            Picker("Hours", selection: Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + minutes % 60 })) {
                ForEach(0...maxHours, id: \.self) { Text("\($0) h").tag($0) }
            }
            .pickerStyle(.wheel)
            Picker("Minutes", selection: Binding(get: { minutes % 60 }, set: { minutes = (minutes / 60) * 60 + $0 })) {
                ForEach(0..<60, id: \.self) { Text("\($0) m").tag($0) }
            }
            .pickerStyle(.wheel)
        }
        .frame(height: 130)
    }
}

/// Progress towards a one-shot or repeating alarm.
struct CountdownBar: View {
    let next: Date?
    let minutes: Int
    var enabled = true

    var body: some View {
        if enabled, let next {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let seconds = Int(next.timeIntervalSince(ctx.date))
                let total = max(1, minutes * 60)
                let remaining = min(max(seconds, 0), total)
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: Double(remaining) / Double(total)).tint(.ccBlue)
                    Text(seconds <= 0 ? "Due now" : "\(remaining / 3600)h \((remaining % 3600) / 60)m \(remaining % 60)s remaining")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Color.ccMuted)
                }
            }
        }
    }
}

/// Shared chrome for the editor sheets: Cancel / Save and an inline error.
struct EditorSheet<Content: View>: View {
    let title: String
    var saveLabel = "Save"
    let save: () async throws -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                content
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        saving = true
                        Task {
                            do { try await save(); dismiss() } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

struct PersonalAlarmSheet: View {
    @Environment(AppStore.self) private var store
    let existing: AlarmRecord?
    @State private var label: String
    @State private var time: Date

    init(existing: AlarmRecord?) {
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        let fallback = Date().addingTimeInterval(3600)
        _time = State(initialValue: max(existing?.time ?? fallback, Date().addingTimeInterval(60)))
    }

    var body: some View {
        EditorSheet(title: existing == nil ? "Add alarm" : "Edit alarm", saveLabel: existing == nil ? "Add" : "Save") {
            try await store.savePersonal(existing: existing, label: label, time: time)
        } content: {
            Section {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                DatePicker("Date", selection: $time, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
            } footer: {
                Text("Device local time · \(store.deviceZone)")
            }
            Section { TextField("Label (optional)", text: $label) }
        }
    }
}

struct ReminderSheet: View {
    @Environment(AppStore.self) private var store
    let flight: Flight
    let existing: AlarmRecord?
    @State private var label: String
    @State private var minutes: Int

    init(flight: Flight, existing: AlarmRecord?) {
        self.flight = flight
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        let offset = existing.map { Int(flight.departure.timeIntervalSince($0.time) / 60) } ?? 60
        _minutes = State(initialValue: min(max(offset, 0), 10080))
    }

    var body: some View {
        EditorSheet(title: existing == nil ? "Add reminder" : "Edit reminder") {
            try await store.saveFlightReminder(flight, existing: existing, label: label, minutesBefore: minutes)
        } content: {
            Section("\(flight.number) · \(flight.from) → \(flight.to)") {
                TextField("Reminder label", text: $label)
            }
            Section {
                DurationPicker(minutes: $minutes, maxHours: 167)
            } header: {
                Text("Before departure")
            } footer: {
                let at = flight.departure.addingTimeInterval(-Double(minutes) * 60)
                Text("Rings \(Fmt.stamp(at, zone: store.zone(flight.from))) \(flight.from) (L)")
            }
        }
    }
}

struct DelaySheet: View {
    @Environment(AppStore.self) private var store
    let flight: Flight
    @State private var minutes = 15

    var body: some View {
        EditorSheet(title: "Departure delay", saveLabel: "Apply") {
            try await store.shiftFlight(flight, minutes: minutes)
        } content: {
            Section {
                Stepper(value: $minutes, in: -120...720, step: 5) {
                    Text((minutes > 0 ? "+" : minutes < 0 ? "−" : "") + Fmt.short(minutes))
                        .font(.title2.weight(.bold).monospacedDigit())
                }
            } header: {
                Text("\(flight.number) · \(flight.from) → \(flight.to)")
            } footer: {
                let dep = flight.departure.addingTimeInterval(Double(minutes) * 60)
                Text("New departure \(Fmt.stamp(dep, zone: store.zone(flight.from))) \(flight.from) (L). The arrival time and every alarm of this flight, including rest alarms, move by the same amount.")
            }
        }
    }
}

struct DocumentSheet: View {
    @Environment(AppStore.self) private var store
    let existing: DocumentItem
    @State private var name: String
    @State private var expiry: Date
    static let suggestions = ["Passport", "Visa", "Medical certificate", "Licence", "Crew ID"]

    init(existing: DocumentItem) {
        self.existing = existing
        _name = State(initialValue: existing.name)
        _expiry = State(initialValue: existing.expiry)
    }

    var body: some View {
        EditorSheet(title: "Document") {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 60 else { throw AppError("Enter a document name.") }
            store.saveDocument(DocumentItem(id: existing.id, name: trimmed, expiry: expiry))
        } content: {
            Section {
                TextField("Name", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Self.suggestions, id: \.self) { s in
                            Button(s) { name = s }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            Section {
                DatePicker("Expiry date", selection: $expiry, displayedComponents: .date)
            } footer: {
                Text("Briefing shows a warning from 90 days before expiry. This is an in-app reminder, not an alarm.")
            }
        }
    }
}

struct RosterListSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var months: [(title: String, flights: [Flight])] {
        var result: [(title: String, flights: [Flight])] = []
        for f in store.sortedFlights {
            let title = Fmt.format(f.departure, "MMMM yyyy", zone: store.zone(f.from))
            if result.last?.title == title { result[result.count - 1].flights.append(f) } else { result.append((title, [f])) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if store.flights.isEmpty { Text("No flights yet. Add your roster first.").foregroundStyle(Color.ccMuted) }
                ForEach(months, id: \.title) { month in
                    Section(month.title) {
                        ForEach(month.flights) { f in
                            Button {
                                store.showInRoster(f)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(Fmt.badge(f.departure, zone: store.zone(f.from)))
                                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(f.departure < Date() ? Color.ccGround : Color.ccBlue, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(f.number) · \(f.from) → \(f.to)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ccInk)
                                        Text(store.timesText(from: f.from, to: f.to, departure: f.departure, arrival: f.arrival))
                                            .font(.caption).foregroundStyle(Color.ccMuted)
                                        if let lay = store.layover(after: f) {
                                            Text("Layover \(f.to) \(AppStore.gapText(lay.minutes))").font(.caption).foregroundStyle(Color.ccMint)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("All flights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct TimerSheet: View {
    @Environment(AppStore.self) private var store
    @State private var label = ""
    @State private var minutes = 60

    var body: some View {
        EditorSheet(title: "New timer", saveLabel: "Start") {
            try await store.addTimer(label: label, minutes: minutes)
        } content: {
            Section("Rings after") { DurationPicker(minutes: $minutes, maxHours: 167) }
            Section { TextField("Label (optional)", text: $label) }
        }
    }
}

struct IntervalSheet: View {
    @Environment(AppStore.self) private var store
    let existing: IntervalReminder?
    @State private var label: String
    @State private var minutes: Int

    init(existing: IntervalReminder?) {
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        _minutes = State(initialValue: existing?.minutes ?? 60)
    }

    var body: some View {
        EditorSheet(title: "Repeating reminder", saveLabel: existing == nil ? "Add" : "Save") {
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            var next = store.intervals
            if let existing, let i = next.firstIndex(where: { $0.id == existing.id }) {
                next[i].label = name.isEmpty ? "Repeating reminder" : name
                next[i].minutes = minutes
            } else {
                guard next.count < 16 else { throw AppError("Up to 16 repeating reminders are supported.") }
                next.append(IntervalReminder(id: "interval_\(store.newID())", label: name.isEmpty ? "Repeating reminder" : name,
                                             minutes: minutes, enabled: true, anchor: Date()))
            }
            try await store.saveIntervals(next)
        } content: {
            Section {
                DurationPicker(minutes: $minutes, maxHours: 167)
            } header: {
                Text("Repeat every")
            } footer: {
                Text("After Stop, the next reminder is scheduled for the selected interval.")
            }
            Section { TextField("Label (optional)", text: $label) }
        }
    }
}

struct PresetSheet: View {
    @Environment(AppStore.self) private var store
    let group: PresetGroup
    let preset: Preset
    @State private var label: String
    @State private var minutes: Int

    init(group: PresetGroup, preset: Preset) {
        self.group = group
        self.preset = preset
        _label = State(initialValue: preset.label)
        _minutes = State(initialValue: preset.minutes)
    }

    var body: some View {
        EditorSheet(title: group.title) {
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { throw AppError("Enter a reminder label within 100 characters.") }
            try await store.updateSettings { s in
                var list = s.presets[group.rawValue] ?? group.defaults
                if let i = list.firstIndex(where: { $0.id == preset.id }) {
                    list[i].label = name
                    list[i].minutes = minutes
                } else {
                    list.append(Preset(id: preset.id, label: name, minutes: minutes))
                }
                s.presets[group.rawValue] = list
            }
        } content: {
            Section { TextField("Reminder label", text: $label) }
            Section("Before departure") { DurationPicker(minutes: $minutes, maxHours: 47) }
        }
    }
}

struct FlightEditorSheet: View {
    @Environment(AppStore.self) private var store
    let existing: Flight?
    @State private var number: String
    @State private var from: String
    @State private var to: String
    @State private var departure: Date
    @State private var hasArrival: Bool
    @State private var arrival: Date
    @State private var depZone = ""
    @State private var arrZone = ""

    init(existing: Flight?, home: String) {
        self.existing = existing
        _number = State(initialValue: existing?.number ?? "")
        _from = State(initialValue: existing?.from ?? home)
        _to = State(initialValue: existing?.to ?? "")
        let dep = existing?.departure ?? Date().addingTimeInterval(2 * 86400)
        _departure = State(initialValue: dep)
        _hasArrival = State(initialValue: existing?.arrival != nil)
        _arrival = State(initialValue: existing?.arrival ?? dep.addingTimeInterval(3 * 3600))
    }

    private func knownZone(_ code: String) -> String? { store.zone(code.uppercased()) }
    private func timeZone(_ code: String, _ manual: String) -> TimeZone {
        TimeZone(identifier: knownZone(code) ?? manual) ?? TimeZone(identifier: "UTC")!
    }

    var body: some View {
        EditorSheet(title: existing == nil ? "Add flight" : "Edit flight") {
            let n = number.trimmingCharacters(in: .whitespaces).uppercased()
            let f = from.trimmingCharacters(in: .whitespaces).uppercased()
            let t = to.trimmingCharacters(in: .whitespaces).uppercased()
            guard n.rxTest("^[A-Z0-9]{2,10}$"), f.rxTest("^[A-Z]{3}$"), t.rxTest("^[A-Z]{3}$") else {
                throw AppError("Use a flight number and three-letter IATA airport codes.")
            }
            guard let dz = knownZone(f) ?? (TimeZone(identifier: depZone) != nil ? depZone : nil) else {
                throw AppError("Enter a valid departure time zone, for example Asia/Seoul.")
            }
            var az: String?
            if hasArrival {
                az = knownZone(t) ?? (TimeZone(identifier: arrZone) != nil ? arrZone : nil)
                guard az != nil else { throw AppError("Enter a valid arrival time zone, for example Europe/Prague.") }
                guard arrival > departure else { throw AppError("Arrival must be after departure.") }
            }
            let parsed = ParsedFlight(id: existing?.id ?? store.newID(), number: n, from: f, to: t, departure: departure,
                                      arrival: hasArrival ? arrival : nil, departureZone: dz, arrivalZone: az)
            try await store.importFlights([parsed])
        } content: {
            Section {
                TextField("Flight number", text: $number).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Departure airport (IATA)", text: $from).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Arrival airport (IATA)", text: $to).textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            Section {
                DatePicker("Departure", selection: $departure)
                    .environment(\.timeZone, timeZone(from, depZone))
                if from.count == 3 && knownZone(from) == nil {
                    TextField("Departure time zone (e.g. Asia/Seoul)", text: $depZone).autocorrectionDisabled()
                }
            } footer: {
                Text("Departure airport local time.")
            }
            Section {
                Toggle("Arrival time", isOn: $hasArrival)
                if hasArrival {
                    DatePicker("Arrival", selection: $arrival)
                        .environment(\.timeZone, timeZone(to, arrZone))
                    if to.count == 3 && knownZone(to) == nil {
                        TextField("Arrival time zone (e.g. Europe/Prague)", text: $arrZone).autocorrectionDisabled()
                    }
                }
            } footer: {
                Text("Arrival is optional and uses the arrival airport local time. It is needed for the in-flight rest planner.")
            }
        }
    }
}
