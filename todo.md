# ScheduleDensity 패밀리 — 할 일 목록

iOS 앱(ScheduleDensity)과 macOS 앱(WeekBlocks)을 하나의 Xcode 프로젝트에서
두 개의 타깃으로 관리하는 "같은 패밀리" 구조.

## 완료
- [x] WeekBlocks 소스를 `WeekBlocks/` 폴더로 흡수
- [x] `ScheduleDensityApp.xcodeproj`에 macOS 타깃 `WeekBlocks` 추가
- [x] WeekBlocks 타깃에 macOS 빌드 설정(SDKROOT/배포타깃) 오버라이드
- [x] 두 타깃 모두 빌드 성공 검증 (iOS / macOS)
- [x] 명명 전면 통일: macOS 번들 ID `com.devkoan.ScheduleDensityApp`, 표시이름 `ScheduleDensity`
- [x] WeekBlocks iCloud(CloudKit) 연동: 공유 컨테이너 `iCloud.com.devkoan.ScheduleDensity`
      (entitlements + SwiftData `cloudKitDatabase: .private(...)`, 빌드/서명 검증, 컨테이너 자동 등록됨)
- [x] iOS 기준 디자인 통일 (표시이름 "무지개 공방")
      - 컬러: `Theme.swift` 신설 — iOS laneColors와 동일한 7색 무지개 hex 팔레트 + `Color(hex:)` + 밀도 색 스케일
      - `paletteColor`/`routineColorOptions`를 iOS 시스템 색 hex로 통일, AccentColor = 시스템 블루 #007AFF
      - 톤: 전 UI 반말 → iOS 존댓말로 통일 (ContentView/BlockEditor/ConcretenessChecker/Backlog/Reflection/Routines)
      - UX: 툴바에 설정(gearshape)·더보기(ellipsis.circle: 루틴 추가/샘플/전체 삭제) 추가, `SettingsView` 신설(iOS Form/Section 미러링)

- [x] 고정 루틴 워크플로 강제 (macOS)
      - 고정 루틴 추가 시 주간 그리드에 자동 배치 (`onChange(routines.count)` → 즉시 occurrence 시딩)
      - 고정 루틴 삭제 잠금: RoutineRow 휴지통 → 잠금 아이콘, 편집기 삭제 버튼 숨김 (이름·요일 편집은 가능)
      - 게이트: 고정 루틴이 하나라도 있어야 백로그·계획 블록 추가 가능 (없으면 잠금 + 안내)
      - 레이아웃: 루틴 섹션을 그리드/백로그 위로 이동 (루틴 먼저 → 계획 흐름)
- [x] 요일별 하루 24시간 타임라인 (`DayTimelineView.swift`)
      - 7요일 가로 막대 + 0/6/12/18/24 축, 시간 격자(24칸)
      - 고정 루틴 정확한 시각 배치(자정 넘김 분할), 계획 블록은 시간대 빈 구간 패킹
      - 요일별 "자유 Xh"(초과 시 빨강) 표시
      - 절대 겹침 없음: 통합 그리디 패킹(루틴+계획 모두 통째로, 빈 구간에만 배치, 시각은 근사치)
- [x] 주간 쿼터 자동 계산 표시 (일 평균 + 회당)
      - Routine에 `sessionsPerDay`(하루 횟수) 추가, `dailyQuotaHours` + `formatDuration` 헬퍼
      - scheduleDescription: "주 17.5h · 일 평균 2시간 30분 · 회당 약 50분"
      - 편집기에 하루 횟수 스테퍼 + 실시간 계산 미리보기, 기본 식사 시드 = 3회

- [x] 백로그 주(week) 단위 재구성
      - BacklogItem에 weekStartDate 추가, 메인 백로그는 "이번 주"만 표시
      - "전체 백로그" 시트(AllBacklogView): 주별 그룹, 지난 주 미완료 → "이번 주로 가져오기", 헤더에 이월 개수 배지
      - "할 일 작성" 시트(BacklogComposerView): TODO식 입력(Enter 연속 추가), 행별 카테고리·시간 편집, 카테고리 관리 포함
      - 메인의 인라인 빠른추가 바 제거(동선 단축)

