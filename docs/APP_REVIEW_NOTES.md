# App Review 답변 — 맥판 첫 제출 (Guideline 2.1 Information Needed)

> 2026-11-12. 아이폰 '욕망의 무지개' 와 같은 번들 ID(`com.example.ScheduleDensityApp`)로 올린 맥판 1.1.15 (빌드 36)에 온 요청.
> 아래 **영문 그대로** 두 곳에 붙인다:
>   1. App Store Connect ▸ 앱 심사 메시지(Resolution Center)의 답장 — 영상 파일을 첨부한다.
>   2. App Store Connect ▸ macOS 앱 ▸ 앱 심사 정보 ▸ **메모(Notes)** — 다음 제출에도 남는다 (4000자 이내).
>
> 영상: `docs/review/AppReview-macOS-1.1.15.mp4` (이 맥에서 실제 앱을 녹화. 영상은 레포에 올리지 않는다 — `.gitignore`)
> 다시 찍기: `scripts/record-review-video.sh`

---

Hello App Review team,

Thank you for reviewing the macOS version of our app. This build adds a Mac app to the existing iPhone app record (same bundle ID, universal purchase). The attached recording was captured on a Mac running macOS 27.0, the latest release.

1. SCREEN RECORDING
Attached. It starts with launching the app, then shows the typical flow: first-run setup of fixed routines, adding to-dos, dragging one onto a day in the week grid, the 24-hour timeline, the timer, the weekly review and its Trends, the plans sheet that sells the paid features, and Settings. The recording stops before paying, because completing a purchase needs an Apple Account sign-in in Apple's payment sheet.
The app has no account registration, no login, and no user-generated content shared publicly, so those flows do not exist.

2. PURPOSE AND AUDIENCE
Rainbow Craft is a weekly planner for people who keep running out of week. A to-do list cannot tell you whether your week can actually hold it. The app has you lay down the hours you cannot give up first (sleep, meals, work or school), shows the hours that are really left out of 168, and lets you drag to-dos onto the days that still have room. A timer follows the plan, and a weekly review compares what you planned with what happened, so the next week is planned on real numbers.
Audience: students, office workers and freelancers who plan their own time, including iPhone users who want the same plan on a larger screen.

3. HOW TO ACCESS THE MAIN FEATURES
No login, demo account or sample file is needed.
a) On first launch, a short setup asks which fixed routines to create (Sleep, Meals, Work · school, Exercise). Pick any, or skip.
b) To fill the week quickly for review, click More (…) in the toolbar and choose "Add sample data".
c) Add a to-do with "New to-do" in the to-do list, then drag it onto a day in the week grid to make a plan block.
d) "Timeline view" opens one day on a 24-hour ruler. "Timer" shows what is planned now and the time left. "Review" opens the weekly review and its Trends.
e) Paid features: open Settings and click "See plans", or open Review > Trends. Purchases use the standard In-App Purchase sheet and work with a Sandbox account.
   Free: plans, routines, to-dos, the weekly review, the timer, calendar import, iPhone sync, and the last 2 weeks of trends.
   Plus (yearly subscription or one-time): 8-week trends, day and hour insights, planned versus actual, and copying another week's plan.
   Pro (yearly subscription or one-time): everything in Plus, sharing your schedule as a view-only iCloud link, and Pro in the iPhone app.
   These are the same In-App Purchases already approved for the iPhone app. "Restore purchase" is in the plans sheet.
f) Optional: "Import from Calendar" (More menu) reads events from the Mac Calendar after the system permission prompt. If the user turns it on, the app writes plan blocks only to a separate calendar it creates, and never edits other calendars.

4. EXTERNAL SERVICES
The app has no server of its own and uses no third-party SDKs, AI services, ad networks or login providers. It uses only Apple services:
- iCloud / CloudKit (private database): syncs the user's own data between their Mac and iPhone.
- CloudKit sharing: optional view-only schedule link (Pro). It is shared only with people the user invites through iCloud.
- StoreKit: In-App Purchases.
- EventKit: optional calendar import and export described above.
- CloudKit public database: the feedback form in Settings, and anonymous usage counts tied only to a random install ID (no personal data or content; can be turned off in Settings).

5. REGIONAL DIFFERENCES
None. The app works the same in every region. Only the interface language (24 localizations) and the local price of the In-App Purchases differ.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app is not in a regulated industry and contains no protected third-party content.

Thank you.
