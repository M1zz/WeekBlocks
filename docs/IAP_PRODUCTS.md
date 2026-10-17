# 요금제 — App Store Connect 에서 하나씩 세우는 순서 (아이폰 + 맥)

> 2026-10-17. ⚠️ 이 파일은 `욕망의 무지개/docs/IAP_PRODUCTS.md` 와
> `무지개 공방/docs/IAP_PRODUCTS.md` 에 **같은 내용으로** 있다. 한쪽을 고치면 같이 고칠 것.

## 왜 6개인가

두 앱은 번들 ID가 다르다 — 아이폰 `com.example.ScheduleDensityApp`, 맥 `com.devkoan.ScheduleDensityApp`.
그래서 유니버설 구매(한 번 사면 두 플랫폼)가 **안 되고**, 상품도 앱마다 따로 세운다. 앱마다 3개, 모두 6개.

대신 한쪽에서 사면 그 앱이 iCloud에 "샀다"는 표(`ProMark`)를 남기고, 다른 쪽 앱이 그것을 읽고 Pro로 연다.
그러니 **값이 두 앱에서 반드시 같아야 한다.** 다르면 사람들은 싼 쪽에서만 산다.

| | 월간 | 연간 | 평생 |
|---|---|---|---|
| 대한민국 값 | ₩4,400 | ₩22,000 (첫 1주 무료) | ₩59,000 |
| 미국 값 (참고, 직접 확인하지 않음) | $2.99 근처 | $14.99 근처 | $39.99 근처 |

- 연간은 월간 12개월(₩52,800)보다 58% 싸고, 한 달에 ₩1,833꼴이다. 평생은 연간의 2.7배다.
  페이월의 'N% 절약', '월 ₩1,833 꼴'이 이 비율을 그대로 보여 준다.
- 값을 넣을 때마다 **기준 국가를 대한민국**으로 고르고 ₩ 값을 넣는다. 다른 나라 값은 ASC가 환율에 맞춰 채운다.
- 두 레포의 `.storekit`(Xcode 테스트 결제)도 같은 값이다. **진짜 값은 ASC에서만 바뀐다.**

---

## 0단계 — 시작 전에 (한 번만)

1. ASC ▸ **비즈니스**(계약·세금·금융) 에 들어간다.
2. **유료 앱 계약**이 '활성'인지 본다. 아니면 약관에 동의하고 은행 계좌·세금 양식을 끝낸다.
   이게 활성이 아니면 상품을 다 세워도 앱에서 값이 **아예 안 뜬다.**
3. 아이폰 심사용 스크린샷을 준비한다 (맥은 이미 있다 → 아래 '심사용 스크린샷').
4. 가족 공유는 **6개 모두 켠다** (→ 아래 '가족 공유').

---

## 1단계 — 아이폰 「욕망의 무지개」

ASC ▸ **앱** ▸ **욕망의 무지개** 를 연다. 왼쪽 메뉴의 **수익화** 아래에 **구독**과 **앱 내 구입**이 있다.

### 1-1. 구독 그룹 「무지개 Pro」

1. 왼쪽 **구독** 을 누른다.
2. 「무지개 Pro」 그룹이 있으면 연다. 없으면 **만들기** ▸ 참조 이름 `무지개 Pro` ▸ 만들기.
3. 그룹 화면 아래 **App Store 현지화** ▸ **추가**(+) 를 눌러 언어마다 넣는다.
   - 한국어: 구독 그룹 표시 이름 `무지개 Pro`, 앱 이름 표시 방식 **앱 이름 사용**
   - 영어(미국): 구독 그룹 표시 이름 `Rainbow Pro`, 앱 이름 표시 방식 **앱 이름 사용**
   - 다른 언어는 넣지 않으면 영어가 보인다. 넣고 싶으면 같은 식으로 더한다.
4. 저장.

### 1-2. 연간 구독 `com.example.ScheduleDensityApp.pro.annual`

1. 그룹 안 구독 목록에 이 ID가 있으면 연다. 없으면 **만들기**(+):
   - 참조 이름: `Pro 연간`
   - 제품 ID: `com.example.ScheduleDensityApp.pro.annual` — **글자 하나 틀리면 앱에서 안 보인다.**
   - ⚠️ `…pro.yearly` 가 아니다. 그 ID는 ASC가 "이미 다른 구독에서 사용 중"이라 거절했다.
