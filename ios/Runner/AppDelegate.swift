import Flutter
import UIKit
import UserNotifications
import AlarmKit
import AppIntents
import ActivityKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import SQLite3

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var rosterImportResult: FlutterResult?
  private var soundPreview: AVAudioPlayer?
  private var alarmDismissObserver: NSObjectProtocol?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "crewclock/native_alarm",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    alarmDismissObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("crewclock.alarmDismissed"), object: nil, queue: .main
    ) { _ in channel.invokeMethod("alarmDismissed", arguments: nil) }
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        do {
          switch call.method {
          case "pickRosterFile":
            self?.pickRosterFile(result)
          case "readLegacyData":
            result(self?.readLegacyData() ?? [:])
          case "readIntervalAlarms":
            result(UserDefaults.standard.array(forKey: "crewclock.intervals") ?? [])
          case "shareDutyBriefing":
            guard let owner = self else { throw NSError(domain: "CrewClock", code: 3) }
            try owner.shareDutyBriefing(call.arguments as? [String: Any] ?? [:])
            result(nil)
          case "syncIntervalAlarms":
            let args = call.arguments as? [String: Any] ?? [:]
            result(try await CrewIntervalReminders.sync(args["records"] as? [[String: Any]] ?? [],
              requestPermission: args["requestPermission"] as? Bool == true))
          case "getAlarmPrivacy":
            result(UserDefaults.standard.bool(forKey: "crewclock.privateLabels"))
          case "setAlarmPrivacy":
            UserDefaults.standard.set(call.arguments as? Bool == true, forKey: "crewclock.privateLabels")
            result(nil)
          case "getAlarmStatus":
            result(try await self?.alarmStatus(call.arguments as? [[String: Any]] ?? []) ?? [:])
          case "getAvailableNotificationSlots":
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            result(max(0, 64 - pending.count))
          case "requestAlarmPermission":
            guard #available(iOS 26.0, *) else { result(false); return }
            let manager = AlarmManager.shared
            if manager.authorizationState == .notDetermined {
              _ = try await manager.requestAuthorization()
            }
            result(manager.authorizationState == .authorized)
          case "scheduleAlarms":
            let args = call.arguments as? [String: Any] ?? [:]
            let records = args["records"] as? [[String: Any]] ?? []
            if records.isEmpty {
              let center = UNUserNotificationCenter.current()
              let pending = await center.pendingNotificationRequests()
              center.removePendingNotificationRequests(withIdentifiers: pending.filter {
                !$0.identifier.hasPrefix("crewclock.interval.") }.map { $0.identifier })
              center.removeAllDeliveredNotifications()
              if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
                try await CrewSystemAlarms.sync([])
              }
              result(false); return
            }
            guard #available(iOS 26.0, *) else { result(false); return }
            let manager = AlarmManager.shared
            if args["requestPermission"] as? Bool == true,
               manager.authorizationState == .notDetermined {
              _ = try await manager.requestAuthorization()
            }
            guard manager.authorizationState == .authorized else {
              if args["requestPermission"] as? Bool == true {
                throw NSError(domain: "CrewClock", code: 1, userInfo:
                  [NSLocalizedDescriptionKey: "Allow CrewClock alarms in Settings > Apps > CrewClock."])
              }
              result(false); return
            }
            try await CrewSystemAlarms.sync(records)
            result(true)
          case "cancelPending":
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            UNUserNotificationCenter.current().removePendingNotificationRequests(
              withIdentifiers: pending.filter { Int($0.identifier) != nil }.map { $0.identifier })
            result(nil)
          case "getAlarmSound":
            result(UserDefaults.standard.string(forKey: "crewclock.sound"))
          case "getQueuedAlarmCount":
            result(UserDefaults.standard.stringArray(forKey: "crewclock.queuedAlarmIDs")?.count ?? 0)
          case "chooseAlarmSound":
            self?.chooseSound(result)
          case "stopAlarm":
            if #available(iOS 26.0, *) {
              for alarm in try AlarmManager.shared.alarms where alarm.state == .alerting {
                let intervals = UserDefaults.standard.dictionary(forKey: "crewclock.intervalAlarmIDs") as? [String: String] ?? [:]
                if let source = intervals.first(where: { $0.value == alarm.id.uuidString })?.key {
                  try await CrewIntervalReminders.advance(sourceID: source, alarmID: alarm.id.uuidString)
                } else {
                  try CrewSystemAlarms.dismiss(alarm.id)
                }
              }
            }
            result(nil)
          case "getDismissedAlarmIds":
            result(UserDefaults.standard.stringArray(forKey: "crewclock.dismissed") ?? [])
          case "acknowledgeDismissals":
            let acknowledged = Set(call.arguments as? [String] ?? [])
            let remaining = (UserDefaults.standard.stringArray(forKey: "crewclock.dismissed") ?? [])
              .filter { !acknowledged.contains($0) }
            UserDefaults.standard.set(remaining, forKey: "crewclock.dismissed")
            result(nil)
          default: result(FlutterMethodNotImplemented)
          }
        } catch {
          result(FlutterError(code: "ALARM_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    guard response.actionIdentifier == "crewclock.stop" else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
      return
    }
    let info = response.notification.request.content.userInfo
    if let source = (info["crewclockSourceID"] ?? info["payload"]) as? String {
      if #available(iOS 26.0, *),
        let mapping = UserDefaults.standard.dictionary(forKey: "crewclock.alarmIDs") as? [String: String],
        let raw = mapping[source], let uuid = UUID(uuidString: raw) {
        do { try CrewSystemAlarms.dismiss(uuid) }
        catch { NSLog("[CrewClock] Stop alarm failed: %@", error.localizedDescription) }
      } else {
        recordAlarmDismissal(source)
      }
    }
    let ids = [response.notification.request.identifier]
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
    completionHandler()
  }

  @MainActor private func pickRosterFile(_ result: @escaping FlutterResult) {
    guard rosterImportResult == nil, let root = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "IMPORT_BUSY", message: "Close the current picker and try again.", details: nil)); return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes:
      [UTType(filenameExtension: "ics") ?? .plainText, UTType(filenameExtension: "ical") ?? .plainText, .plainText], asCopy: true)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    rosterImportResult = result
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    rosterImportResult?(nil); rosterImportResult = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let callback = rosterImportResult; rosterImportResult = nil
    guard let url = urls.first else { callback?(nil); return }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 5_000_000 else { throw NSError(domain: "CrewClock", code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Choose a roster smaller than 5 MB."]) }
      let data = try Data(contentsOf: url)
      guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
        throw NSError(domain: "CrewClock", code: 4, userInfo: [NSLocalizedDescriptionKey: "Use a UTF-8 calendar or text file."])
      }
      callback?(["name": url.lastPathComponent, "text": text])
    } catch { callback?(FlutterError(code: "IMPORT_FAILED", message: error.localizedDescription, details: nil)) }
  }

  // Read only this application's historical WebKit SQLite storage; no WebView is loaded.
  private func readLegacyData() -> [String: String] {
    var values: [String: String] = [:]
    let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    let root = library.appendingPathComponent("WebKit")
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return values }
    for case let file as URL in files {
      let name = file.lastPathComponent.lowercased()
      guard name.hasSuffix(".localstorage") || name == "localstorage.sqlite3" else { continue }
      var db: OpaquePointer?
      guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        if db != nil { sqlite3_close(db) }; continue
      }
      defer { sqlite3_close(db) }
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, "SELECT key, value FROM ItemTable", -1, &statement, nil) == SQLITE_OK else { continue }
      defer { sqlite3_finalize(statement) }
      func string(_ column: Int32) -> String? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\0") { return utf8 }
        return String(data: data, encoding: .utf16LittleEndian)
      }
      while sqlite3_step(statement) == SQLITE_ROW {
        if let key = string(0), key.hasPrefix("crewclock_"), let value = string(1) { values[key] = value }
      }
    }
    return values
  }

  @MainActor private func shareDutyBriefing(_ args: [String: Any]) throws {
    guard let lines = args["lines"] as? [String], lines.count <= 50,
      lines.allSatisfy({ $0.count <= 2000 }),
      let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      throw NSError(domain: "CrewClock", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to export flight preparation."])
    }
    let title = String((args["title"] as? String ?? "CrewClock Flight Preparation").prefix(100))
    let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CrewClock-\(UUID().uuidString).pdf")
    try renderer.writePDF(to: url) { context in
      context.beginPage()
      var y: CGFloat = 40
      let paragraphs = [title] + lines
      for (index, text) in paragraphs.enumerated() {
        let attributes: [NSAttributedString.Key: Any] = [.font: index == 0 ? UIFont.boldSystemFont(ofSize: 20) : UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
        let height = ceil((text as NSString).boundingRect(with: CGSize(width: 515, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height) + 8
        if y + height > 802 { context.beginPage(); y = 40 }
        (text as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: height), withAttributes: attributes)
        y += height + 6
      }
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = presenter.view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
    presenter.present(sheet, animated: true)
  }

  @MainActor private func chooseSound(_ result: @escaping FlutterResult) {
    guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "NO_WINDOW", message: "Please try again.", details: nil)); return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker = UIAlertController(title: "Alarm Sound", message: nil, preferredStyle: .actionSheet)
    for (label, name) in [("System Default", ""), ("CrewClock Beep", "crewclock_beep.caf")] {
      picker.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
        do {
          if !name.isEmpty {
            let url = try Self.makeSound(name)
            self?.soundPreview = try AVAudioPlayer(contentsOf: url)
            self?.soundPreview?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.soundPreview?.stop() }
          }
          UserDefaults.standard.set(name.isEmpty ? nil : name, forKey: "crewclock.sound")
          result(label)
        } catch {
          result(FlutterError(code: "SOUND_ERROR", message: error.localizedDescription, details: nil))
        }
      })
    }
    picker.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in result(nil) })
    picker.popoverPresentationController?.sourceView = presenter.view
    picker.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX,
      y: presenter.view.bounds.midY, width: 1, height: 1)
    presenter.present(picker, animated: true)
  }

  private static func makeSound(_ name: String) throws -> URL {
    let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Sounds", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: url.path) { return url }
    let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
    let count = AVAudioFrameCount(22050 * 28)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
    buffer.frameLength = count
    for i in 0..<Int(count) {
      let t = Double(i) / 22050
      let phase = t.truncatingRemainder(dividingBy: 1)
      let envelope = max(0, min(1, min(phase / 0.02, (0.7 - phase) / 0.02)))
      buffer.floatChannelData![0][i] = Float(0.3 * envelope * sin(2 * .pi * 880 * t))
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }
}