- [x] App Store 심사 Guideline 4(Design) 대응 — 창 닫은 뒤 다시 열기 (macOS)
      - `WeekBlocksApp.swift`: `WindowGroup` → `Window("무지개 공방", id: "main")` 단일 창 씬으로 교체
      - 윈도우 메뉴에 "무지개 공방" 항목이 자동 등록되어 창을 닫아도 메뉴/Dock 클릭으로 재오픈 가능
      - macOS 빌드 검증 완료

- [x] WeekBlocks 지원 페이지 제작 + GitHub Pages 배포
      - `docs/index.html`: 기능/사용법/FAQ/개인정보/문의 (무지개 팔레트·존댓말)
      - Pages 소스 = main `/docs`, URL https://m1zz.github.io/ScheduleDensity/
      - README(main·dev)에 지원 페이지 링크 추가

## 완료 (2026-07-08)
- [x] iOS 앱(ScheduleDensityApp)도 같은 공유 컨테이너로 iCloud 연동
      - entitlements `iCloud.com.devkoan.ScheduleDensity` + Background Modes(Remote notifications)
      - WeekBlocks 모델 6종을 iOS 타깃에 공유 컴파일, `cloudKitDatabase: .private(...)`
      - Event는 별도 로컬 전용 ModelConfiguration으로 유지 (CloudKit 미적용 — 기존 데이터 그대로)
- [x] iOS에 '할 일' 탭 추가 — 간단 Todo(내 할 일: 맥 백로그와 동기화, isCompleted 체크)
      - Event 스토어·WeekBlocksStore 미러와 분리된 별도 컨테이너("WeekBlocksTodos", BacklogItem·BacklogCategory만 CloudKit private)
- [x] 가족 공유 — CloudKit 커스텀 존("FamilyTodos") + 존 전체 CKShare
      - `FamilyShareStore.swift`(공용): 소유자=개인 DB, 참가자=공유 DB, 초대 링크(publicPermission .readWrite)
      - iOS: 할 일 탭 안 '가족' 세그먼트 / macOS: '가족 할 일' 섹션
      - 초대 수락: iOS SceneDelegate·macOS NSApplicationDelegate + `CKSharingSupported`
      - ⚠️ 프로덕션 배포 전 CloudKit Console에서 스키마 deploy 필요 (BacklogItem 새 필드 + FamilyTodo 레코드 타입)

## 정리 필요
- [ ] 기존 독립 프로젝트 `/Users/leeo/Documents/workspace/code/WeekBlocks` 제거 (이 저장소로 흡수 완료 후)
- [ ] (선택) WeekBlocks 내부 타깃/스킴명도 ScheduleDensity 계열로 변경 — Xcode에서 rename 권장(수기 pbxproj 위험)

## iOS 시각화 연동 (WeekBlocks 데이터 → 욕망의 무지개 밀도 뷰)
방향 확정: **같은 iCloud 계정(private DB)** 전제, iOS는 **읽기 전용 소비자**.
WeekBlocks `Routine`/`PlanBlock`을 메모리상 `Event`로 변환해 기존 밀도 파이프라인 재사용.

- [ ] 1. 공유 모델: `WeekBlocks/`의 `Models.swift`·`Routine.swift`·`PlanBlock.swift`(+필요 시 BacklogItem 등)를 iOS 타깃 멤버십에 추가 (복붙 금지, 단일 소스)
      - ⚠️ `Theme.swift`(Rainbow/Color(hex:))도 함께 필요 — iOS에 같은 헬퍼가 있으면 중복 정의 충돌 점검
- [ ] 2. 별도 읽기 전용 store: iOS에 WeekBlocks 모델용 `ModelConfiguration`(CloudKit private, 컨테이너 `iCloud.com.devkoan.ScheduleDensity`) 추가. 기존 `Event` store는 **그대로 둠**
      - entitlements에 iCloud/CloudKit + 컨테이너 ID + Background Modes(Remote notifications)
