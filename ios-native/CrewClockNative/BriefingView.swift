import SwiftUI

struct BriefingView: View {
    @Environment(AppStore.self) private var store
    @Environment(ImportCoordinator.self) private var importer
    @State private var newTask = ""
    @State private var editMode = EditMode.inactive
    @State private var editingReminder: AlarmRecord?
    @State private var addingReminder = false
    @State private var delaying = false
    @State private var renaming: PrepTask?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let f = store.briefingFlight {
                    content(f)
                } else {
                    ContentUnavailableView {
                        Label("No upcoming flights", systemImage: "airplane")
                    } description: {
                        Text("Add your roster to see the briefing, preparation reminders and in-flight rest.")
                    } actions: {
                        Button("Add Roster") { importer.showMenu = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Briefing")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { AddRosterToolbar() }
        }
    }

    private func content(_ f: Flight) -> some View {
        let steps = store.flightAlarms(f)
        let next = steps.first { $0.active && $0.time > Date() }
        let state = store.briefing(f)
        return List {
            Section {
                ForEach(store.expiringDocuments) { d in
                    Label(d.daysLeft < 0 ? "\(d.name) expired on \(Fmt.ymd(d.expiry, zone: store.deviceZone))"
                                         : "\(d.name) expires in \(d.daysLeft) days · \(Fmt.ymd(d.expiry, zone: store.deviceZone))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .cardRow()
                }
                flightPicker(f).cardRow()
                hero(f).cardRow()
                DutyRibbonView(ribbon: store.dutyRibbon(f)).cardRow()
                zones(f).cardRow()
            }
            Section {
                ForEach(steps) { a in stepRow(a, f, isNext: a.id == next?.id) }
                if steps.isEmpty {
                    Text("No preparation reminders. Configure them in Settings.").foregroundStyle(Color.ccMuted).plainRow()
                }
                Button { addingReminder = true } label: { Label("Add reminder", systemImage: "plus") }.plainRow()
                Button { delaying = true } label: { Label("Departure delayed…", systemImage: "clock.arrow.circlepath") }.plainRow()
            } header: {
                Text("Preparation reminders")
            }
            Section {
                ForEach(state.tasks) { task in taskRow(task, f) }
                    .onDelete { offsets in store.updateBriefing(f) { $0.tasks.remove(atOffsets: offsets) } }
                    .onMove { from, to in store.updateBriefing(f) { $0.tasks.move(fromOffsets: from, toOffset: to) } }
                if state.tasks.count < 12 {
                    HStack {
                        TextField("New preparation item", text: $newTask).onSubmit { addTask(f) }
                        Button("Add") { addTask(f) }
                            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .plainRow()
                }
            } header: {
                HStack {
                    Text("Personal preparation · \(state.tasks.filter { $0.checkedAt != nil }.count) / \(state.tasks.count) checked")
                    Spacer()
                    EditButton().font(.footnote)
                }
            } footer: {
                Text("Personal organization only. Use your airline’s official operational procedures and roster.")
            }
        }
        .listStyle(.insetGrouped)
            .contentMargins(.top, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.editMode, $editMode)
        .refreshable { await store.refresh() }
        .sheet(item: $editingReminder) { a in ReminderSheet(flight: f, existing: a) }
        .sheet(isPresented: $addingReminder) { ReminderSheet(flight: f, existing: nil) }
        .sheet(isPresented: $delaying) { DelaySheet(flight: f) }
        .alert("Rename item", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Preparation item", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                guard let id = renaming?.id, !name.isEmpty, name.count <= 100 else { return }
                store.updateBriefing(f) { s in
                    if let i = s.tasks.firstIndex(where: { $0.id == id }) { s.tasks[i].label = name }
                }
            }
        }
    }

    private func addTask(_ f: Flight) {
        let label = newTask.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label.count <= 100 else { return }
        store.updateBriefing(f) { s in
            if s.tasks.count < 12 { s.tasks.append(PrepTask(id: "task_\(store.newID())", label: label)) }
        }
        newTask = ""
    }

    private func flightPicker(_ f: Flight) -> some View {
        Menu {
            ForEach(store.sortedFlights.filter { $0.departure > Date() }) { option in
                Button {
                    store.selectedFlightID = option.id
                } label: {
                    if option.id == f.id { Label(store.flightLabel(option), systemImage: "checkmark") } else { Text(store.flightLabel(option)) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "airplane.departure").foregroundStyle(Color.ccBlue)
                Text(store.flightLabel(f)).font(.body.weight(.medium)).foregroundStyle(Color.ccInk).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Color.ccMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.ccCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func hero(_ f: Flight) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel("\(f.number) · \(Fmt.badge(f.departure, zone: store.zone(f.from)))" + (store.settings.displayUTC ? " · UTC" : ""), color: .ccBlue)
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(countdown(to: f.departure, now: ctx.date))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.ccBlue.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.ccBlue)
                }
            }
            HStack(alignment: .top) {
                airport(f.from, Fmt.time(f.departure, zone: store.shown(f.from)), .leading)
                VStack(spacing: 4) {
                    Image(systemName: "airplane").foregroundStyle(Color.ccBlue)
                    Rectangle().fill(Color.ccBlue.opacity(0.3)).frame(height: 2)
                    if let arrival = f.arrival {
                        Text("\(Fmt.span(Int(arrival.timeIntervalSince(f.departure) / 60))) block")
                            .font(.caption).foregroundStyle(Color.ccMuted)
                    }
                }
                .padding(.top, 12).padding(.horizontal, 8)
                airport(f.to, f.arrival.map { Fmt.time($0, zone: store.shown(f.to)) } ?? "—", .trailing)
            }
            nextAlarmLine(f)
            dutyLines(f)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.ccBlueSoft, .ccCard], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func nextAlarmLine(_ f: Flight) -> some View {
        if let next = store.flightAlarms(f).first(where: { $0.active && $0.time > Date() }) {
            let status = store.status(next)
            let ok = status == "Scheduled"
            HStack(spacing: 6) {
                Image(systemName: ok ? "alarm.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.ccMint : Color.orange)
                Text("Next alarm \(Fmt.time(next.time, zone: store.shown(f.from))) (\(store.suffix)) · \(next.label)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ccInk).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(ok ? "Scheduled" : status).font(.caption.weight(.semibold))
                    .foregroundStyle(ok ? Color.ccMint : Color.orange).lineLimit(1)
            }
        } else {
            Label("No upcoming alarm for this flight", systemImage: "alarm")
                .font(.subheadline).foregroundStyle(Color.ccMuted)
        }
    }

    @ViewBuilder
    private func dutyLines(_ f: Flight) -> some View {
        let report = store.settings.reportMinutes
        if report > 0 {
            let at = f.departure.addingTimeInterval(-Double(report) * 60)
            let fdp = f.arrival.map { " · FDP \(Fmt.span(Int($0.timeIntervalSince(at) / 60)))" } ?? ""
            Label("Report \(Fmt.time(at, zone: store.shown(f.from))) (\(store.suffix))\(fdp)", systemImage: "person.badge.clock")
                .font(.subheadline).foregroundStyle(Color.ccInk)
        }
        if let gap = store.groundGap(before: f) {
            Label("Ground time before · \(AppStore.gapText(gap.minutes)) since \(gap.previous.number)", systemImage: "clock")
                .font(.subheadline).foregroundStyle(Color.ccMuted)
        }
        if let lay = store.layover(after: f) {
            Label("Layover \(f.to) · \(AppStore.gapText(lay.minutes)) until \(lay.next.number)", systemImage: "bed.double")
                .font(.subheadline).foregroundStyle(Color.ccMuted)
        }
    }

    private func airport(_ code: String, _ time: String, _ align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(code).font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.ccInk)
            Text(time).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ccBlue)
        }
    }

    private func countdown(to d: Date, now: Date) -> String {
        let s = d.timeIntervalSince(now)
        if s <= 0 { return "Departed" }
        let days = Int(s / 86400), hours = Int(s / 3600) % 24, minutes = Int(s / 60) % 60
        return days > 0 ? "in \(days)d \(hours)h" : "in \(hours)h \(minutes)m"
    }

    private func zones(_ f: Flight) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Departure time across zones")
                HStack(spacing: 8) {
                    tile(f.from, Fmt.time(f.departure, zone: store.zone(f.from)) + " (L)", highlight: true)
                    tile("\(store.home) home", Fmt.time(f.departure, zone: store.homeZone) + " (L)", highlight: false)
                    tile("UTC", Fmt.time(f.departure, zone: "UTC") + " (Z)", highlight: false)
                }
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("\(f.to) local time now \(Fmt.time(ctx.date, zone: store.zone(f.to))) · \(Fmt.badge(ctx.date, zone: store.zone(f.to)))")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.ccInk)
                }
                Text("Same departure instant across the displayed time zones. Flight reminders stay on \(f.from) local time when you travel.")
                    .font(.caption).foregroundStyle(Color.ccMuted)
            }
        }
    }

    private func tile(_ label: String, _ time: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).lineLimit(1)
            Text(time).font(.headline.monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(highlight ? Color.white : Color.ccInk)
        .background(highlight ? Color.ccBlue : Color.ccBlueSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepRow(_ a: AlarmRecord, _ f: Flight, isNext: Bool) -> some View {
        let status = store.status(a)
        let offset = Int(f.departure.timeIntervalSince(a.time) / 60)
        return Button { editingReminder = a } label: {
            HStack(spacing: 10) {
                Circle().fill(isNext ? Color.ccBlue : Color.clear)
                    .overlay(Circle().stroke(isNext ? Color.ccBlue : Color.ccMuted, lineWidth: 2))
                    .frame(width: 10, height: 10)
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
        }
        .listRowBackground(isNext ? Color.ccBlueSoft : Color.ccCard)
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

    private func taskRow(_ task: PrepTask, _ f: Flight) -> some View {
        Button {
            if editMode.isEditing {
                renameText = task.label
                renaming = task
            } else {
                store.updateBriefing(f) { s in
                    if let i = s.tasks.firstIndex(where: { $0.id == task.id }) {
                        s.tasks[i].checkedAt = s.tasks[i].checkedAt == nil ? Date() : nil
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.checkedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(task.checkedAt == nil ? Color.ccMuted : Color.ccMint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.label).foregroundStyle(Color.ccInk)
                    if let at = task.checkedAt {
                        Text("Checked \(Fmt.stamp(at, zone: store.zone(f.from))) \(f.from)")
                            .font(.caption).foregroundStyle(Color.ccMuted)
                    }
                }
            }
        }
        .plainRow()
    }
}

struct DutyRibbonView: View {
    let ribbon: DutyRibbon
    private let labelWidth: CGFloat = 40
    private let rowHeight: CGFloat = 18
    private let barTop: CGFloat = 4

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(ribbon.blockMinutes.map { "Block \(Fmt.span($0))" } ?? "Block time unknown")
                        .font(.headline).foregroundStyle(Color.ccInk)
                    Spacer()
                    if let wocl = ribbon.woclFlightMinutes {
                        Text(wocl > 0 ? "WOCL \(Fmt.span(wocl))" : "No WOCL in flight")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ccMuted)
                    }
                }
                GeometryReader { g in
                    chart(width: g.size.width - labelWidth)
                }
                .frame(height: 30 + rowHeight * CGFloat(ribbon.axes.count))
                HStack(spacing: 14) {
                    legend(.ccGround, "Preparation")
                    legend(.ccBlue, "Flight")
                    legend(.ccSand, "WOCL · \(ribbon.home) 02–06")
                }
                .font(.caption).foregroundStyle(Color.ccMuted)
                Text("Home-base body-clock low, for reference only.").font(.caption).foregroundStyle(Color.ccMuted)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private func x(_ fraction: Double, _ width: CGFloat) -> CGFloat { labelWidth + CGFloat(fraction) * width }

    private func segment(_ from: Double, _ to: Double, _ width: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color)
            .frame(width: max(0, CGFloat(to - from) * width), height: 14)
            .offset(x: x(from, width), y: barTop)
    }

    private func chart(width: CGFloat) -> some View {
        let height = 30 + rowHeight * CGFloat(ribbon.axes.count)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(ribbon.wocl.enumerated()), id: \.offset) { _, band in
                Rectangle().fill(Color.ccSand.opacity(0.35))
                    .frame(width: max(2, CGFloat(band.to - band.from) * width), height: height)
                    .offset(x: x(band.from, width))
            }
            segment(0, 1, width, Color.ccBlueSoft)
            segment(ribbon.prep, ribbon.dep, width, .ccGround)
            if let arr = ribbon.arr { segment(ribbon.dep, arr, width, .ccBlue) }
            ForEach(Array(ribbon.steps.enumerated()), id: \.offset) { _, s in
                Circle().fill(Color.white).overlay(Circle().stroke(Color.ccBlue, lineWidth: 2))
                    .frame(width: 9, height: 9)
                    .offset(x: x(s, width) - 4.5, y: barTop + 2.5)
            }
            if let now = ribbon.now {
                Rectangle().fill(Color.red).frame(width: 2, height: height).offset(x: x(now, width) - 1)
            }
            ForEach(Array(ribbon.axes.enumerated()), id: \.element.id) { index, axis in
                axisRow(axis, y: 30 + rowHeight * CGFloat(index), width: width)
            }
        }
    }

    private func axisRow(_ axis: RibbonAxis, y: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(axis.label).font(.caption2.weight(.semibold)).foregroundStyle(Color.ccMuted)
                .frame(width: labelWidth, alignment: .leading).offset(y: y)
            ForEach(Array(axis.ticks.enumerated()), id: \.offset) { _, tick in
                Text(tick.text).font(.caption2.monospacedDigit()).foregroundStyle(Color.ccInk)
                    .frame(width: 24).offset(x: x(tick.x, width) - 12, y: y)
            }
        }
    }
}
