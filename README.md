# CrewClock for iOS

Flight preparation, departure-local reminders, personal alarms and repeating reminders.
Four primary tabs provide direct access to Briefing, Roster, Alarms and Settings.
Alarm status labels reflect operating-system reservations; repeating reminders only
show a next time when iOS reports a reserved alarm.

The app is native SwiftUI in `ios-native/` (iPhone only, iOS 26 or later). It uses
AlarmKit for alarms, WidgetKit and ActivityKit for the widget and Live Activity, and
Vision for roster image and PDF import. There are no third-party dependencies. The
earlier Flutter implementation was removed; it remains in the git history.

## Build

Open `ios-native/CrewClockNative.xcodeproj` and run the `CrewClockNative` scheme on a
device. The project file is generated: after adding or removing source files, run
`ruby ios-native/tools/generate_project.rb` (needs the `xcodeproj` gem). Xcode signing
and a real iPhone are required to test lock-screen alarms. See `ios-native/CLAUDE.md`
for the command-line build.

## Data

Schedules, preferences, preparation lists and document dates are stored locally as JSON
in Application Support. Repeating reminders and alarm reservations are kept in
UserDefaults. Nothing leaves the device.

Calendar import understands dated ICS flights with UTC/TZID/airport time zones. Pasted
text accepts one `YYYY-MM-DD KE955 ICN IST 13:55` departure-local line per flight.
Monthly roster images and PDFs are read on the device. Use manual entry for other
formats. Ambiguous or nonexistent daylight-saving civil times require an explicit UTC
calendar time.

Airport mappings and their MIT license are in `ios-native/CrewClockNative/Resources`;
update them with `ios-native/tools/update_airport_timezones.py` from a pinned
airportsdata CSV and license. `privacy.html` and `support.html` are public App Store
support pages, not bundled app UI.
