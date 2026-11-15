# CrewClock (SwiftUI 네이티브 앱)

순수 SwiftUI 앱. 이전 Flutter 앱은 저장소에서 삭제했다(git 기록에 남아 있음). 최소 iOS 26.0 (AlarmKit).

- 프로젝트: `CrewClockNative.xcodeproj` · 스킴: `CrewClockNative`
- 타깃: `CrewClockNative`(앱, `com.addvalue.crewclock`), `CrewClockWidgets`(위젯·Live Activity 확장)
- 위젯 소스는 `CrewClockWidgets/`, 앱·위젯 공용 모델은 `Shared/`에 있다. `CrewClockWatch/`는 아직 타깃에 넣지 않은 Watch 소스다.
- 프로젝트 파일은 `tools/generate_project.rb`로 생성한다(폴더 동기화 그룹 아님). 새 Swift 파일을 추가하면 `ruby tools/generate_project.rb`를 다시 실행한다.
- 이 Mac(macOS 15)에서는 iOS 26 시뮬레이터가 동작하지 않는다. 실제 기기로 확인한다.

```bash
xcodebuild -project CrewClockNative.xcodeproj -scheme CrewClockNative \
  -destination 'generic/platform=iOS' -derivedDataPath "$TMPDIR/dd2" \
  -allowProvisioningUpdates -quiet build > "$TMPDIR/nd.log" 2>&1 \
  && echo "BUILD OK" || grep -E "error:" "$TMPDIR/nd.log" | sort -u | head -20
```

기기 설치는 `xcrun devicectl device install app`을 쓴다(기존 앱을 지우지 않는다).

## 구조

- `Models.swift` 데이터 모델·포맷터 · `Store.swift` 상태·저장·로직(`AppStore`)
- `RosterParser.swift` ICS·월간 로스터·텍스트 파서 · `ImportFlow.swift` 가져오기 흐름·OCR
- `AlarmEngine.swift` AlarmKit 예약·반복 리마인더·위젯/Live Activity 게시
- 화면: `BriefingView`, `RosterView`, `AlarmsView`, `SettingsView`, 편집 시트는 `Components.swift`

## 규칙

- iPhone 전용, 서드파티 의존성 없음, 모든 데이터는 기기 안에만 저장한다(JSON은 Application Support, 반복 리마인더·알람 예약은 UserDefaults). 외부 API·서버·분석 SDK를 추가하지 않는다.
- 알람 상태 표시는 OS 예약 결과를 따른다. 반복 리마인더는 iOS가 예약을 보고할 때만 다음 시각을 보여 준다.
- 서머타임 때문에 모호하거나 존재하지 않는 현지 시각은 임의로 보정하지 않고 UTC 시각을 명시하게 한다.
- 공항 시간대 데이터는 `Resources`에 있고 `tools/update_airport_timezones.py`로만 갱신한다(MIT 라이선스 파일 유지).
- 상위 `AGENTS.md`는 다른 도구용이다. 이 파일과 `/Volumes/Data/Project/CLAUDE.md`가 우선한다.

## 현재 상태

- App Store 마케팅 버전 1.0.6, TestFlight는 build40까지 올렸다(`../app-store/`).
- `CrewClockWatch/`는 아직 앱 타깃에 연결하지 않았다. 워치 앱은 이 Mac의 Xcode가 27.3 기기를 지원하지 않아 TestFlight로만 확인할 수 있다.
- 다음 할 일: (작업을 시작할 때 여기에 한 줄로 적는다)
