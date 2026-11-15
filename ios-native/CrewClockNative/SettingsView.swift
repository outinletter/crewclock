import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var choosingSound = false
    @State private var soundLabel = AlarmEngine.soundLabel
    @State private var editingPreset: PresetTarget?
    @State private var confirmingReset = false
    @State private var editingDocument: DocumentItem?

    struct PresetTarget: Identifiable {
        let group: PresetGroup
        let preset: Preset
        var id: String { group.rawValue + preset.id }
    }

    private func update(_ change: @escaping (inout AppSettings) -> Void) {
        Task { await store.run { try await store.updateSettings(change) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: Binding(get: { store.settings.appearance }, set: { v in update { $0.appearance = v } })) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label("Appearance", systemImage: "moon")
                    }
                    Button { choosingSound = true } label: {
                        LabeledContent {
                            Text(soundLabel).foregroundStyle(Color.ccMuted)
                        } label: {
                            Label("Alarm sound", systemImage: "speaker.wave.2").foregroundStyle(Color.ccInk)
                        }
                    }
                    Toggle(isOn: Binding(get: { store.settings.liveActivity }, set: { v in update { $0.liveActivity = v } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Activity")
                            Text("Show the next alarm on the Lock Screen").font(.caption).foregroundStyle(Color.ccMuted)
                        }
                    }
                } header: {
                    Text("Appearance & sound")
                } footer: {
                    if let message = store.surfaceError { Text(message).foregroundStyle(.orange) }
                }
                .plainRow()

                Section {
                    Toggle(isOn: Binding(get: { store.settings.displayUTC }, set: { v in update { $0.displayUTC = v } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show times in UTC")
                            Text("Flight and reminder times use Z instead of airport-local time").font(.caption).foregroundStyle(Color.ccMuted)
                        }
                    }
                    Stepper(value: Binding(get: { store.settings.reportMinutes }, set: { v in update { $0.reportMinutes = v } }),
                            in: 0...300, step: 5) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Report before departure")
                            Text(store.settings.reportMinutes == 0 ? "Off" : Fmt.short(store.settings.reportMinutes))
                                .font(.caption.monospacedDigit()).foregroundStyle(Color.ccMuted)
                        }
                    }
                } header: {
                    Text("Duty display")
                } footer: {
                    Text("Report time and FDP (report to arrival of this flight) appear on the Briefing card. Check your operator's limits; this is not an official calculation.")
                }
                .plainRow()

                Section {
                    LabeledContent("System alarms") {
                        Text(AlarmEngine.authorized ? "Allowed" : (AlarmEngine.undetermined ? "Not requested yet" : "Not allowed"))
                            .foregroundStyle(AlarmEngine.authorized ? Color.ccMint : .orange)
                    }
                    Button("Retry alarm scheduling") { Task { await store.retryScheduling() } }.disabled(store.busy)
                } header: {
                    Text("Alarm permission")
                }
                .plainRow()

                Section {
                    HomeBaseRow(domestic: false)
                    HomeBaseRow(domestic: true)
                } header: {
                    Text("Home bases")
                } footer: {
                    Text("Three-letter airport codes separated by commas. The first one is your home time zone.")
                }
                .plainRow()

                ForEach(PresetGroup.allCases) { group in presetSection(group) }

                Section {
                    ForEach(store.documents) { d in
                        Button { editingDocument = d } label: {
                            LabeledContent {
                                Text(d.daysLeft < 0 ? "Expired" : "\(d.daysLeft) days")
                                    .foregroundStyle(d.daysLeft <= 90 ? Color.orange : Color.ccMuted)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundStyle(Color.ccInk)
                                    Text(Fmt.ymd(d.expiry, zone: store.deviceZone)).font(.caption).foregroundStyle(Color.ccMuted)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for id in offsets.map({ store.documents[$0].id }) { store.deleteDocument(id) }
                    }
                    Button {
                        editingDocument = DocumentItem(id: store.newID(), name: "", expiry: Date().addingTimeInterval(365 * 86400))
                    } label: {
                        Label("Add document", systemImage: "plus")
                    }
                } header: {
                    Text("Document expiry")
                } footer: {
                    Text("Passport, visa, medical and licence dates. Briefing warns from 90 days before expiry.")
                }
                .plainRow()

                Section {
                    Button(role: .destructive) { confirmingReset = true } label: {
                        Label("Delete all roster", systemImage: "trash")
                    }
                    .disabled(store.busy || store.flights.isEmpty)
                } header: {
                    Text("Reset roster data")
                } footer: {
                    Text("Removes flights and their linked flight alarms. Personal alarms, repeating reminders and settings are kept.")
                }
                .plainRow()

                Section {
                    Link(destination: URL(string: "https://outinletter.github.io/crewclock/privacy.html")!) {
                        Label("Privacy policy", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://outinletter.github.io/crewclock/support.html")!) {
                        Label("Support", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("Privacy & support")
                } footer: {
                    Text("Schedules and preparation notes stay on this device. Roster files and images are read on the device only.\n\nPersonal organization only. Use your airline’s official procedures and roster.")
                }
                .plainRow()
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $editingDocument) { d in DocumentSheet(existing: d) }
            .sheet(item: $editingPreset) { target in PresetSheet(group: target.group, preset: target.preset) }
            .confirmationDialog("Alarm Sound", isPresented: $choosingSound, titleVisibility: .visible) {
                ForEach(AlarmEngine.soundChoices, id: \.name) { choice in
                    Button(choice.label) {
                        do {
                            try AlarmEngine.chooseSound(choice.name)
                            soundLabel = choice.label
                            Task { await store.retryScheduling() }
                        } catch {
                            store.notice = error.localizedDescription
                        }
                    }
                }
            }
            .confirmationDialog("Delete all roster?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { Task { await store.run { try await store.clearRoster() } } }
            } message: {
                Text("Delete all \(store.flights.count) flights, their flight alarms and preparation lists? This cannot be undone.")
            }
        }
    }

    private func presetSection(_ group: PresetGroup) -> some View {
        let presets = store.settings.presetList(group)
        return Section {
            ForEach(presets) { preset in
                Button { editingPreset = PresetTarget(group: group, preset: preset) } label: {
                    LabeledContent {
                        Text(Fmt.offset(preset.minutes)).monospacedDigit().foregroundStyle(Color.ccMuted)
                    } label: {
                        Text(preset.label).foregroundStyle(Color.ccInk)
                    }
                }
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { presets[$0].id })
                update { s in
                    s.presets[group.rawValue] = (s.presets[group.rawValue] ?? group.defaults).filter { !ids.contains($0.id) }
                }
            }
            Button {
                editingPreset = PresetTarget(group: group, preset: Preset(id: "p\(store.newID())", label: "New reminder", minutes: 60))
            } label: {
                Label("Add preparation preset", systemImage: "plus")
            }
        } header: {
            Text("Presets · \(group.title)")
        } footer: {
            if group == .intl { Text("Changes apply to existing flights automatically. Swipe a preset to delete it.") }
        }
        .plainRow()
    }
}

struct HomeBaseRow: View {
    @Environment(AppStore.self) private var store
    let domestic: Bool
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var saved: String { store.settings.codes(domestic: domestic).joined(separator: ", ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(domestic ? "Domestic" : "International").foregroundStyle(Color.ccInk)
                TextField(domestic ? "GMP, CJU" : "ICN, PUS", text: $text)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(save)
                if text != saved {
                    Button("Save", action: save).buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { text = saved }
        .onChange(of: saved) { _, value in if !focused { text = value } }
    }

    private func save() {
        var seen = Set<String>()
        let codes = text.uppercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !codes.isEmpty, codes.allSatisfy({ $0.count == 3 && store.zone($0) != nil }) else {
            error = "Enter known airport codes separated by commas."
            return
        }
        error = nil
        focused = false
        let value = codes.joined(separator: ", ")
        Task {
            await store.run {
                try await store.updateSettings { s in
                    if domestic { s.domesticBaseApt = value } else { s.baseApt = value }
                }
            }
            text = saved
        }
    }
}