extension AppDelegate {
  @MainActor
  func alarmStatus(_ records: [[String: Any]]) async throws -> [String: [String: Any]] {
    let defaults = UserDefaults.standard
    let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
    var status: [String: [String: Any]] = [:]
    if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
      let live = try AlarmManager.shared.alarms
      for key in ["crewclock.alarmIDs", "crewclock.intervalAlarmIDs"] {
        for (source, raw) in defaults.dictionary(forKey: key) as? [String: String] ?? [:] {
          var entry: [String: Any] = ["state": "waiting"]
          if let alarm = live.first(where: { $0.id.uuidString == raw }) {
            entry["state"] = alarm.state == .alerting ? "alerting" : "scheduled"
            if case .fixed(let date) = alarm.schedule { entry["next"] = date.timeIntervalSince1970 * 1000 }
          }
          status[source] = entry
        }
      }
      for source in defaults.stringArray(forKey: "crewclock.queuedAlarmIDs") ?? [] { status[source] = ["state": "waiting"] }
    }
    let sources = records.compactMap { $0["id"] as? String } + ((defaults.array(forKey: "crewclock.intervals") as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
    for source in sources {
      if ["scheduled", "alerting"].contains(status[source]?["state"] as? String ?? "") { continue }
      if pending.contains(where: { $0.content.userInfo["payload"] as? String == source }) { status[source] = ["state": "notification"] }
      else if status[source] == nil { status[source] = ["state": "permission"] }
    }
    return status
  }
}

enum CrewIntervalReminders {
  static let prefix = "crewclock.interval."
  static func sync(_ records: [[String: Any]], requestPermission: Bool) async throws -> [[String: Any]] {
    func failure(_ message: String) -> NSError {
      NSError(domain: "CrewClock", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
    guard records.count <= 16 else { throw failure("Up to 16 repeating reminders are allowed.") }
    var ids = Set<String>()
    for record in records {
      guard let id = record["id"] as? String, id.range(of: "^interval_[0-9]+$", options: .regularExpression) != nil,
        ids.insert(id).inserted, let label = record["label"] as? String,
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.count <= 100,
        let minutes = record["minutes"] as? NSNumber,
        minutes.doubleValue.rounded() == minutes.doubleValue, (1...10080).contains(minutes.intValue),
        record["enabled"] is Bool else { throw failure("Invalid repeating reminder.") }
    }
    guard #available(iOS 26.0, *) else {
      throw failure("Lock-screen interval alarms require iOS 26 or later.")
    }
    let manager = AlarmManager.shared
    if records.contains(where: { $0["enabled"] as? Bool == true }) {
      if requestPermission && manager.authorizationState == .notDetermined {
        _ = try await manager.requestAuthorization()
      }
      guard manager.authorizationState == .authorized else {
        throw failure("Allow CrewClock alarms in Settings > Apps > CrewClock.")
      }
    }
    let defaults = UserDefaults.standard
    let privacy = defaults.bool(forKey: "crewclock.privateLabels")
    let previousPrivacy = defaults.bool(forKey: "crewclock.intervalPrivacy")
    let previous = defaults.array(forKey: "crewclock.intervals") as? [[String: Any]] ?? []
    var mapping = defaults.dictionary(forKey: "crewclock.intervalAlarmIDs") as? [String: String] ?? [:]
    let live = try manager.alarms
    var saved = records
    var added: [UUID] = []
    var replaced: [String: String] = [:]
    do {
      for index in saved.indices where saved[index]["enabled"] as? Bool == true {
        let record = saved[index], id = record["id"] as! String
        let old = previous.first { $0["id"] as? String == id }
        let unchanged = privacy == previousPrivacy && old?["enabled"] as? Bool == true && old?["minutes"] as? Int == record["minutes"] as? Int && old?["label"] as? String == record["label"] as? String
        if unchanged, let raw = mapping[id], let uuid = UUID(uuidString: raw), live.contains(where: { $0.id == uuid }) {
          saved[index]["anchor"] = old?["anchor"]
          continue
        }
        let uuid = UUID()
        let now = Date().timeIntervalSince1970 * 1000
        saved[index]["anchor"] = unchanged ? (old?["anchor"] as? Double ?? now) : now
        let date = nextDate(saved[index])
        _ = try await manager.schedule(id: uuid, configuration: configuration(record: saved[index], uuid: uuid, date: date))
        added.append(uuid)
        if let raw = mapping[id] { replaced[id] = raw }
        mapping[id] = uuid.uuidString
      }
    } catch {
      for uuid in added { try? manager.cancel(id: uuid) }
      throw error
    }
    let wanted = Set(saved.filter { $0["enabled"] as? Bool == true }.compactMap { $0["id"] as? String })
    for (id, raw) in mapping where !wanted.contains(id) {
      if let uuid = UUID(uuidString: raw), live.contains(where: { $0.id == uuid }) { try manager.cancel(id: uuid) }
      mapping.removeValue(forKey: id)
    }
    for raw in replaced.values {
      if let uuid = UUID(uuidString: raw), live.contains(where: { $0.id == uuid }) { try manager.cancel(id: uuid) }
    }
    defaults.set(mapping, forKey: "crewclock.intervalAlarmIDs")
    defaults.set(saved, forKey: "crewclock.intervals")
    defaults.set(privacy, forKey: "crewclock.intervalPrivacy")
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier })
    return saved
  }

