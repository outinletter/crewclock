# CrewClock for iOS

Flight preparation, departure-local reminders, personal alarms and repeating reminders.
Four primary tabs provide direct access to Briefing, Roster, Alarms and Settings.
Preparation presets save automatically and support swipe-to-delete with Undo.
Alarm status labels reflect operating-system reservations; repeating reminders only
show a next time when iOS reports a reserved alarm.
All application screens use Flutter widgets; there is no WebView, JavaScript bridge or
bundled website. iOS uses AlarmKit where authorized/available and notification reminders
otherwise. Calendar/text file selection and PDF sharing use native iOS controllers.

## Build

Run `flutter pub get`, `flutter analyze` and `flutter test`, then
`flutter build ios --release`. iOS plugins use CocoaPods. Xcode signing and a compatible
iOS device are required for lock-screen alarm acceptance tests. No Android target is included.

## Data

Schedules, preferences and preparation records are stored locally in SQLite. Upgrading
from the previous app preserves its alarms table and attempts to read historical local
storage directly for roster/settings/preparation migration without loading a WebView.
Existing WebKit data is left intact. Verify migrated home base, flight times and notes
on a real upgraded device before distribution.

Calendar import understands dated ICS flights with UTC/TZID/airport time zones. Pasted
text accepts one `YYYY-MM-DD KE955 ICN IST 13:55` departure-local line per flight.
Use native manual entry for other roster formats. Ambiguous/nonexistent daylight-saving
civil times require an explicit UTC calendar time.

Airport mappings and their MIT license are in `assets/data`; update them with
`tools/update_airport_timezones.py` from a pinned airportsdata CSV and license.
`privacy.html` and `support.html` are public App Store support pages, not bundled app UI.
