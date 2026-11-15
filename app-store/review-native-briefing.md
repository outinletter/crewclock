# CrewClock 1.0.6 (30) — native iOS conversion

All application screens are Flutter widgets. The WebView dependency, HTML application,
JavaScript bridge, browser tests and web application assets have been removed. The
public privacy/support pages remain hosted for App Store metadata and are not bundled.

CrewClock briefing includes departure/home-base/UTC clocks, countdown, flight selection,
preparation checklist/notes and native PDF sharing. Its reminder list displays the
flight/date header, departure-airport local times and each pre-departure offset.
Swipe horizontally or use the bottom tabs to navigate to the native Roster & alarms
screen with calendar, native calendar/text import preview, manual flight editing,
personal and repeating alarms, home-base presets, privacy, sound and appearance settings.
Existing AlarmKit integration is retained; permission-denied and notification-only
states must not be represented as reserved system alarms.

Upgrade handling preserves the SQLite alarms table, creates a native state table and
reads historical local storage directly without a WebView. Historical WebKit files are
left intact. Real-device migration remains a required acceptance check.

Reviewer path: CrewClock briefing → Explore flight briefing (clearly fictional; no alarms)
→ Exit demo → Import roster → Preview sample roster → inspect times → confirm alarms.
Inspect preparation times, check Passport & VISA, save a pickup note, share a PDF,
then swipe to Roster & alarms to edit alarms and inspect reservation statuses.

Before submission verify real-device data migration, locked-device sound, Stop/Snooze
and repeating rearm, denied permissions, reservation capacity, VoiceOver and iPad
layout. Gather actual crew TestFlight feedback and update screenshots from this build.
No feedback, approval guarantee or App Store submission is claimed by this document.

Inline UX: common CrewClock icon/title, visible hours-and-minutes reminder editors,
editable presets directly in Settings, and native date/time pickers.
