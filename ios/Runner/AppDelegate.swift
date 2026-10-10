import Flutter
import UIKit
import UserNotifications
import AlarmKit
import AppIntents
import ActivityKit
import SwiftUI
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
          case "scheduleAlarms":
            let args = call.arguments as? [String: Any] ?? [:]
            let records = args["records"] as? [[String: Any]] ?? []
            if records.isEmpty {
              let center = UNUserNotificationCenter.current()
              center.removeAllPendingNotificationRequests()
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
                try CrewSystemAlarms.dismiss(alarm.id)
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
      for alarm in live { try AlarmManager.shared.cancel(id: alarm.id) }
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
      let label = record["lbl"] as? String ?? "CrewClock Alarm"
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
      if signatures.count < 64 {
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
