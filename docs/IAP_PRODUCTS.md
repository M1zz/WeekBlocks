# 요금제 — App Store Connect 에 세울 상품 (아이폰 + 맥)

> 2026-10-17 정리. ⚠️ 이 파일은 `욕망의 무지개/docs/IAP_PRODUCTS.md` 와
> `무지개 공방/docs/IAP_PRODUCTS.md` 에 **같은 내용으로** 있다. 한쪽을 고치면 같이 고칠 것.

## 한눈에

두 앱은 번들 ID가 달라(`com.example.ScheduleDensityApp` / `com.devkoan.ScheduleDensityApp`)
**유니버설 구매가 안 된다.** 그래서 상품도 앱마다 따로, **모두 6개**다.
한쪽에서 산 것은 iCloud의 `ProMark` 표로 다른 쪽도 연다(→ `ProMark.swift`). 그러니 **값은 반드시 같아야 한다.**
값이 다르면 사람들은 싼 쪽에서만 산다.

| | 월간 | 연간 | 평생 |
|---|---|---|---|
| 값 (대한민국) | **₩4,400** | **₩22,000** (1주 무료 체험) | **₩59,000** |
| 미국 (참고) | $2.99 근처 | $14.99 근처 | $39.99 근처 |

- 연간은 월간 12개월보다 58% 싸고(월 ₩1,833꼴), 평생은 연간의 2.7배다. 페이월의 'N% 절약'이 이 비율을 그대로 보여 준다.
- **기준 국가를 대한민국으로** 두고 ₩ 값을 넣으면 다른 나라 값은 ASC가 맞춘다. 미국 값만 위와 비슷한지 눈으로 확인한다.
- 이 값은 두 레포의 `.storekit`(테스트 결제)과 같다. **진짜 값은 ASC에서만 바뀐다.**

## 아이폰 — 욕망의 무지개

구독 그룹 **「무지개 Pro」** (그룹 표시 이름 ko `무지개 Pro` · en `Rainbow Pro`)

| 상품 ID | 종류 | 값 | 지금 상태 → 할 일 |
|---|---|---|---|
| `com.example.ScheduleDensityApp.pro.monthly` | 자동 갱신 구독 · 1개월 · 그룹 순위 2 | ₩4,400 | 9/30에 만들었다고 적혀 있음 → 값 바꾸고 '제출 준비 완료'인지 확인 |
| `com.example.ScheduleDensityApp.pro.annual` | 자동 갱신 구독 · 1년 · 그룹 순위 1 · **도입 오퍼 1주 무료** | ₩22,000 | 같음 |
| `com.example.ScheduleDensityApp.pro` | **비소모성** (평생) | ₩59,000 | 1.1.x에 ₩4,900에 팔던 승인된 상품 → **새로 만들지 말고** 값·이름·설명만 고친다. 그때 산 사람은 그대로 평생 Pro |

- ⚠️ 연간 ID는 `…pro.annual` 이다. `…pro.yearly` 는 ASC가 "이미 사용 중"이라며 거절했다.
- ⚠️ 코드(`ProEntitlement.swift`)·`Products.storekit` 의 ID와 **글자 하나까지 같아야 한다.**

## 맥 — 무지개 공방

구독 그룹 **「무지개 공방 Pro」** (그룹 표시 이름 ko `무지개 공방 Pro` · en `Rainbow Craft Pro`)

| 상품 ID | 종류 | 값 | 지금 상태 → 할 일 |
|---|---|---|---|
| `com.devkoan.ScheduleDensityApp.pro.monthly` | 자동 갱신 구독 · 1개월 · 그룹 순위 2 | ₩4,400 | 10/13에 $1.99로 만듦 → 값만 올린다 |
| `com.devkoan.ScheduleDensityApp.pro.yearly` | 자동 갱신 구독 · 1년 · 그룹 순위 1 · **도입 오퍼 1주 무료** | ₩22,000 | 10/13에 $14.99로 만듦 → ₩22,000인지 확인 |
| `com.devkoan.ScheduleDensityApp.sync` | **비소모성** (평생) | ₩59,000 | 10/13에 $29.99로 만듦(예전 '함께 쓰기' 상품을 이어 씀) → 값 올림 |