2. **구독 기간**: `1년`.
3. **사용 가능 여부**: 판매할 국가 **전체** 선택 (맥과 같게).
4. **구독 가격**:
   1. **구독 가격 추가**(또는 기존 값 옆 **편집**) 를 누른다.
   2. 국가 **대한민국**, 가격 **₩22,000** 을 고른다 ▸ 다음.
   3. 다른 나라 값이 자동으로 채워진 표가 나온다. 미국이 $14.99 근처인지 본다 ▸ 다음 ▸ 확인.
   4. 이미 값이 있었고 올리는 것이면 '기존 구독자' 처리를 묻는다 → **현재 가격 유지**.
5. **도입 오퍼**(1주 무료):
   1. 구독 가격 영역의 **+** ▸ **도입 오퍼 만들기**.
   2. 국가: 전체, 시작일: 오늘, 종료일: **없음**.
   3. 유형: **무료**, 기간: **1주**.
   4. 확인.
6. **App Store 현지화** ▸ 추가:
   - 한국어 — 표시 이름 `무지개 Pro 연간`
     설명 `위젯·캘린더 가져오기·일정 공유·지난 통계. 맥 앱도 함께 열립니다.`
   - 영어(미국) — 표시 이름 `Rainbow Pro Yearly`
     설명 `Widgets, Calendar import, sharing and stats. Mac too.`
   - 한도: 표시 이름 35자, 설명 55자. 위 문구는 한도 안이다.
     (`Products.storekit` 의 설명은 55자를 넘어서 그대로 붙여 넣으면 안 된다.)
7. **가족 공유**: **켜기**.
8. **이미지**(선택, 앱스토어에서 홍보할 때): `docs/screenshots/iap/promo-yearly.png` (1024×1024).
9. **심사 정보**:
   - 스크린샷: `docs/screenshots/iap/pro-yearly.png` (아직 없다 → 아래 '심사용 스크린샷')
   - 심사 메모: 아래 '심사 메모'의 아이폰 글을 붙여 넣는다.
10. 저장. 상태가 **제출 준비 완료**가 되어야 한다. '메타데이터 누락'이면 빠진 칸이 빨갛게 보인다.

### 1-3. 월간 구독 `com.example.ScheduleDensityApp.pro.monthly`

1-2와 같은 순서로, 다른 것만:

- 참조 이름 `Pro 월간`, 제품 ID `com.example.ScheduleDensityApp.pro.monthly`
- 구독 기간 `1개월`
- 가격 대한민국 **₩4,400** (미국 $2.99 근처인지 확인)
- **도입 오퍼 없음**
- 현지화 — 한국어 `무지개 Pro 월간` / 설명은 연간과 같음.
  영어 `Rainbow Pro Monthly` / 설명은 연간과 같음.
- 이미지 `promo-monthly.png`, 심사 스크린샷 `pro-monthly.png`, 심사 메모 같음.

### 1-4. 그룹 안 차례

1. 「무지개 Pro」 그룹 화면으로 돌아간다.
2. 구독 목록의 **순서 편집**에서 **연간을 1(맨 위), 월간을 2** 로 둔다.
   위가 더 높은 단계라, 월간 → 연간은 '업그레이드'로 즉시, 연간 → 월간은 갱신일에 바뀐다.
3. 둘이 **같은 그룹**에 있어야 서로 갈아탈 수 있고, 두 번 구독되는 일이 없다.

### 1-5. 평생 이용권 `com.example.ScheduleDensityApp.pro` (있는 상품을 고친다)

⚠️ **새로 만들지 않는다.** 1.1.x 때 ₩4,900에 팔던, 이미 승인된 비소모성 상품이다.
그때 산 사람은 아무것도 안 해도 평생 Pro다. `…pro.lifetime` 같은 새 ID를 만들면 그 사람들이 잠긴다.

1. 왼쪽 **앱 내 구입** ▸ `com.example.ScheduleDensityApp.pro` 를 연다.
2. **가격 일정** ▸ 가격 변경(편집):
   1. 기준 국가 **대한민국**, 가격 **₩59,000**.
   2. 시작일: 오늘(또는 1.1.13이 나가는 날).
   3. 미국이 $39.99 근처인지 보고 확인.
