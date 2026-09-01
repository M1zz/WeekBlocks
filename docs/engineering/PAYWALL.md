# 유료화 — 무엇을 어떻게 파는가

> 코드는 다 들어가 있고 **스위치만 꺼져 있다.** 실제로 팔기 시작할 때
> `MacEntitlement.sellsAccess`를 `true`로 바꾸면 된다. 그 한 줄이 정책 전부다.

## 무엇을 파는가

**적기.** 그것 하나뿐이다.

```
잠긴 기기        아이폰에서 온 할 일이 내려와 보인다.
                예전에 적어 둔 것도 그대로 보인다.
                새로 적는 것만 막힌다.

연 기기          자유롭게 적고, 적은 것이 상대에게도 보인다.
```

두 앱을 각각 판다. 하나만 사면 **산 쪽 → 안 산 쪽** 한 방향이 된다.

## 왜 '적기'에 선을 그었나

동기화 엔진에는 **방향이 없다.** `NSPersistentCloudKitContainer`는 받기와 보내기를
따로 못 끈다 — 켜면 둘 다, 끄면 둘 다다. "산 쪽에서 안 산 쪽으로만"을 엔진으로
만들려면 스토어를 둘로 나눠야 하는데, 그건 데이터가 사는 집을 쪼개는 일이라 값이 안 맞는다.

그래서 방향을 **사람이 적을 수 있는지**로 만들었다. 안 적으니 보낼 것이 없고,
결과가 한 방향이 된다. 엔진은 그대로 둔다.

## 잠긴 기기의 줄은 왜 상대에게 안 보이나

올라가는 것은 못 막으니 **올라가게 두고, 받는 쪽에서 안 그린다.**
줄마다 두 칸이 실려 간다 (→ `TodoSharing.swift`).

| 칸 | 뜻 |
|---|---|
| `isShared` | 상대에게도 보여도 되는 줄인가. **false → true 로만 간다.** |
| `originInstallID` | 어디서 난 줄인가. 잠긴 기기의 스토어에는 자기 것과 상대 것이 섞여 있어서 필요하다. |

감추는 것은 **남이 잠긴 채로 적어 둔 줄** 하나뿐이다. 내 줄은 잠겨 있어도 내 화면에서는 보인다.

거르는 자리는 **`TodoTree`를 세울 때 한 번**이다. 목록·주간 화면·결산이 전부 그
트리에서 나오므로 거기서 한 번 거르면 어디에도 안 샌다. 화면마다 조건을 따로 쓰면
반드시 어딘가는 새어 보인다.

> ⚠️ 이건 담장이 아니라 **커튼**이다. 값은 사용자 자신의 iCloud를 거쳐 자신의 다른 기기
> 디스크에 실제로 놓인다. 남의 데이터가 아니므로 보안 문제는 아니지만, "물리적으로
> 막았다"고 말하면 안 된다.

## 켜는 순서

### 1. App Store Connect에 상품을 만든다

- 유형: **비소모성**(Non-Consumable). 구독이 아니다.
- 제품 ID: `com.devkoan.ScheduleDensityApp.sync`
  - ⚠️ `MacEntitlement.productID`와 **글자 하나까지 같아야 한다.**
- 이름·설명·가격을 채우고 **심사에 함께 제출**한다. 상품만 따로는 승인이 안 난다.

### 2. 로컬에서 먼저 확인한다

Xcode에 StoreKit 설정 파일을 하나 만들면 App Store Connect 없이 결제 흐름을 돌려볼 수 있다.

```
File → New → File → StoreKit Configuration File
Scheme → Run → Options → StoreKit Configuration 에 지정
```

같은 제품 ID로 비소모성 상품을 하나 넣고, 사기/복원/환불을 다 눌러 본다.

### 3. 스위치를 켠다

```swift
// MacEntitlement.swift
static let sellsAccess = true
```

**이때까지는 모두에게 열려 있다.** 상품을 못 사는 동안 앱이 잠겨 있으면 쓰던 사람이
갑자기 못 적게 되는데, 그건 값을 받는 게 아니라 뺏는 것이다.

### 4. 페이월 화면을 붙인다

아직 없다. 잠긴 상태에서 '새 할 일'이 안 눌리는 것까지만 되어 있고, **왜 안 되는지
말해 주는 화면이 없다.** iOS의 `PaywallView.swift`가 참고가 된다.

붙일 자리:
- 목록이 잠겼을 때 맨 위 한 줄 (iOS `TodoView.readOnlyNotice` 참고)
- 설정 어딘가에 '함께 쓰기 열기' / '구매 복원'

### 5. 산 뒤에 예전 것이 열리게 한다

결제가 확인되면 이 기기에서 난 줄들을 상대에게도 보이게 열어야 한다.

```swift
TodoSharing.openMyItems(in: context)
```

`PurchaseManager.isUnlocked`가 true로 바뀌는 순간에 부른다.
iOS는 `ScheduleDensityApp.swift`의 `onChange(of: purchases.isUnlocked)`에 붙어 있다.
**맥에는 아직 안 붙었다.**

## 남은 일

- [ ] 페이월 화면 (4번)
- [ ] 결제 직후 `openMyItems` 호출 (5번)
- [ ] 잠긴 화면에 "이 기기의 N개는 아이폰에서 안 보입니다" 안내
      (`TodoSharing.hiddenFromOthersCount` 는 있고, 쓰는 곳이 없다)
- [ ] 상세·분류 화면의 쓰기 경로 잠금 (지금은 '새 할 일'만 막힌다)

## 기존 사용자

값을 받기 전부터 쓰던 사람에게 유예를 줄지는 **정하지 않았다.**
iOS에는 `ProEntitlement.grandfathersExistingUsers` 라는 한 줄짜리 정책이 있다.
맥에도 같은 것이 필요하면 그 파일을 참고해 만든다.

지금까지 동기화가 **아예 막혀 있었으므로**(→ `CLOUDKIT.md` 성격의 기록: 커밋 `2cd8173`,
`8914c53`) '쓰던 기능'이라 보기 어렵다는 판단이 한 번 있었다. 다시 정할 때 참고할 것.

## 출시 전 반드시

**CloudKit 콘솔에서 Development → Production 스키마를 배포한다.**

App Store 빌드는 entitlement와 무관하게 **언제나 Production**을 쓴다. 지금 동기화가
되는 것은 Development 환경이기 때문이다. 배포를 빠뜨리면 출시된 앱에서 동기화가
**조용히** 멈춘다 — 필드 하나만 없어도 미러링 초기화 자체가 실패한다.

`isShared`·`originInstallID`도 이번에 새로 생긴 필드라 배포 대상이다.
