# CrewClocks — App Review notes

Version: 1.0.4 (28)

## English — ready to paste into App Review notes

Hello App Review,

I am a pilot and the creator of CrewClocks. I planned this app around the personal preparation and time-zone problems I encounter on international flying duties. This is my own app concept and brand, not an app commissioned by an external client. I have not used a commercial app template or another app's design assets. The app uses Flutter, standard third-party libraries, and an attributed open-source airport time-zone dataset.

Compared with the previously reviewed build 9, build 28 extends the existing roster and alarm functions into a departure-specific personal preparation workflow. The substantive changes are:

1. Added a flight briefing workspace. An imported departure now connects its route, departure-local date/time, home-base date/time, UTC and preparation timeline in one place. A pilot can verify which local calendar day applies before preparing for the flight.
2. Added a persistent preparation record for each departure: custom checklist items, completion timestamps and layover or hotel-pickup notes. Reimporting the same departure retains that record, so updating a roster does not require starting preparation again.
3. Added a briefing PDF through the native iOS share sheet. It combines the selected departure's clocks, preparation timeline, checklist and note into a portable preparation record.
4. Expanded airport time-zone coverage to 7,884 IATA codes and 359 time zones, available offline, and corrected roster-import/time-zone handling. Preparation reminders are anchored to the departure's fixed instant, with daylight-saving and date-line handling. Returning from the US to Korea must not recreate a past departure's alarms. This is a reliability improvement supporting the workflow.
5. Simplified roster presentation: compact date, route and times; preparation alarms with local-time labels; past entries dimmed; and empty alarm cards hidden. This makes the upcoming preparation steps easier to scan.

Roster calendars, time-zone clocks and wake-up alarms already exist in crew apps. The product focus of this revision is the connected preparation record for an individual departure: import roster → verify the departure's date across zones → complete and record personal preparation → use departure-relative reminders → export the same record as a PDF. The distinction we ask you to evaluate is this implemented workflow and its persistent per-departure context. Personal date/time alarms and interval reminders remain supplementary tools.

To review without an airline account or a personal roster:
- On a fresh install, select “Explore flight briefing” to open a clearly labeled fictional departure.
- Compare its departure-local, home-base and UTC clocks and dates.
- Check a preparation item, add a custom item, and enter a hotel-pickup note.
- Select “Save / share briefing PDF” to open the native share sheet.
- Select “Exit demo”. The fictional briefing does not register alarms or replace saved flights.
- For a saved roster workflow, use “Import roster”. “Preview sample roster” also provides fictional roster text for inspection before registration.

No login, airline credentials, organization membership, or purchase is required to use these workflows. I have personally tested the app. CrewClocks is a personal organization tool; its preparation checklist is not an aircraft operating checklist or a regulatory compliance determination.

Please evaluate version 1.0.4, build 28, which includes this preparation workflow and the worldwide airport time-zone database. Thank you for your review.

## 한국어 — 개선 사항과 차별점

저는 국제선 조종사로서 실제 근무 중 겪는 출발 준비와 시차 문제를 해결하기 위해 CrewClocks를 직접 기획했습니다. 기존 심사 빌드 9의 일정·알람 기능을 빌드 28에서 다음과 같이 확장했습니다.

1. **출발편별 준비 화면 추가**: 가져온 로스터의 비행편에 출발지 현지 날짜·시각, 홈베이스 시각, UTC와 준비 타임라인을 연결했습니다. 조종사가 어느 지역의 어느 날짜를 기준으로 준비해야 하는지 한 화면에서 확인할 수 있습니다.
2. **출발편별 준비 기록 추가**: 개인 체크리스트, 완료 시각, 사용자 추가 항목, 스테이·호텔 픽업 메모를 해당 출발편에 저장합니다. 같은 출발편을 다시 가져와도 준비 기록을 유지합니다.
3. **준비 기록 PDF 추가**: 해당 편의 시각 정보, 준비 타임라인, 체크리스트와 메모를 하나의 PDF로 저장·공유할 수 있습니다.
4. **국가 이동 시 날짜·알람 처리 개선**: 공항 시간대 지원을 IATA 코드 7,884개·359개 시간대로 확대했습니다. 출발 시점을 고정하여 서머타임과 날짜 변경선을 반영하고, 미국에서 처리한 지난 알람이 한국 복귀 후 다시 등록되는 문제를 방지하도록 보완했습니다. 이는 차별화 주장의 근거인 새 기능과 구분되는 신뢰성 개선입니다.
5. **준비 목록 가독성 개선**: 날짜·비행편·노선·시각을 간결하게 배치하고 지난 일정만 흐리게 표시하며 빈 알람 카드를 제거했습니다.

기존 승무원 앱에도 로스터·세계 시각·기상 알람 기능은 있습니다. CrewClocks가 이번 수정에서 집중한 차별점은 **한 출발편의 로스터 확인부터 시차 확인, 개인 준비 완료 기록, 준비 알람, PDF 보관까지 연결하는 사용 흐름**입니다. 개별 시계나 알람 자체를 독창적이라고 주장하는 것이 아니라, 출발편마다 유지되는 개인 준비 기록과 이를 활용하는 구체적인 경험을 심사해 주시기 바랍니다.

## Submission record — not part of the text to paste

- This is a draft for App Review notes; it has not been sent to App Review.
- Uploading to TestFlight does not select a build for App Store review or submit a new review.
- Use screenshots and any review video captured from the build selected for review.
- The current automated regression suite has 43 passing tests, including the supplied November ICS roster, non-hour time-zone offsets, southern-hemisphere DST, half-hour DST transitions, date-line crossings, and past US alarms after returning to Korea.
- Third-party airport data: https://github.com/mborsetti/airportsdata, revision 47ae282a8491758e6dafe28d4139539e561b54d5. The dataset's MIT notice is bundled in the application source.