  static func nextDate(_ record: [String: Any]) -> Date {
    let step = Double(record["minutes"] as! Int) * 60
    let anchor = (record["anchor"] as? Double ?? Date().timeIntervalSince1970 * 1000) / 1000
    let now = Date().timeIntervalSince1970
    return Date(timeIntervalSince1970: anchor + (floor(max(0, now - anchor) / step) + 1) * step)
  }

  @available(iOS 26.0, *)
  static func configuration(record: [String: Any], uuid: UUID, date: Date)
    -> AlarmManager.AlarmConfiguration<CrewAlarmMetadata> {
    let label = UserDefaults.standard.bool(forKey: "crewclock.privateLabels") ? "CrewClock reminder" : record["label"] as! String
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = .init(title: LocalizedStringResource(stringLiteral: label))
    } else {
      alert = .init(title: LocalizedStringResource(stringLiteral: label),
        stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
    }
    let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
      metadata: CrewAlarmMetadata(sourceID: record["id"] as! String), tintColor: Color.blue)
    let sound: AlertConfiguration.AlertSound = UserDefaults.standard.string(forKey: "crewclock.sound").map { .named($0) } ?? .default
    return .alarm(schedule: .fixed(date), attributes: attributes,
      stopIntent: CrewIntervalStopIntent(sourceID: record["id"] as! String, alarmID: uuid.uuidString), sound: sound)
  }

  @available(iOS 26.0, *)
  static func advance(sourceID: String, alarmID: String) async throws {
    let defaults = UserDefaults.standard
    let mapping = defaults.dictionary(forKey: "crewclock.intervalAlarmIDs") as? [String: String] ?? [:]
    guard mapping[sourceID] == alarmID, let uuid = UUID(uuidString: alarmID) else { return }
    let records = defaults.array(forKey: "crewclock.intervals") as? [[String: Any]] ?? []
    guard let record = records.first(where: { $0["id"] as? String == sourceID && $0["enabled"] as? Bool == true }) else { return }
    if try AlarmManager.shared.alarms.contains(where: { $0.id == uuid }) { try AlarmManager.shared.stop(id: uuid) }
    _ = try await AlarmManager.shared.schedule(id: uuid, configuration: configuration(record: record, uuid: uuid, date: nextDate(record)))
  }

}

