# 일정 밀도 앱 (Schedule Density App)

일정의 밀도를 시각화하고, 비어있는 시간대를 추천해주는 iOS 앱입니다.

> 🌈 **WeekBlocks(macOS) 지원 페이지** → https://m1zz.github.io/ScheduleDensity/
> 주간 타임블로킹 앱 WeekBlocks의 사용 안내·FAQ·문의 페이지입니다.

> **패밀리 구조**: 이 프로젝트(`ScheduleDensityApp.xcodeproj`)는 두 개의 타깃을 포함합니다.
> - **ScheduleDensityApp** (iOS) — 일정 밀도 시각화 + 빈 시간 추천 (`com.example.ScheduleDensityApp`)
> - **WeekBlocks** (macOS) — 주간 타임블로킹 + 구체성 검사 (표시이름 ScheduleDensity, `com.devkoan.ScheduleDensityApp`)
>
> iCloud(CloudKit) 동기화: 패밀리 공유 컨테이너 `iCloud.com.devkoan.ScheduleDensity` 사용.
> macOS 타깃은 적용 완료(SwiftData `cloudKitDatabase: .private(...)`). iOS 타깃은 미적용(아래 todo 참고).
>
> 빌드:
> ```
> xcodebuild -scheme ScheduleDensityApp -destination 'generic/platform=iOS' build
> xcodebuild -scheme WeekBlocks -destination 'platform=macOS' build
> ```
> macOS 앱 소스는 `WeekBlocks/` 폴더에 있습니다.

## 📱 주요 기능

1. **주간 캘린더 뷰**
   - 30분 단위로 일정 표시
   - 일정이 겹칠수록 색상이 진해짐
   - 좌우 스와이프로 주 이동

2. **반복 일정 지원**
   - 매일, 평일, 주말, 월수금, 화목 등
   - 사용자 지정 요일 선택 가능
   - 기간 설정 (시작일 ~ 종료일)

3. **시간대 추천**
   - 일정 밀도가 낮은 시간대 자동 추천
   - 주간 밀도 분석
   - 점수 기반 추천 순위

4. **샘플 데이터**
   - 수업 (매일 09:00-18:00)
   - 운동 (월수금, 2시간)
   - 스터디 (주말, 2시간)
   - 스터디 준비 (수요일, 2시간)

## 🛠 기술 스택

- **SwiftUI**: 모던 UI 프레임워크
- **Swift Data**: 데이터 영속화
- **iOS 17.0+**: 최소 지원 버전

## 📂 프로젝트 구조

```
ScheduleDensityApp/
├── Models/
│   ├── Event.swift              # 일정 데이터 모델
│   └── RecurrencePattern.swift  # 반복 패턴 정의
├── ViewModels/
│   └── ScheduleViewModel.swift  # 비즈니스 로직
├── Views/
│   ├── ContentView.swift        # 메인 화면
│   ├── WeekView.swift           # 주간 캘린더
│   ├── AddEventView.swift       # 일정 추가
│   └── RecommendationView.swift # 추천 화면
└── Utilities/
    ├── DateExtensions.swift     # 날짜 유틸리티
    └── DensityCalculator.swift  # 밀도 계산
```

## 🚀 실행 방법

1. Xcode 15.0 이상 필요
2. `ScheduleDensityApp.xcodeproj` 열기
3. 시뮬레이터 또는 실제 기기 선택
4. ⌘ + R 로 실행

## 💡 사용 방법

### 일정 추가
1. 상단 `+` 버튼 클릭
2. 일정 정보 입력
3. 반복 패턴 선택 (선택사항)
4. `추가` 버튼 클릭

### 시간대 추천
1. 상단 💡 버튼 클릭
2. 새 일정의 소요 시간 설정
3. `추천 시간 찾기` 클릭
4. 추천 리스트 확인

### 샘플 데이터 추가
1. 상단 `⋯` 메뉴 클릭
2. `샘플 데이터 추가` 선택
3. 확인

## 🎨 디자인 특징

- **무지개 시각화**: 일정이 겹칠수록 색이 진해짐
- **30분 단위**: 세밀한 시간 관리
- **직관적인 UI**: 한눈에 보는 주간 일정
- **밀도 분석**: 데이터 기반 추천

## 📝 라이선스

MIT License

## 👤 개발자

Created by Claude (2025)

---

**참고**: 이 앱은 iOS 17.0 이상에서만 작동합니다 (Swift Data 사용).