3. **App Store 현지화**의 기존 줄을 고친다:
   - 한국어 — 표시 이름 `무지개 Pro 평생`
     설명 `위젯·캘린더 가져오기·통계를 한 번 결제로. 맥 앱도 함께 열립니다.`
   - 영어(미국) — 표시 이름 `Rainbow Pro Lifetime`
     설명 `Widgets, Calendar import and stats, once. Mac too.`
4. **가족 공유**: **켜기** (이미 켜져 있으면 그대로).
5. 이미지 `promo-lifetime.png`, 심사 스크린샷 `pro-lifetime.png`, 심사 메모.
6. 저장. 이름·설명을 고치면 상품이 다시 심사 대상이 될 수 있다 → 2단계에서 버전과 함께 낸다.

---

## 2단계 — 아이폰 버전에 붙여 함께 낸다

1. ASC ▸ 욕망의 무지개 ▸ 왼쪽 **iOS 앱** 아래 다음 버전(예: 1.1.13)을 연다.
2. 아래로 내려 **앱 내 구입 및 구독** 칸 ▸ **앱 내 구입 또는 구독 선택**(+).
3. 연간·월간·평생 중 **심사 대기가 아닌 것(제출 준비 완료)** 을 모두 체크 ▸ 완료.
4. 이 칸은 처음 심사받는 상품이나 고친 상품이 있을 때만 보인다. 안 보이면 셋 다 이미 승인된 것이다.
5. 버전 제출은 **DeployBar** 가 한다 (`DeployBar --deploy 욕망의 무지개`). 상품만 붙여 두면 된다.

⚠️ 상품을 안 붙인 채 빌드만 내면 심사자가 페이월에서 값을 못 받아 오류를 본다.
1.1.8 (17)·(20)이 iPad 심사에서 이걸로 **2.1(b) 거절을 두 번** 받았다.

---

## 3단계 — 맥 「무지개 공방」

ASC ▸ **앱** ▸ **무지개 공방** 을 연다. 메뉴 자리는 아이폰과 같다.
10/13에 셋 다 이미 만들었다(평생 $29.99 · 연간 $14.99 · 월간 $1.99). **값과 문구만 고친다.**

### 3-1. 구독 그룹 「무지개 공방 Pro」

1. **구독** ▸ 「무지개 공방 Pro」 를 연다.
2. **App Store 현지화**에 한국어 `무지개 공방 Pro`, 영어(미국) `Rainbow Craft Pro` 가 있는지 본다.
   없으면 1-1의 3번처럼 더한다 (앱 이름 표시 방식 **앱 이름 사용**).

### 3-2. 연간 구독 `com.devkoan.ScheduleDensityApp.pro.yearly`

1. 연다.
2. **구독 가격** ▸ 대한민국 값이 **₩22,000** 인지 본다. 아니면 1-2의 4번처럼 고친다
   (올리는 것이면 '기존 구독자' → **현재 가격 유지**).
3. **도입 오퍼**가 '무료 · 1주 · 전체 국가 · 종료 없음' 인지 본다. 없으면 1-2의 5번처럼 만든다.
4. **App Store 현지화**:
   - 한국어 — 표시 이름 `무지개 공방 Pro 연간`
     설명 `회고 추세·계획 대비 실제·지난 주 가져오기. 아이폰 앱도 함께.`
   - 영어(미국) — 표시 이름 `Rainbow Craft Pro Yearly`
     설명 `Trends, plan vs. actual, past weeks. iPhone app too.`
5. 가족 공유: **켜기**.
6. 이미지 `docs/screenshots/iap/promo-yearly.png`, 심사 스크린샷 `docs/screenshots/iap/pro-yearly.png`
   (2880×1800, 이미 있다), 심사 메모는 아래 맥 글.
7. 저장 ▸ **제출 준비 완료** 확인.

### 3-3. 월간 구독 `com.devkoan.ScheduleDensityApp.pro.monthly`

1. 연다.
2. **구독 가격**: $1.99 → 대한민국 **₩4,400** 으로 올린다 (기존 구독자 → **현재 가격 유지**).
3. 도입 오퍼 **없음**.
4. 현지화 — 한국어 `무지개 공방 Pro 월간` / 설명은 연간과 같음.
   영어 `Rainbow Craft Pro Monthly` / 설명은 연간과 같음.