@available(iOS 26.0, *)
struct CrewAlarmMetadata: AlarmMetadata { var sourceID: String }

@available(iOS 26.0, *)
enum CrewSystemAlarms {
  static let defaults = UserDefaults.standard
  static func sync(_ records: [[String: Any]], retryLimit: Bool = true) async throws {
    var mapping = defaults.dictionary(forKey: "crewclock.alarmIDs") as? [String: String] ?? [:]
    var signatures = defaults.dictionary(forKey: "crewclock.alarmSignatures") as? [String: String] ?? [:]
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let live = try AlarmManager.shared.alarms
    if records.isEmpty {
      for alarm in live where mapping.values.contains(alarm.id.uuidString) { try AlarmManager.shared.cancel(id: alarm.id) }
      for key in ["crewclock.alarmIDs", "crewclock.alarmSignatures", "crewclock.queuedAlarmIDs", "crewclock.dismissed", "crewclock.alarmCapacity"] {
        defaults.removeObject(forKey: key)
      }
      return
    }
    let now = Date()
    let eligible = records.filter { record in
      guard record["id"] is String,
        (record["armed"] as? NSNumber)?.boolValue == true,
        (record["dism"] as? NSNumber)?.boolValue != true,
        (record["missed"] as? NSNumber)?.boolValue != true,
        let raw = record["time"] as? String, let date = formatter.date(from: raw)
      else { return false }
      return date > now
    }.sorted {
      let first = formatter.date(from: $0["time"] as! String)!
      let second = formatter.date(from: $1["time"] as! String)!
      return first == second ? ($0["id"] as! String) < ($1["id"] as! String) : first < second
    }
    let limit = defaults.object(forKey: "crewclock.alarmCapacity") as? Int
    let protectedCount = live.filter { $0.state != .scheduled }.count
    let selected = limit.map { Array(eligible.prefix(max(0, $0 - protectedCount))) } ?? eligible
    let selectedIDs = Set(selected.compactMap { $0["id"] as? String })
    let recordIDs = Set(records.compactMap { $0["id"] as? String })
    for (source, value) in mapping {
      guard let uuid = UUID(uuidString: value) else { continue }
      let record = records.first { $0["id"] as? String == source }
      let scheduled = live.first { $0.id == uuid }?.state == .scheduled
      if !recordIDs.contains(source) || (record?["dism"] as? NSNumber)?.boolValue == true || (record?["armed"] as? NSNumber)?.boolValue == false || (scheduled && !selectedIDs.contains(source)) {
        if live.contains(where: { $0.id == uuid }) { try AlarmManager.shared.cancel(id: uuid) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm." + value])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["alarm." + value])
        mapping.removeValue(forKey: source); signatures.removeValue(forKey: source)
      }
    }
    defaults.set(mapping, forKey: "crewclock.alarmIDs")
    defaults.set(signatures, forKey: "crewclock.alarmSignatures")
    for record in selected {
      guard let source = record["id"] as? String,
        (record["armed"] as? NSNumber)?.boolValue == true, (record["dism"] as? NSNumber)?.boolValue != true,
        (record["missed"] as? NSNumber)?.boolValue != true, let raw = record["time"] as? String,
        let date = formatter.date(from: raw), date > Date() else { continue }
      let label = defaults.bool(forKey: "crewclock.privateLabels") ? "CrewClock reminder" : (record["lbl"] as? String ?? "CrewClock Alarm")
      let signature = raw + label + (defaults.string(forKey: "crewclock.sound") ?? "default")
      let uuid = mapping[source].flatMap(UUID.init(uuidString:)) ?? UUID()
      if live.contains(where: { $0.id == uuid && $0.state != .scheduled }) { continue }
      if signatures[source] == signature && live.contains(where: { $0.id == uuid }) { continue }
      let configuration = config(source: source, label: label, date: date, uuid: uuid)
      // Updating a scheduled alarm must not require an additional slot at capacity.
      if live.contains(where: { $0.id == uuid }) {
        try AlarmManager.shared.cancel(id: uuid)
        signatures.removeValue(forKey: source)
        defaults.set(signatures, forKey: "crewclock.alarmSignatures")
      }
      do {
        _ = try await AlarmManager.shared.schedule(id: uuid, configuration: configuration)
      } catch {
        let nativeError = error as NSError
        let limitError = AlarmManager.AlarmError.maximumLimitReached as NSError
        guard error as? AlarmManager.AlarmError == .maximumLimitReached ||
          (nativeError.domain == limitError.domain && nativeError.code == limitError.code) else {
          throw error
        }
        let capacity = try AlarmManager.shared.alarms.count
        defaults.set(capacity, forKey: "crewclock.alarmCapacity")
        if retryLimit && capacity > 0 {
          try await sync(records, retryLimit: false)
          return
        }
        break
      }
      mapping[source] = uuid.uuidString; signatures[source] = signature
      defaults.set(mapping, forKey: "crewclock.alarmIDs")
      defaults.set(signatures, forKey: "crewclock.alarmSignatures")
      let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
      if pending.count < 64 || pending.contains(where: { $0.identifier == "alarm." + uuid.uuidString }) {
        let content = UNMutableNotificationContent()
        content.title = label
        content.categoryIdentifier = "crewclock_alarm"
        content.userInfo = ["crewclockSourceID": source]
        content.body = "CrewClock alarm. Open CrewClock to view your schedule."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        do {
          try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "alarm." + uuid.uuidString, content: content, trigger: trigger))
        } catch {
          NSLog("[CrewClock] Reminder notification failed: %@", error.localizedDescription)
        }
      }
    }
    defaults.set(mapping, forKey: "crewclock.alarmIDs")
    defaults.set(signatures, forKey: "crewclock.alarmSignatures")
    let registered = Set(try AlarmManager.shared.alarms.map { $0.id.uuidString })
    let queued = eligible.compactMap { record -> String? in
      let source = record["id"] as! String
      return mapping[source].map { registered.contains($0) } == true ? nil : source
    }
    defaults.set(queued, forKey: "crewclock.queuedAlarmIDs")
  }

  static func config(source: String, label: String, date: Date, uuid: UUID)
    -> AlarmManager.AlarmConfiguration<CrewAlarmMetadata> {
    let snooze = AlarmButton(text: "Snooze 5 min", textColor: .white, systemImageName: "zzz")
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = .init(title: LocalizedStringResource(stringLiteral: label),
        secondaryButton: snooze, secondaryButtonBehavior: .custom)
    } else {
      alert = .init(title: LocalizedStringResource(stringLiteral: label),
        stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
        secondaryButton: snooze, secondaryButtonBehavior: .custom)
    }
    let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
      metadata: CrewAlarmMetadata(sourceID: source), tintColor: Color.blue)
    let sound: AlertConfiguration.AlertSound = defaults.string(forKey: "crewclock.sound")
      .map { .named($0) } ?? .default
    return .alarm(schedule: .fixed(date), attributes: attributes,
      stopIntent: CrewStopIntent(alarmID: uuid.uuidString),
      secondaryIntent: CrewSnoozeIntent(alarmID: uuid.uuidString, sourceID: source, label: label),
      sound: sound)
  }

  static func dismiss(_ uuid: UUID) throws {
    let notificationIDs = ["alarm." + uuid.uuidString]
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIDs)
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notificationIDs)
    if try AlarmManager.shared.alarms.contains(where: { $0.id == uuid }) {
      try AlarmManager.shared.stop(id: uuid)
    }
    let mapping = defaults.dictionary(forKey: "crewclock.alarmIDs") as? [String: String] ?? [:]
    if let source = mapping.first(where: { $0.value == uuid.uuidString })?.key {
      recordAlarmDismissal(source)
    }
  }
}

