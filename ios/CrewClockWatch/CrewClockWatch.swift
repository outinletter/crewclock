import SwiftUI
import WatchConnectivity

@MainActor final class CrewWatchModel: NSObject, ObservableObject, WCSessionDelegate {
  @Published var payload = CrewSurfacePayload.empty
  @Published var message = "Open CrewClock on your iPhone to sync."
  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: CrewSurfacePayload.key) { receive(data) }
    if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
  }
  func receive(_ data: Data) {
    guard let value = try? JSONDecoder().decode(CrewSurfacePayload.self, from: data) else { return }
    payload = value; message = ""
    UserDefaults.standard.set(data, forKey: CrewSurfacePayload.key)
  }
  func refresh() {
    guard WCSession.default.isReachable else { message = "iPhone unavailable. Showing last sync."; return }
    WCSession.default.sendMessage(["refresh": true], replyHandler: { reply in
      guard let data = reply["payload"] as? Data else { return }
      Task { @MainActor in self.receive(data) }
    }, errorHandler: { _ in Task { @MainActor in self.message = "Unable to refresh. Open the iPhone app." } })
  }
  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let data = session.receivedApplicationContext["payload"] as? Data { Task { @MainActor in self.receive(data) } }
  }
  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let data = applicationContext["payload"] as? Data else { return }
    Task { @MainActor in self.receive(data) }
  }
}
@main struct CrewClockWatchApp: App {
  @StateObject private var model = CrewWatchModel()
  var body: some Scene { WindowGroup { TimelineView(.periodic(from: .now, by: 30)) { context in
    ScrollView { VStack(alignment: .leading, spacing: 8) {
      Label("CrewClock", systemImage: "alarm.fill").foregroundStyle(.blue)
      if model.payload.allowed, let next = model.payload.alarms.filter({ $0.date > context.date }).min(by: { $0.at < $1.at }) {
        Text(next.clockText).font(.largeTitle.bold()).environment(\.timeZone, TimeZone(identifier: next.zone) ?? TimeZone(secondsFromGMT: 0)!)
        Text(next.label).font(.headline)
        Text(next.dayText + " · " + next.zone).font(.caption2).foregroundStyle(.secondary)
        Text(model.payload.flight).font(.caption).lineLimit(2)
      } else { Text(model.payload.allowed ? "No upcoming reservation" : "Check alarm permission on iPhone") }
      if !model.message.isEmpty { Text(model.message).font(.caption2).foregroundStyle(.secondary) }
      if model.payload.updatedAt > 0 { Text("Last sync").font(.caption2); Text(Date(timeIntervalSince1970: model.payload.updatedAt), style: .relative).font(.caption2).foregroundStyle(.secondary) }
      Button("Refresh") { model.refresh() }
      Text("Alarms are reserved by your iPhone. This screen shows synced information.").font(.caption2).foregroundStyle(.secondary)
    }.padding() }
  } } }
}
