import SwiftUI

@main
struct CrewClockApp: App {
    @State private var store = AppStore()
    @State private var importer = ImportCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    private var scheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var store = store
            TabView(selection: $store.tab) {
                Tab("Briefing", systemImage: "airplane", value: 0) { BriefingView().safeAreaPadding(.top, 12) }
                Tab("Roster", systemImage: "calendar", value: 1) { RosterView().safeAreaPadding(.top, 12) }
                Tab("Alarms", systemImage: "alarm", value: 2) { AlarmsView().safeAreaPadding(.top, 12) }
                Tab("Settings", systemImage: "gearshape", value: 3) { SettingsView().safeAreaPadding(.top, 12) }
            }
            .tint(.ccBlue)
            .modifier(RosterImportModifier())
            .alert("CrewClock", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.notice ?? "")
            }
            .environment(store)
            .environment(importer)
            .preferredColorScheme(scheme)
            .task { await store.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .crewAlarmDismissed)) { _ in
                Task { await store.refresh() }
            }
            .onOpenURL { url in
                if url.host == "alarms" { store.tab = 2 }
                if url.host == "briefing" { store.tab = 0 }
            }
        }
    }
}
