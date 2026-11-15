import SwiftUI

struct DayAlarm: Identifiable {
    let id: String
    let time: Date
    let zone: String?
    let label: String
    let active: Bool
}

struct RosterView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: EditTarget?
    @State private var editingFlight: Flight?
    @State private var pickingDay = false
    @State private var deleting: Flight?
    @State private var delaying: Flight?
    @State private var listing = false

    struct EditTarget: Identifiable {
        let flight: Flight
        let alarm: AlarmRecord?
        var id: String { flight.id + (alarm?.id ?? "new") }
    }

    private var dayFlights: [Flight] { store.flightsOn(store.rosterDay) }
    private var dayDuties: [Duty] { store.duties.filter { $0.date == store.rosterDay } }
    private var dayDate: Date { Fmt.date(ymd: store.rosterDay) ?? Date() }

    private var dayAlarms: [DayAlarm] {
        dayFlights.flatMap { f in
            store.flightAlarms(f).map {
                DayAlarm(id: $0.id, time: $0.time, zone: store.shown(f.from), label: $0.label, active: $0.active)
            }
        }
        .sorted { $0.time < $1.time }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    dayBar.cardRow()
                    RosterClockCard(alarms: dayAlarms, day: dayDate, suffix: store.suffix).cardRow()
                    Text("\(Fmt.displayDate(dayDate, zone: "UTC")) · Departure local date")
                        .font(.footnote).foregroundStyle(Color.ccMuted)
                        .frame(maxWidth: .infinity, alignment: .center).cardRow()
                }
                if dayFlights.isEmpty || !dayDuties.isEmpty {
                  Section {
                    ForEach(dayDuties) { duty in
                        Label {
                            VStack(alignment: .leading) {
                                Text(duty.category).foregroundStyle(Color.ccInk)
                                Text(duty.label).font(.caption).foregroundStyle(Color.ccMuted)
                            }
                        } icon: {
                            Image(systemName: duty.category == "Off / leave" ? "bed.double" : "doc.text")
                        }
                        .plainRow()
                    }
                    if dayFlights.isEmpty {
                        Text("No flights on this day. Choose another date or import your roster.")
                            .foregroundStyle(Color.ccMuted).plainRow()
                    }
                  }
                }
                ForEach(dayFlights) { f in flightSection(f) }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .refreshable { await store.refresh() }
            .navigationTitle("Roster")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { listing = true } label: { Label("All flights", systemImage: "list.bullet") }
                }
                AddRosterToolbar()
            }
            .sheet(isPresented: $listing) { RosterListSheet() }
            .onAppear { store.followUpcomingDay() }
            .onChange(of: store.flights) { _, _ in store.followUpcomingDay() }
            .sheet(item: $editing) { target in ReminderSheet(flight: target.flight, existing: target.alarm) }
            .sheet(item: $editingFlight) { f in FlightEditorSheet(existing: f, home: store.home) }
            .sheet(isPresented: $pickingDay) { dayPicker }
            .sheet(item: $delaying) { f in DelaySheet(flight: f) }
            .confirmationDialog("Delete this flight?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete flight and its alarms", role: .destructive) {
                    if let f = deleting { Task { await store.run { try await store.deleteFlight(f) } } }
                }
            }
        }
    }

    private var dayBar: some View {
        HStack {
            Button { store.shiftRosterDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous day")
            Spacer()
            Button { pickingDay = true } label: {
                VStack(spacing: 2) {
                    Text(Fmt.format(dayDate, "EEE, MMM d", zone: "UTC")).font(.headline)
                    Text("Tap to choose a date").font(.caption).foregroundStyle(Color.ccMuted)
                }
            }
            Spacer()
            Button { store.shiftRosterDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.ccInk)
        .padding(.horizontal, 4)
        .background(Color.ccCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var dayPicker: some View {
        NavigationStack {
            DatePicker("Date", selection: Binding(
                get: { dayDate },
                set: { store.followUpcoming = false; store.rosterDay = Fmt.ymd($0, zone: "UTC") }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                .padding()
                .navigationTitle("Choose date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickingDay = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func flightSection(_ f: Flight) -> some View {
        Section {
            HStack(spacing: 12) {
                Text(Fmt.badge(f.departure, zone: store.zone(f.from)))
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.ccBlue, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(f.number) · \(f.from) → \(f.to)").font(.headline).foregroundStyle(Color.ccInk)
                    Text(flightTimes(f)).font(.caption).foregroundStyle(Color.ccMuted)
                }
                Spacer()
                Menu {
                    Button { editing = EditTarget(flight: f, alarm: nil) } label: { Label("Add reminder", systemImage: "plus") }
                    Button { delaying = f } label: { Label("Departure delayed…", systemImage: "clock.arrow.circlepath") }
                    Button { editingFlight = f } label: { Label("Edit flight", systemImage: "pencil") }
                    Button { store.selectedFlightID = f.id; store.tab = 0 } label: { Label("Show in Briefing", systemImage: "airplane") }
                    Button(role: .destructive) { deleting = f } label: { Label("Delete flight", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                }
            }
            .listRowBackground(Color.ccBlueSoft)
            ForEach(store.flightAlarms(f)) { a in alarmRow(a, f) }
            if let gap = store.groundGap(before: f) {
                Label("Ground time before · \(AppStore.gapText(gap.minutes)) since \(gap.previous.number)", systemImage: "clock")
                    .font(.footnote).foregroundStyle(Color.ccMuted).plainRow()
            }
            if let lay = store.layover(after: f) {
                Label("Layover \(f.to) · \(AppStore.gapText(lay.minutes)) until \(lay.next.number)", systemImage: "bed.double")
                    .font(.footnote).foregroundStyle(Color.ccMint).plainRow()
            }
        }
    }

    private func flightTimes(_ f: Flight) -> String {
        let dep = "Departs \(f.from) \(Fmt.time(f.departure, zone: store.shown(f.from))) (\(store.suffix))"
        guard let arrival = f.arrival else { return dep }
        return dep + " · Arrives \(f.to) \(Fmt.time(arrival, zone: store.shown(f.to))) (\(store.suffix))"
    }

    private func alarmRow(_ a: AlarmRecord, _ f: Flight) -> some View {
        let status = store.status(a)
        let offset = Int(f.departure.timeIntervalSince(a.time) / 60)
        let passed = !a.dismissed && a.time < Date()
        return Button { editing = EditTarget(flight: f, alarm: a) } label: {
            HStack(spacing: 10) {
                Text(Fmt.time(a.time, zone: store.shown(f.from)) + " (\(store.suffix))")
                    .font(.headline.monospacedDigit()).foregroundStyle(Color.ccBlue)
                Text(a.label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ccInk).lineLimit(1)
                Spacer()
                Text(Fmt.offset(offset)).font(.caption).foregroundStyle(Color.ccMuted)
                if !["Scheduled", "Done"].contains(status) {
                    Image(systemName: status == "Paused" ? "pause.circle" : "info.circle")
                        .foregroundStyle(status == "Paused" ? Color.ccMuted : Color.orange)
                        .accessibilityLabel(status)
                }
            }
            .opacity(passed ? 0.4 : 1)
        }
        .plainRow()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await store.run { try await store.deleteAlarm(a.id) } } } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { Task { await store.run { try await store.toggleAlarm(a.id, armed: !a.armed) } } } label: {
                Label(a.armed ? "Pause" : "Resume", systemImage: a.armed ? "pause" : "play")
            }
            .tint(.ccGround)
        }
    }
}

/// Shows the selected day's alarms in order: the next one is drawn boldly,
/// the others stay as thin hands. The current time sits in the badge below.
struct RosterClockCard: View {
    let alarms: [DayAlarm]
    let day: Date
    var suffix = "L"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let next = alarms.first { $0.active && $0.time > ctx.date }
            HStack(spacing: 16) {
                AlarmDial(hands: hands(next: next), dateText: Fmt.format(day, "MMM d", zone: "UTC").uppercased())
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(title(next), color: .ccBlue)
                    if let shown = next ?? alarms.first {
                        Text(Fmt.time(shown.time, zone: shown.zone) + " (\(suffix))")
                            .font(.system(size: 32, weight: .heavy).monospacedDigit())
                            .foregroundStyle(next == nil ? Color.ccMuted : Color.ccInk)
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text(shown.label).font(.subheadline).foregroundStyle(Color.ccMuted).lineLimit(1)
                        sequence(next: next, now: ctx.date)
                    } else {
                        Text("No flight alarms on this day").font(.subheadline).foregroundStyle(Color.ccMuted)
                    }
                    Text("Now \(Fmt.time(ctx.date, zone: TimeZone.current.identifier)) · \(Fmt.format(ctx.date, "MM/dd", zone: TimeZone.current.identifier))")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.ccBlue.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.ccBlue)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(LinearGradient(colors: [.ccBlueSoft, .ccCard], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func title(_ next: DayAlarm?) -> String {
        guard let next else { return alarms.isEmpty ? "Alarms" : "All alarms passed" }
        return next.id == alarms.first?.id ? "First alarm" : "Next alarm"
    }

    private func sequence(next: DayAlarm?, now: Date) -> some View {
        HStack(spacing: 6) {
            ForEach(alarms) { a in
                Text(Fmt.time(a.time, zone: a.zone))
                    .font(.caption.weight(a.id == next?.id ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(a.id == next?.id ? Color.ccBlue : Color.ccMuted)
                    .opacity(a.time < now ? 0.5 : 1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityLabel("Alarm order")
    }

    private func hands(next: DayAlarm?) -> [AlarmDial.Hand] {
        alarms.map { a in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: a.zone ?? "UTC") ?? TimeZone(identifier: "UTC")!
            let c = cal.dateComponents([.hour, .minute], from: a.time)
            return AlarmDial.Hand(hour: c.hour ?? 0, minute: c.minute ?? 0, primary: a.id == next?.id)
        }
    }
}

struct AlarmDial: View {
    struct Hand {
        let hour: Int
        let minute: Int
        let primary: Bool
    }
    let hands: [Hand]
    let dateText: String

    private let face = Color(red: 0.07, green: 0.13, blue: 0.22)
    private let accent = Color(red: 0.45, green: 0.72, blue: 1.0)
    private let mark = Color(red: 1.0, green: 0.85, blue: 0.47)

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            func point(_ angle: Double, _ length: CGFloat) -> CGPoint {
                CGPoint(x: c.x + CGFloat(sin(angle)) * length, y: c.y - CGFloat(cos(angle)) * length)
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat) {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            let outer = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: outer), with: .color(face))
            ctx.stroke(Path(ellipseIn: outer.insetBy(dx: 1, dy: 1)), with: .color(accent.opacity(0.45)), lineWidth: 2)
            for i in 0..<60 {
                let angle = Double(i) * Double.pi / 30
                let major = i % 5 == 0
                let inner: CGFloat = major ? r - 13 : r - 9
                let color: Color = major ? Color.white.opacity(0.9) : Color.white.opacity(0.35)
                line(point(angle, inner), point(angle, r - 5), color, major ? 2 : 1)
            }
            for hour in 1...12 {
                let p = point(Double(hour) * Double.pi / 6, r - 25)
                let text = Text("\(hour)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                ctx.draw(text, at: p)
            }
            // Like a watch face, the date window sits under the hands.
            let window = CGRect(x: c.x - 24, y: c.y + r * 0.30 - 8, width: 48, height: 16)
            let shape = Path(roundedRect: window, cornerRadius: 6)
            ctx.fill(shape, with: .color(Color(red: 0.03, green: 0.06, blue: 0.1)))
            ctx.stroke(shape, with: .color(accent.opacity(0.6)), lineWidth: 1)
            let label = Text(dateText).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
            ctx.draw(label, at: CGPoint(x: window.midX, y: window.midY))
            // Every alarm of the day stays visible; the next one is drawn on top.
            let ordered = hands.filter { !$0.primary } + hands.filter(\.primary)
            for hand in ordered {
                let hourAngle = (Double(hand.hour % 12) + Double(hand.minute) / 60) * Double.pi / 6
                let minuteAngle = Double(hand.minute) * Double.pi / 30
                let alpha: Double = hand.primary ? 1 : 0.4
                // Hour and minute hands of one alarm share a colour.
                let color: Color = hand.primary ? Color.white : accent.opacity(alpha)
                line(c, point(hourAngle, r * 0.48), color, hand.primary ? 5 : 1.6)
                line(c, point(minuteAngle, r * 0.72), color, hand.primary ? 3.5 : 1.6)
                line(point(minuteAngle, r - 13), point(minuteAngle, r - 5), mark.opacity(0.9), 2.4)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(accent))
        }
        .accessibilityLabel("Alarm clock for the selected day")
    }
}