5. 이미지 `promo-monthly.png`, 심사 스크린샷 `pro-monthly.png`, 심사 메모.
6. 저장.

### 3-4. 그룹 안 차례

「무지개 공방 Pro」 ▸ 순서 편집 ▸ **연간 1, 월간 2**.

### 3-5. 평생 이용권 `com.devkoan.ScheduleDensityApp.sync`

⚠️ ID가 `…pro.lifetime` 이 아니라 `…sync` 다. 예전 '함께 쓰기' 상품을 이어 쓴다. 새로 만들지 않는다.

1. **앱 내 구입** ▸ `com.devkoan.ScheduleDensityApp.sync` 를 연다.
2. **가격 일정**: $29.99 → 대한민국 **₩59,000** (미국 $39.99 근처인지 확인).
3. 현지화:
   - 한국어 — 표시 이름 `무지개 공방 Pro (평생)`
     설명 `회고 추세와 계획 대비 실제를 한 번 결제로. 아이폰 앱도 함께 열립니다.`
   - 영어(미국) — 표시 이름 `Rainbow Craft Pro (Lifetime)`
     설명 `Trends and plan vs. actual, once. iPhone app too.`
4. 가족 공유: **켜기**.
5. 이미지 `promo-lifetime.png`, 심사 스크린샷 `pro-lifetime.png`, 심사 메모.
6. 저장.

---

## 4단계 — 맥 버전에 붙여 함께 낸다

1. 무지개 공방 ▸ 왼쪽 **macOS 앱** 아래 다음 버전을 연다.
2. **앱 내 구입 및 구독** ▸ (+) ▸ 제출 준비 완료인 상품을 모두 체크 ▸ 완료.
3. 1.1.12 를 아직 안 냈다면 거기에 붙인다 (todo: "1.1.12 버전 페이지에 세 상품을 붙여 앱과 함께 심사").
4. 제출은 DeployBar (`DeployBar --deploy 무지개 공방`).

---

## 5단계 — 두 앱 값 대조

두 앱의 **구독** ▸ 각 상품 ▸ 구독 가격 ▸ **모든 가격 보기**에서 몇 나라를 나란히 본다.

| 확인 | 아이폰 | 맥 |
|---|---|---|
| 대한민국 월간 | ₩4,400 | ₩4,400 |
| 대한민국 연간 | ₩22,000 | ₩22,000 |
| 대한민국 평생 | ₩59,000 | ₩59,000 |
| 미국 | 세 값이 맥과 같은가 | |
| 판매 국가 | 맥과 같은 국가 목록인가 | |
| 도입 오퍼 | 연간에만 1주 무료 | 연간에만 1주 무료 |
| 가족 공유 | 6개 모두 켜졌는가 | |

---

## 6단계 — 샌드박스로 한 번 사 본다

1. ASC ▸ **사용자 및 액세스** ▸ **샌드박스** ▸ 테스터 추가 (안 쓰던 이메일).
2. 아이폰: 설정 ▸ App Store ▸ 맨 아래 **샌드박스 계정**으로 로그인.
   맥: App Store 앱 ▸ 설정 ▸ 샌드박스 계정 (또는 처음 살 때 뜨는 창에서 로그인).
3. TestFlight 빌드(또는 Xcode에서 StoreKit 설정 없이 돌린 빌드)로:
   1. 아이폰에서 **연간** 체험 시작 → Pro가 열리는가.
   2. 같은 iCloud 의 맥에서 무지개 공방을 켠다 → **사지 않았는데 Pro로 열리는가** (ProMark).
   3. 아이폰에서 구독을 해지·만료시킨다(샌드박스는 1년이 1시간쯤) → 맥도 다시 잠기는가.
   4. 반대로 맥에서 **평생**을 사고 → 아이폰이 열리는가.
   5. 앱을 지웠다 깔고 **구매 복원** → 다시 열리는가.

---

## 심사용 스크린샷