private func recordAlarmDismissal(_ source: String) {
  var ids = UserDefaults.standard.stringArray(forKey: "crewclock.dismissed") ?? []
  if !ids.contains(source) { ids.append(source) }
  UserDefaults.standard.set(ids, forKey: "crewclock.dismissed")
  NotificationCenter.default.post(name: Notification.Name("crewclock.alarmDismissed"), object: nil)
}

@available(iOS 26.0, *)
struct CrewStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Stop CrewClock Alarm"
  @Parameter(title: "Alarm ID") var alarmID: String
  init() {}
  init(alarmID: String) { self.alarmID = alarmID }
  func perform() async throws -> some IntentResult {
    if let uuid = UUID(uuidString: alarmID) { try CrewSystemAlarms.dismiss(uuid) }
    return .result()
  }
}

@available(iOS 26.0, *)
struct CrewSnoozeIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Snooze CrewClock Alarm"
  @Parameter(title: "Alarm ID") var alarmID: String
  @Parameter(title: "Source ID") var sourceID: String
  @Parameter(title: "Label") var label: String
  init() {}
  init(alarmID: String, sourceID: String, label: String) {
    self.alarmID = alarmID; self.sourceID = sourceID; self.label = label
  }
  func perform() async throws -> some IntentResult {
    guard let uuid = UUID(uuidString: alarmID) else { return .result() }
    try AlarmManager.shared.stop(id: uuid)
    _ = try await AlarmManager.shared.schedule(id: uuid, configuration:
      CrewSystemAlarms.config(source: sourceID, label: label,
        date: Date().addingTimeInterval(300), uuid: uuid))
    return .result()
  }
}


@available(iOS 26.0, *)
struct CrewIntervalStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Stop and continue interval reminder"
  @Parameter(title: "Source ID") var sourceID: String
  @Parameter(title: "Alarm ID") var alarmID: String
  init() {}
  init(sourceID: String, alarmID: String) { self.sourceID = sourceID; self.alarmID = alarmID }
  func perform() async throws -> some IntentResult {
    try await CrewIntervalReminders.advance(sourceID: sourceID, alarmID: alarmID)
    return .result()
  }
}