- ⚠️ 코드(`WeekBlocksSpec` · `MacEntitlement.swift`)·`WeekBlocks.storekit` 의 ID와 글자 하나까지 같아야 한다.
- 구독 값을 올릴 때 ASC가 기존 구독자 값을 어떻게 할지 묻는다. 1.1.12부터 막 팔기 시작해 구독자가 거의 없으니 **'기존 구독자는 현재 가격 유지'** 가 무난하다.

## 상품마다 채울 것 (ko · en 은 꼭, 나머지 언어는 권장)

ASC 한도: **표시 이름 35자, 설명 55자.** `.storekit`에 적힌 아이폰 설명은 55자를 넘어서 그대로 못 쓴다.
아래는 한도 안으로 줄인 것이고, 한쪽에서 사면 다른 쪽도 열린다는 것을 값 앞에서 말한다.

| 상품 | 표시 이름 ko / en | 설명 ko / en |
|---|---|---|
| 아이폰 월간·연간 | 무지개 Pro 월간 · 연간 / Rainbow Pro Monthly · Yearly | 위젯·캘린더 가져오기·일정 공유·지난 통계. 맥 앱도 함께 열립니다. / Widgets, Calendar import, sharing and stats. Mac too. |
| 아이폰 평생 | 무지개 Pro 평생 / Rainbow Pro Lifetime | 위젯·캘린더 가져오기·통계를 한 번 결제로. 맥 앱도 함께 열립니다. / Widgets, Calendar import and stats, once. Mac too. |
| 맥 월간·연간 | 무지개 공방 Pro 월간 · 연간 / Rainbow Craft Pro Monthly · Yearly | 회고 추세·계획 대비 실제·지난 주 가져오기. 아이폰 앱도 함께. / Trends, plan vs. actual, past weeks. iPhone app too. |
| 맥 평생 | 무지개 공방 Pro (평생) / Rainbow Craft Pro (Lifetime) | 회고 추세와 계획 대비 실제를 한 번 결제로. 아이폰 앱도 함께 열립니다. / Trends and plan vs. actual, once. iPhone app too. |

그 밖에 상품마다:

- **심사용 스크린샷 1장** — 페이월 화면.
  - 맥: `무지개 공방/docs/screenshots/iap/pro-*.png` (2880×1800) 있음.
  - 아이폰: **아직 없다.** 아이폰 페이월을 한 장 찍어 `욕망의 무지개/docs/screenshots/iap/pro-*.png` 로 둔다.
- **홍보 이미지 1024×1024** (선택) — 두 레포 `docs/screenshots/iap/promo-{monthly,yearly,lifetime}.png` 에 같은 그림이 있다.
- **심사 메모** — 무료로 쓰는 범위와 Pro가 잠긴 자리, 그리고 "다른 쪽 앱에서 산 것도 iCloud로 연다"를 적는다.

## 정할 것 — 가족 공유

지금 둘이 어긋나 있다. 아이폰 평생은 테스트 파일에서 가족 공유가 **켜져** 있고, 나머지 다섯은 꺼져 있다.
ASC에서 **한 번 켜면 다시 끌 수 없다.** 무지개 공방 로드맵에는 "가족 공유 켜기"가 있다.
6개를 같은 값으로 맞출 것 — 켤지 끌지는 사람이 정한다.

## 마지막 확인

- [ ] 사업 ▸ 유료 앱 계약 '활성', 은행·세금 완료 (없으면 상품이 아예 안 뜬다)
- [ ] 6개 모두 '제출 준비 완료' (메타데이터 누락이 없을 것), 두 구독 그룹의 현지화
- [ ] 값이 두 앱에서 같은지 — 월간 ₩4,400 · 연간 ₩22,000 · 평생 ₩59,000, 판매 국가도 같게
- [ ] 처음 심사받는 상품은 각 앱 **버전 페이지 ▸ 앱 내 구입 및 구독**에 붙여 빌드와 함께 제출
      (상품 없이 빌드만 내면 1.1.8처럼 페이월이 빈손으로 오류를 내 2.1(b) 거절을 받는다)
- [ ] 샌드박스 계정으로 한쪽에서 사고, 다른 쪽 앱이 Pro로 열리는지 한 번 본다
