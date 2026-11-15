# CrewClock 1.0.6 (40) — TestFlight candidate

## Included
- October/November calendar image OCR using per-cell enlargement, pasted calendar text normalization and chronological cell matching; PDF monthly calendars (1–12 full-calendar pages, one month per import); ICS import.
- Preview new/changed/unchanged flights and previous/new departure and arrival dates/times before confirming.
- Separate off/leave, reserve, layover and training entries; connected pairing sectors with local departure/arrival timestamps and scheduled ground gaps. Ground gaps exclude duty/reporting and are not an FDP/legal-rest assessment.
- Flight preparation fixed to departure-airport time. Global UTC(Z)/Local(L) display does not change alarm instants.
- Personal home-time/device-local policy and destination wake-up selection. Device-local fixed-date reservations recalculate when CrewClock resumes after a time-zone change; open after arrival to confirm. No claim of terminated-app time-zone rescheduling.
- One-off duty-handover alarms after H hours/M minutes, 20/40/90-minute nap alarms, existing repeating reminders with countdown bars.
- Optional +2/+5/+10-minute backup alarms, off by default. Stop cancels associated system backup. Extra reservations consume available alarm capacity.
- Separate AlarmKit/notification permission diagnostics, warning banner and Settings link; opt-in one-minute test alarm and recent 100 Stop records, stored on device. Records begin with this version.
- All 24 hour numbers (1–24) on the dial, earliest listed alarm bold and subsequent hands faint; compact date/time wheels; consistent Add Roster headers, hierarchy, offset notation, duplicate zone-card removal.
- Next-alarm iPhone Home/Lock Screen widget, optional next-alarm Live Activity, Apple Watch companion viewer using WatchConnectivity and cached-sync timestamps, Next Alarm App Shortcut and deep links.
- App/extension privacy manifests and shared App Group for widget snapshots. No server was added.

## Verification
- Original October image: 8 flights, same numbers/routes/dates as both October ICS files. Source times differ in 2 flights vs 202610.ics and 8 flights vs calendar-ical.ics; image times remain unchanged.
- Original November image and rasterized PDF: 6 flights, exact number/route/date/time match with 202611.ics.
- Related parser/domain/UI tests passed, including backup after primary time, display-only UTC switching, pairing, non-flight duties, relative alarms, narrow header/dropdown layout and large text. Static analysis clean.
- Unsigned Debug build of Runner + widget + Watch targets passed. Release archive/upload results recorded separately in work logs.

## Physical checks still required in beta
- Locked iPhone with Silent and each Focus configuration; AlarmKit vs notification permission combinations; actual ringing and Stop/backup cancellation.
- Force-quit/reboot and time-zone travel behavior, notably device-local policy requiring reopening after arrival.
- Real Watch sync, disconnected cached state, widget refresh budgets and Live Activity authorization/staleness. System surfaces show confirmed reservations/snapshots; they do not independently reserve alarms.
- Privacy/manifests/signing and upload validation do not establish App Review acceptance.

## Distribution scope
Upload to TestFlight only. No App Store review submission, external beta review, tester invitations or automatic distribution changes authorized by this request.
