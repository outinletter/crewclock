# Native flight briefing — local iOS validation

The first tab now renders flight preparation with Flutter widgets: flight selection,
departure countdown, departure-airport/home-base/UTC clocks, next preparation,
reservation statuses, personal checklist, saved pickup notes and PDF sharing.
Roster import and alarm configuration remain in the existing WebView. Shared roster,
time-zone and preparation storage logic is reused; this is a hybrid application.
The duplicate briefing is hidden inside the native shell. Android project files,
Android-only Dart code and direct dependencies, duplicate web assets and PWA assets
were removed from the iOS-only project. Plugins use CocoaPods consistently;
Swift Package Manager is disabled in the project configuration.
Existing preparation records and home-base settings are reused.

Reviewer walkthrough:
1. Launch into Next flight. With no roster, choose Explore flight briefing.
2. Inspect the clearly marked fictional demo; it never schedules alarms.
3. Exit demo, choose Import roster, then Preview sample roster and confirm registration.
4. Return to Next flight. Choose a flight; compare airport, home-base and UTC dates.
5. Check a preparation item, save a pickup note, and share the briefing PDF.
6. Choose Review flight alarms to open the selected flight in Roster & alarms.

Privacy: no photo-library access is requested. Schedule-image text is copied by the
user with Photos Live Text and pasted into the app. The unused photo permission
purpose string was removed. Alarm permission remains contextual to scheduling.

Validation: automated widget/bridge checks cover startup readiness, time-zone
presentation, flight selection and alarm navigation; JavaScript contract checks cover
UTC date rollover, checklist/note persistence and stale-flight protection.
Pending manual release checks: lock-screen alarm sound, Stop/Snooze/rearm, permission
denial, reservation capacity, VoiceOver, iPad layout and real crew TestFlight feedback.
No beta feedback or full device acceptance testing is claimed. No App Store submission
is made by this change. Native presentation alone does not guarantee 4.3(b) acceptance.
