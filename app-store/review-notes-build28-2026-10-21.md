# CrewClocks — App Review notes

Version: 1.0.4 (28)

## English — ready to paste into App Review notes

Hello App Review,

I am a pilot and the creator of CrewClocks. I planned this app around the personal preparation and time-zone problems I encounter on international flying duties. This is my own app concept and brand, not an app commissioned by an external client. I have not used a commercial app template or another app's design assets. The app uses Flutter, standard third-party libraries, and an attributed open-source airport time-zone dataset.

CrewClocks connects an imported flight roster to a departure-specific preparation record:

1. Import supported ICS calendars or paste roster text. Each flight connects its route, departure and arrival dates, and preparation reminders.
2. Compare the departure airport's local date/time, home-base date/time, and UTC for the same departure. The bundled database covers 7,884 IATA airport codes and 359 time zones without requiring a network connection. Time-zone conversion accounts for daylight saving and crossings of the international date line.
3. Schedule preparation reminders relative to the departure's fixed instant. Traveling to a different time zone does not turn that departure into a new event. Completed or past alarms must not be re-registered because the user returns to another country.
4. Keep a personal checklist for each departure, including completion timestamps, custom items, and layover or hotel-pickup notes. Reimporting the same departure preserves its preparation record.
5. Export that departure's clocks, preparation timeline, checklist, and note as a PDF through the native iOS share sheet.

The intended use is a single personal workflow: roster → time-zone check → departure preparation → reminders → a portable preparation record. Personal date/time alarms and interval reminders are supplementary tools.

To review without an airline account or a personal roster:
- On a fresh install, select “Explore flight briefing” to open a clearly labeled fictional departure.
- Compare its departure-local, home-base and UTC clocks and dates.
- Check a preparation item, add a custom item, and enter a hotel-pickup note.
- Select “Save / share briefing PDF” to open the native share sheet.
- Select “Exit demo”. The fictional briefing does not register alarms or replace saved flights.
- For a saved roster workflow, use “Import roster”. “Preview sample roster” also provides fictional roster text for inspection before registration.

No login, airline credentials, organization membership, or purchase is required to use these workflows. I have personally tested the app. CrewClocks is a personal organization tool; its preparation checklist is not an aircraft operating checklist or a regulatory compliance determination.

Please evaluate version 1.0.4, build 28, which includes this preparation workflow and the worldwide airport time-zone database. Thank you for your review.

## 한국어 요약

저는 조종사이며, 국제선 근무 중 직접 겪는 시차와 출발 준비 문제를 해결하기 위해 CrewClocks를 기획했습니다. 외부 고객에게 의뢰받아 만든 앱이 아니며, 상용 앱 템플릿이나 다른 앱의 디자인 자산을 사용하지 않았습니다. Flutter, 표준 라이브러리, 출처를 명시한 공항 시간대 데이터를 사용합니다.

앱의 중심은 로스터를 가져와 공항 현지 날짜·홈베이스 시각·UTC를 확인하고, 해당 출발편의 준비 알람과 체크리스트·메모를 연결한 뒤 PDF로 보관하는 흐름입니다. 출발편마다 개인 준비 기록이 유지되며, 국가 이동으로 휴대폰 시간대가 달라져도 알람의 실제 시점은 바뀌지 않습니다.

전 세계 IATA 공항 7,884개와 359개 시간대를 오프라인으로 조회하며, 서머타임과 날짜 변경선을 반영합니다. 이 기능들은 조종사의 개인 출발 준비라는 목적 아래 연결되어 있습니다.

## Submission record — not part of the text to paste

- This is a draft for App Review notes; it has not been sent to App Review.
- Uploading to TestFlight does not select a build for App Store review or submit a new review.
- Use screenshots and any review video captured from the build selected for review.
- The current automated regression suite has 43 passing tests, including the supplied November ICS roster, non-hour time-zone offsets, southern-hemisphere DST, half-hour DST transitions, date-line crossings, and past US alarms after returning to Korea.
- Third-party airport data: https://github.com/mborsetti/airportsdata, revision 47ae282a8491758e6dafe28d4139539e561b54d5. The dataset's MIT notice is bundled in the application source.