- [x] 3a. 어댑터 순수 코어: `WeekBlocksAdapter`(타깃 의존성 없음) — `WBRoutineInput`/`WBBlockInput` → `WBVisualEvent`
      - PlanBlock → 해당 주 단일일(weekStart+요일, hoursPerDay=durationHours)
      - Routine.fixed → 주간 반복(selectedWeekdays, hoursPerDay=durationHours)
      - Routine.quota → 7일 평균 부하 밴드(hoursPerDay=weeklyHours/7)
      - 요일 변환 mon0→iOS weekday, 날짜·색·필터 모두 swiftc로 단위 검증 통과 ✅
- [x] 1·2. 모델 공유·store: Models/Routine/PlanBlock을 iOS 타깃에 포함, Routine 색상헬퍼는 Theme(macOS)로 분리.
      `WeekBlocksStore`(Services) = 별도 읽기전용 CloudKit 컨테이너(`iCloud.com.devkoan.ScheduleDensity`), Event 스토어와 분리.
      entitlements 컨테이너 추가 + Background Modes(Remote notifications). pbxproj에 어댑터/스토어 정식 포함.
- [x] 3b. 배선: WeekBlocksStore.loadVisualEvents()가 Routine/PlanBlock→어댑터→[Event](insert 금지).
- [x] 4. 표시: ScheduleViewModel.fetchEvents()에 합쳐 투입(전 화면 반영) + SettingsView "무지개 공방 계획 표시" 토글(기본 ON).
- [ ] ⚠️ 런타임 검증 미완: 같은 iCloud 계정 실기기/시뮬레이터에서 Mac↔iOS 실제 동기화 확인 필요.
- [ ] 5. 동기화 상태: iCloud 미로그인/첫 다운로드 지연/오프라인 빈 상태 UI 처리, 원격 변경 시 갱신(현재는 캐시가 dataRefreshTrigger에만 반응).
- [ ] (개선) 어댑터가 쿼터를 7일 평균으로 뭉갬 → '하루 흐름'까지 보이려면 TimelineLayout 공유 코어화.
- [ ] 6. (보류) successCriteria·deliverable·reviewStatus 노출 여부 결정

## macOS(WeekBlocks) 피드백 반영 (2026-06-23) — macOS 빌드 성공
- [x] 1. 타임라인 격자 6h → 3h 세분화 (DayTimelineRow 격자 major 3h, HourAxis 0·3·6…24)
- [x] 2. 짧은 블록 텍스트 — 임계값 30→18 + minimumScaleFactor + 툴팁에 계획 이름 노출
- [x] 3. 유연 쿼터 대비 강화 — 고정 위에 겹칠 때 흰 테두리 링 + 채움 0.20→0.32
- [x] 4. '구체성 체크' 버튼 제거 — 편집기 진입 시 항상 실시간 피드백
- [x] 5. 계획 블록을 다른 요일로 드래그 이동 (BlockChip draggable + 드롭에서 day 변경)
- [x] 6. '이번 주 계획' 순서 = '요일별 하루' 타임라인 순서 일치
      - DayPlanItem을 occurrence 기반으로(고정/끼니세션/블록) 재정의, TimelineLayout.segments의 seg.start로 정렬
      - 자정 넘긴 고정 루틴(수면)은 조각마다 따로 → 위·아래 두 번 표시
      - 유연 쿼터(끼니)는 다른 일정과 안 겹치는 세션만 자기 시각에 표시(겹치면 접음), 부제에 세션 시각

## WeekBlocks 기능 백로그 (흡수)
- [ ] ConcretenessChecker Level 2 — 측정 가능 패턴 정규식
- [ ] ConcretenessChecker Level 3 — Claude API 판정
- [ ] 시간 그리드 / 블록 드래그 이동 / 반복 계획 블록
- [ ] 알림 / 메뉴바 위젯
