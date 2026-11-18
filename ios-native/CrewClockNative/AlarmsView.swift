import SwiftUI

struct AlarmsView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: SheetKind?
    @State private var editingReminder: ReminderTarget?

    struct ReminderTarget: Identifiable {
        let flight: Flight
        let alarm: AlarmRecord
        var id: String { alarm.id }
    }


    enum SheetKind: Identifiable {
        case personal(AlarmRecord?), timer, interval(IntervalReminder?)
        var id: String {
            switch self {
            case .personal(let a): return "personal" + (a?.id ?? "new")
            case .timer: return "timer"
            case .interval(let r): return "interval" + (r?.id ?? "new")
            }
        }
    }

    private var personal: [AlarmRecord] { store.alarms.filter { $0.kind == .personal }.sorted { $0.time < $1.time } }
    private var timers: [AlarmRecord] {
        store.alarms.filter { $0.kind == .timer || $0.kind == .rest }.sorted { $0.time < $1.time }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.alarmAllowed {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("System alarms are disabled", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline).foregroundStyle(.orange)
                            Text("Enable CrewClock alarms in iPhone Settings so reminders can ring.")
                                .font(.footnote).foregroundStyle(Color.ccMuted)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                        .plainRow()
                    }
                }
                Section { RestPlannerCard().cardRow() }

                Section {
                    ForEach(personal) { a in personalRow(a) }
                    if personal.isEmpty { emptyRow("No personal alarms. Tap + to set a time.") }
                } header: {
                    header("Personal alarms", label: "New personal alarm") { sheet = .personal(nil) }
                }

                Section {
                    ForEach(timers) { a in timerRow(a) }
                    if timers.isEmpty { emptyRow("No timers.") }
                } header: {
                    header("Timers", label: "New timer") { sheet = .timer }
                }

                Section {
                    ForEach(store.intervals) { r in intervalRow(r) }
                    if store.intervals.isEmpty { emptyRow("No repeating reminders.") }
                } header: {
                    header("Repeating reminders", label: "New repeating reminder") { sheet = .interval(nil) }
                } footer: {
                    Text("After Stop, the next reminder is scheduled for the selected interval.")
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .refreshable { await store.refresh() }
            .navigationTitle("Alarms")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $editingReminder) { t in ReminderSheet(flight: t.flight, existing: t.alarm) }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .personal(let a): PersonalAlarmSheet(existing: a)
                case .timer: TimerSheet()
                case .interval(let r): IntervalSheet(existing: r)
                }
            }
        }
    }

    private func header(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.ccInk).textCase(nil)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.ccBlue)
            }
            .accessibilityLabel(label)
        }
        .padding(.bottom, 4)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Color.ccMuted).plainRow()
    }

    private func delete(_ id: String) { Task { await store.run { try await store.deleteAlarm(id) } } }

    private func personalRow(_ a: AlarmRecord) -> some View {
        let zone = a.zone ?? store.deviceZone
        let status = store.status(a)
        return HStack {
            Button { sheet = .personal(a) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.time(a.time, zone: zone) + " (L)")
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(a.active ? Color.ccBlue : Color.ccMuted)
                    Text(Fmt.displayDate(a.time, zone: zone) + (a.label.isEmpty ? "" : " · \(a.label)"))
                        .font(.footnote).foregroundStyle(Color.ccMuted).lineLimit(1)
                    if !["Scheduled", "Paused", "Done"].contains(status) {
                        Text(status).font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Toggle("Armed", isOn: Binding(get: { a.armed }, set: { on in
                Task { await store.run { try await store.toggleAlarm(a.id, armed: on) } }
            }))
            .labelsHidden()
        }
        .opacity(!a.dismissed && a.time < Date() ? 0.5 : 1)
        .plainRow()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(a.id) } label: { Label("Delete", systemImage: "trash") }
            Button { sheet = .personal(a) } label: { Label("Edit", systemImage: "pencil") }.tint(.ccBlue)
        }
    }

    private func timerRow(_ a: AlarmRecord) -> some View {
        let zone = store.deviceZone
        return VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.time(a.time, zone: zone) + " (L)")
                .font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundStyle(Color.ccBlue)
            Text(Fmt.displayDate(a.time, zone: zone) + " · \(a.label)")
                .font(.footnote).foregroundStyle(Color.ccMuted).lineLimit(1)
            if a.kind == .timer {
                CountdownBar(next: a.time, minutes: a.durationMinutes ?? 60, enabled: a.active)
            }
        }
        .plainRow()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(a.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func intervalTitle(_ r: IntervalReminder) -> String {
        let every = "Every \(r.minutes / 60)h \(r.minutes % 60)m"
        return ["Repeating reminder", "Repeating reminders", ""].contains(r.label) ? every : "\(r.label) · \(every)"
    }

    private func saveIntervals(_ next: [IntervalReminder]) {
        Task { await store.run { try await store.saveIntervals(next) } }
    }

    private func intervalRow(_ r: IntervalReminder) -> some View {
        let next = store.intervalNext(r)
        let headline = next.map { Fmt.stamp($0, zone: store.deviceZone) + " (L)" }
            ?? (r.enabled ? "No upcoming alarm reserved" : "Paused")
        return HStack {
            Button { sheet = .interval(r) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.headline.monospacedDigit()).foregroundStyle(Color.ccBlue)
                    Text(intervalTitle(r)).font(.footnote).foregroundStyle(Color.ccMuted)
                    CountdownBar(next: next, minutes: r.minutes, enabled: r.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Toggle("Enabled", isOn: Binding(get: { r.enabled }, set: { on in
                saveIntervals(store.intervals.map { x in
                    var y = x
                    if x.id == r.id { y.enabled = on; y.anchor = Date() }
                    return y
                })
            }))
            .labelsHidden()
        }
        .plainRow()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { saveIntervals(store.intervals.filter { $0.id != r.id }) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { sheet = .interval(r) } label: { Label("Edit", systemImage: "pencil") }.tint(.ccBlue)
        }
    }
}

/// Plans equal in-flight rest periods for a roster flight and reserves
/// one-shot alarms for the changeovers.
struct RestPlannerCard: View {
    @Environment(AppStore.self) private var store
    @State private var flightID: String?
    @State private var draft: RestConfig?
    @State private var error: String?
    @State private var saving = false
    @State private var addingArrival: Flight?

    var body: some View {
        let flights = store.restFlights
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if let flight = flights.first(where: { $0.id == flightID }) ?? flights.first {
                    planner(flight, flights)
                } else {
                    SectionLabel("In-flight rest", color: .ccMint)
                    Text("Add a flight with an arrival time to split its rest periods.")
                        .font(.subheadline).foregroundStyle(Color.ccMuted)
                    if let missing = store.sortedFlights.first(where: { $0.arrival == nil && $0.departure > Date() }) {
                        Button { addingArrival = missing } label: {
                            Label("Add arrival time to \(missing.number) \(missing.from) → \(missing.to)", systemImage: "clock.badge.plus")
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .sheet(item: $addingArrival) { f in FlightEditorSheet(existing: f, home: store.home) }
    }

    private func config(_ f: Flight) -> RestConfig {
        if flightID == f.id, let draft { return draft }
        return store.restConfig(f)
    }

    private func set(_ f: Flight, _ change: (inout RestConfig) -> Void) {
        var next = config(f)
        change(&next)
        next.mine = min(max(next.mine, 0), next.periods - 1)
        flightID = f.id
        draft = next
        error = nil
    }

    @ViewBuilder
    private func planner(_ f: Flight, _ flights: [Flight]) -> some View {
        let cfg = config(f)
        let saved = store.restAlarms(f)
        let plan = try? store.restPlan(f, cfg)
        let problem = error ?? planError(f, cfg)
        let delay = Double(cfg.delay) * 60
        let dep = f.departure.addingTimeInterval(delay)
        let arr = (f.arrival ?? f.departure).addingTimeInterval(delay)

        HStack {
            SectionLabel("In-flight rest", color: .ccMint)
            Spacer()
            if !saved.isEmpty {
                Text("\(saved.count) alarm\(saved.count == 1 ? "" : "s") set").font(.caption.weight(.semibold)).foregroundStyle(Color.ccMuted)
            }
        }
        Menu {
            ForEach(flights.prefix(12)) { option in
                Button(store.flightLabel(option)) { flightID = option.id; draft = nil; error = nil }
            }
        } label: {
            HStack {
                Text("\(f.number)  \(f.from) → \(f.to)").font(.title3.weight(.bold)).foregroundStyle(Color.ccInk)
                Spacer()
                if flights.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Color.ccMuted) }
            }
        }
        .disabled(flights.count < 2 || saving)
        Text("Block \(Fmt.time(dep, zone: "UTC"))–\(Fmt.time(arr, zone: "UTC")) Z · \(Fmt.span(Int(arr.timeIntervalSince(dep) / 60)))")
            .font(.subheadline).foregroundStyle(Color.ccMuted)

        if let plan {
            restBar(plan, dep: dep, arr: arr, mine: cfg.mine)
            ForEach(Array(plan.periods.enumerated()), id: \.offset) { index, period in
                periodRow(index, period, f, mine: index == cfg.mine)
            }
        }
        segments("Rest periods", values: Array(2...4), selection: cfg.periods) { v in set(f) { $0.periods = v } }
        segments("My rest", values: Array(1...cfg.periods), selection: cfg.mine + 1) { v in set(f) { $0.mine = v - 1 } }
        stepper("Start after departure", cfg.after, range: 0...180) { v in set(f) { $0.after = v } }
        stepper("End before arrival", cfg.before, range: 0...180) { v in set(f) { $0.before = v } }
        stepper("Departure delay", cfg.delay, range: -60...600, signed: true) { v in set(f) { $0.delay = v } }
        Toggle("Alarm at every changeover", isOn: Binding(get: { cfg.all }, set: { v in set(f) { $0.all = v } }))
            .foregroundStyle(Color.ccInk)
        if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
        HStack {
            let planned = plan?.alarms.count ?? 0
            Button {
                save(f, cfg)
            } label: {
                Text(saved.isEmpty ? "Set \(planned) rest alarm\(planned == 1 ? "" : "s")" : "Update rest alarms")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            .disabled(saving || plan == nil || planned == 0)
            if !saved.isEmpty {
                Button("Clear") { save(f, nil) }.disabled(saving)
            }
        }
        Text("Uses roster block times. Adjust the delay after the actual departure. Personal reminder only.")
            .font(.caption).foregroundStyle(Color.ccMuted)
    }

    private func planError(_ f: Flight, _ cfg: RestConfig) -> String? {
        do { _ = try store.restPlan(f, cfg); return nil } catch { return error.localizedDescription }
    }

    private func save(_ f: Flight, _ cfg: RestConfig?) {
        saving = true
        error = nil
        Task {
            do {
                try await store.saveRestPlan(f, cfg)
                if cfg == nil { draft = nil }
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private func restBar(_ plan: RestPlan, dep: Date, arr: Date, mine: Int) -> some View {
        let total = max(1, arr.timeIntervalSince(dep))
        return GeometryReader { g in
            HStack(spacing: 2) {
                let lead = plan.periods[0].start.timeIntervalSince(dep) / total
                Rectangle().fill(Color.ccBlueSoft).frame(width: max(2, g.size.width * CGFloat(lead)))
                ForEach(Array(plan.periods.enumerated()), id: \.offset) { index, _ in
                    Rectangle().fill(index == mine ? Color.ccMint : Color.ccMint.opacity(0.3))
                }
                let tail = arr.timeIntervalSince(plan.periods[plan.periods.count - 1].end) / total
                Rectangle().fill(Color.ccBlueSoft).frame(width: max(2, g.size.width * CGFloat(tail)))
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func periodRow(_ index: Int, _ period: (start: Date, end: Date), _ f: Flight, mine: Bool) -> some View {
        let zone = store.zone(f.from)
        return HStack(spacing: 10) {
            Text(mine ? "MINE" : "Rest \(index + 1)").font(.caption.weight(.bold))
                .foregroundStyle(mine ? Color.ccMint : Color.ccMuted).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Fmt.time(period.start, zone: "UTC"))–\(Fmt.time(period.end, zone: "UTC")) Z")
                    .font(.headline.monospacedDigit()).foregroundStyle(Color.ccInk)
                Text("\(Fmt.time(period.start, zone: zone))–\(Fmt.time(period.end, zone: zone)) \(f.from) time")
                    .font(.caption).foregroundStyle(Color.ccMuted)
            }
            Spacer()
            Text(Fmt.span(Int(period.end.timeIntervalSince(period.start) / 60)))
                .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ccInk)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(LinearGradient(colors: mine ? [Color.ccMint.opacity(0.34), .ccMintSoft, .ccCard] : [Color.ccBlue.opacity(0.34), .ccBlueSoft, .ccCard],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func segments(_ label: String, values: [Int], selection: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.ccInk)
            Spacer()
            Picker(label, selection: Binding(get: { selection }, set: onChange)) {
                ForEach(values, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: CGFloat(values.count) * 52)
            .disabled(saving)
        }
    }

    private func stepper(_ label: String, _ value: Int, range: ClosedRange<Int>, signed: Bool = false,
                         onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Color.ccInk)
            Spacer()
            Button { onChange(value - 5) } label: { Image(systemName: "minus.circle").font(.title2).frame(width: 40, height: 40) }
                .disabled(saving || value - 5 < range.lowerBound)
                .accessibilityLabel("Decrease \(label)")
            Text((signed && value > 0 ? "+" : value < 0 ? "−" : "") + Fmt.short(value))
                .font(.body.weight(.bold).monospacedDigit()).foregroundStyle(Color.ccInk)
                .frame(width: 70).lineLimit(1).minimumScaleFactor(0.8)
            Button { onChange(value + 5) } label: { Image(systemName: "plus.circle").font(.title2).frame(width: 40, height: 40) }
                .disabled(saving || value + 5 > range.upperBound)
                .accessibilityLabel("Increase \(label)")
        }
    }
}
