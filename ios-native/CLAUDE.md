# CrewClock (SwiftUI 네이티브 앱)

순수 SwiftUI 앱. Flutter 앱(`../lib`, `../ios/Runner`)을 대체한다. 최소 iOS 26.0 (AlarmKit).

- 프로젝트: `CrewClockNative.xcodeproj` · 스킴: `CrewClockNative`
- 타깃: `CrewClockNative`(앱, `com.addvalue.crewclock`), `CrewClockWidgets`(위젯·Live Activity 확장)
- 위젯 소스와 공용 모델은 `../ios/CrewClockWidgets`, `../ios/Shared`를 그대로 참조한다.
- 프로젝트 파일은 `xcodeproj` gem 스크립트로 생성했다(폴더 동기화 그룹 아님). 새 Swift 파일을 추가하면 프로젝트에 파일 참조를 추가해야 한다.
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