- 맥: `무지개 공방/docs/screenshots/iap/pro-{monthly,yearly,lifetime}.png` (2880×1800) — 있다.
- 아이폰: **없다.** 찍는 법:
  1. 시뮬레이터(iPhone 17 Pro Max 등)에서 욕망의 무지개를 Debug로 돌린다.
  2. `ProEntitlement.unlockedInDebug` 를 잠깐 `false` 로 바꿔야 잠긴 페이월이 보인다 (찍고 되돌린다).
  3. 무지개 탭 ▸ 톱니(설정) ▸ Pro 항목을 눌러 페이월을 연다.
     또는 `xcrun simctl openurl booted rainbow://paywall/widget`.
  4. 연간이 골라진 상태로 `xcrun simctl io booted screenshot docs/screenshots/iap/pro-yearly.png`.
     월간·평생을 각각 골라 `pro-monthly.png` · `pro-lifetime.png`.
  5. 한 장을 셋에 다 써도 심사는 받는다. 다만 상품마다 그 줄이 골라진 화면이면 더 분명하다.

## 심사 메모 (상품마다 붙여 넣는 글)

**아이폰 (욕망의 무지개)**

```
Pro is optional. Planning, the rainbow view, to-dos, step breakdown, timers and syncing with the Mac app are free.
Pro unlocks: Home/Lock Screen widgets, Calendar import, schedule sharing, and statistics and the Ledger older than the last two weeks.
To open the paywall: Rainbow tab > gear (Settings) > Pro, or tap a locked widget.
Yearly and Monthly are in one subscription group; Yearly has a 1-week free trial. Lifetime is a one-time non-consumable.
Pro bought in our companion Mac app with the same iCloud account also unlocks this app (and vice versa) through a record in the user's private iCloud. Restore Purchases is on the paywall.
```

**맥 (무지개 공방)**

```
Pro is optional. Weekly and daily planning, routines, to-dos, timers, this week's review and syncing with the iPhone app are free.
Pro unlocks: review trends beyond the last two weeks, plan vs. actual, copying plans from other weeks, exporting reviews and sharing your schedule.
To open the paywall: Settings > Pro, or open Trends in the weekly review.
Yearly and Monthly are in one subscription group; Yearly has a 1-week free trial. Lifetime is a one-time non-consumable.
Pro bought in our companion iPhone app with the same iCloud account also unlocks this app (and vice versa) through a record in the user's private iCloud. Restore Purchases is on the paywall.
```

## 가족 공유 — 6개 모두 켠다 (2026-10-17 결정)

- 6개 상품 모두 **가족 공유 켜기**. 한 사람이 사면 가족 공유 그룹 최대 6명이 함께 Pro를 쓴다.
- ⚠️ ASC에서 **한 번 켜면 다시 끌 수 없다.** 켜기 전에 이 결정이 맞는지 한 번 더 본다.
- 이미 산 사람(특히 아이폰 평생 `…pro` 와 맥 `…sync`)에게도 켜는 순간부터 가족에게 퍼진다.
- 두 레포의 `.storekit` 도 6개 모두 `familyShareable: true` 로 맞췄다 (테스트 결제가 실제와 같게).
- 코드는 고칠 것이 없다. 가족이 공유받은 거래도 `LeeoStore` 가 영수증으로 읽고,
  그 가족의 iCloud에 `ProMark` 를 남겨 다른 쪽 앱도 연다.
- 앱 소개 글에 가족 공유를 알리고 싶으면 `APPSTORE.md` 의 구독 안내에 한 줄 더한다 (선택).

## 코드와 맞물리는 곳 (값·ID를 바꾸면 같이 볼 것)

| | 아이폰 | 맥 |
|---|---|---|
| 상품 ID | `ScheduleDensityApp/Shared/ProEntitlement.swift` | `WeekBlocks/WeekBlocksSpec.swift` · `MacEntitlement.swift` |
| 테스트 결제 | `ScheduleDensityApp/Products.storekit` | `WeekBlocks.storekit` |
| 두 앱 잇기 | `ScheduleDensityApp/Shared/ProMark.swift` | `WeekBlocks/ProMark.swift` (같은 내용) |
| 팔기 스위치 | `ProEntitlement.sellsPro` = true | `MacEntitlement.sellsPro` = true |

ID는 지금 코드와 ASC가 같다. **이 문서대로 하면 코드는 고칠 것이 없다.**
