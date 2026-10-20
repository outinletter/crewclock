# CrewClock review revision — 2026-10-20

## Reason for the revision

The submission shown in App Store Connect is 1.0.4 (9), rejected under 4.3.0.
The October 16 message also references 4.2.6 (app generation services).
The latest response does not identify a specific comparison app or disclose a
binary similarity score. We cannot infer which individual component caused it.

Apple evaluates the overall product. Changing colors, names, Bundle IDs or build
metadata alone does not establish a distinct user experience. No approval is
guaranteed. Keep the existing app identity and submit substantive, demonstrable
changes, accurate screenshots, and a concrete reviewer walkthrough.

Sources: https://developer.apple.com/app-store/review/guidelines/#spam and
https://developer.apple.com/app-store/review/guidelines/#minimum-functionality.

## Product direction implemented in build 16

Personal departure preparation for pilots and traveling crew, connecting an
imported roster to airport-local reminders and a persistent preparation record.

- First screen: flight briefing rather than an empty general-purpose calendar.
- The same departure in departure-airport time, home-base time and UTC, with dates.
- Preparation timeline derived from that flight's reminder presets.
- Personal checklist with completion timestamps, custom items and layover notes.
- Records keyed to flight number, departure airport and absolute departure;
  reimporting the same departure retains its preparation record.
- Departure-local flight reminder labels, calendar association and weekdays stay
  fixed after arrival in another time zone. Stored UTC trigger times stay fixed.
- A native iOS PDF renderer and share sheet export the selected flight's clocks,
  timeline, preparation marks and note. Data is shared only when the user chooses
  an activity in the share sheet.
- One-tap fictional briefing demo available from the first screen, with no login,
  no imported roster and no alarm scheduling. Demo edits are not persisted.
- Keep the user's compact interval-reminder form with name and minutes together.

The checklist is personal organization, not an operational aircraft checklist,
fitness-for-duty determination, regulatory rest calculator or airline service.
No new Bundle ID, binary disguising, code obfuscation or fabricated test evidence
is part of this revision. Flutter and the existing web UI remain in use; the
native integration is described accurately rather than claiming a full native
rewrite.

## Proposed App Store metadata

Keep the existing app name/identity. Suggested subtitle (24 characters):

Pilot Roster & Duty Prep

### Description

CrewClock connects your flight roster to personal departure preparation.
Import supported ICS calendars or paste roster text, check departure times
across time zones, and organize the steps before each flight.

FLIGHT BRIEFING
See the selected departure in airport-local time, home-base time and UTC with
the date in each zone. Review its preparation timeline in one place.

DEPARTURE-LOCAL REMINDERS
Build reminders relative to each departure using your preparation offsets.
Flight reminder labels remain tied to the departure airport when you travel.

PERSONAL PREPARATION RECORD
Check off personal preparation items, add your own items and save a layover or
pickup note per departure. Completion marks and notes are stored on your device.
Reimporting the same departure preserves its preparation record.

BRIEFING PDF
Save or share a PDF containing departure clocks, the preparation timeline,
checklist and note through the iOS share sheet.

TRY WITHOUT A ROSTER
Explore a clearly labeled fictional flight briefing from the first screen.
This demo does not register alarms or replace your saved flights.

Also includes personal date/time alarms and interval reminders. Alarm and
notification permissions are required for the corresponding reminders.
Interval notification sounds may be silenced by Silent mode or Focus.

CrewClock is a personal organization tool. Verify your roster and use your
airline's official operational procedures. It is not an airline-operated or
certified flight operations system.

## App Review notes / reply draft

Hello App Review,

I am a pilot and the creator of CrewClock. I designed it for the preparation and
time-zone problems I encounter when traveling for flights. This is my own app
concept and brand, not an external client's template app. I have not used a
commercial app template or copied another app's design assets. The app uses
Flutter and standard third-party libraries; I am not claiming exclusive
ownership of those libraries.

I have revised the product around a flight-specific preparation workflow:
departure-local, home-base and UTC clocks; preparation timelines; per-departure
checklists with completion timestamps; layover notes; and native iOS PDF export.
These changes are available in build 16, rather than the previously reviewed
build 9. Flight reminder labels also retain the departure airport's date and
time when the user arrives in another time zone.

To review without an account or a personal roster:
1. Launch the app and select “Explore flight briefing” on the first screen.
2. Compare the DFW departure, home-base and UTC clocks and their dates.
3. Review the departure preparation timeline.
4. Check a preparation item, add a custom item and enter a pickup note.
5. Select “Save / share briefing PDF” to open the native iOS share sheet.
6. Exit the demo. No fictional alarms or flights have been registered.

For the saved workflow, import a supported roster using “Import roster”. Each
departure has its own preparation record. The fictional demo is intentionally
temporary; its checklist and notes are discarded when it is closed.

No airline account, organization membership, payment or reviewer credentials
are required. The app is available for individual users, not restricted to one
company's employees. The checklist is for personal organization, not an
operational aircraft checklist or regulatory compliance decision.

I have personally tested the app. I am not claiming an external tester count or
external tester feedback. Please let me know if a specific remaining similarity
or workflow requires clarification.

Thank you.

## Submission checks

- Attach the newly verified build, not build 9 or the earlier build 15.
- Replace old screenshots with captures of this exact revised build, including
  the briefing, time-zone comparison and personal preparation workflow.
- Keep screenshots, description, privacy information and reviewer notes aligned
  with the submitted binary. Do not upload browser mockups as device evidence.
- Physically check PDF saving, multi-page output, Korean notes, relaunch
  persistence and notification permissions before submitting. Include iPad
  testing and share-sheet placement if the app supports iPad.
- The automated web regression suite is necessary evidence, but is not proof of
  physical notification delivery, iPad behavior or an App Store approval.
- This document is a local draft, not a message sent to Apple or a resubmission.
