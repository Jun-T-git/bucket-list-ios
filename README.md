# バケットリスト — iOS app (SwiftUI)

SwiftUI implementation of the v2 prototype from `バケットリスト v2.html`,
evolved past the prototype to make the core experience real
(see `docs/philosophy/01-コアコンセプト.md`, and `CLAUDE.md` for the
autonomous-development guide).

## Quick start

```sh
open BucketList.xcodeproj
```

Pick an iPhone simulator (iOS 17+) and hit ▶︎.

## File layout

```
BucketList/
  BucketListApp.swift   — @main entry point, notification re-sync on launch
  ContentView.swift     — root TabView, FAB, custom tab bar, tab icons
  Theme.swift           — tokens.css → Color/Font/shadow constants, Haptics
  Models.swift          — Item / Priority / Season / Tag / AppStore /
                          Storage / Classifier / Clock / TimingSuggestion /
                          NotificationPlanner / SeasonalCopy
  Components.swift      — HighlightWord, ToastView, PriorityPill,
                          SeasonChip(+Row), TagChip(+Row), Check,
                          FlowLayout, SectionLabel, HintLine, PressScale
  HomeView.swift        — リスト tab (HeroHeader, InlineSuggestionBanner,
                          CountStrip, OptionsButton, single flat ListRow,
                          EmptyList)
  AddEditSheet.swift    — 追加/編集 modal (shared component, AI おまかせ)
  DetailSheet.swift     — 詳細 modal (past-you note, tappable via card)
  FilterSheet.swift     — ViewOptionsSheet: unified sort + 3-axis filter
                          modal (multi-select w/ per-chip counts)
  ReportView.swift      — レポート tab (real done-history chart, PaceCard,
                          SeasonPlanCard in upcoming order)
  SettingsView.swift    — 設定 tab (通知/AI/タグ管理/データ)
  SelectAllTextField.swift — UITextField wrapper: selects-all on focus so an
                          AI suggestion can be overwritten without deleting
  Capture/              — URL → やりたいこと候補 (on-device, no backend)
    URLMetadata.swift       — normalize / SourceType / SSRF guard / redirects /
                            LinkPresentation + capped HTML·OGP → LinkMetadata
    ItemCandidate.swift     — editable candidate model + tag validation
    OnDeviceModel.swift     — Foundation Models (@Generable, iOS 26, weak-linked)
    RuleBasedCandidate.swift— keyword fallback when the model is unavailable
    CandidateGenerator.swift— orchestration: metadata → model|rules → candidate
  BucketList.entitlements — App Group (group.teratech.BucketList)
  Assets.xcassets/      — AccentColor + AppIcon (1024px, brand motif)
  Preview Content/      — SwiftUI preview asset catalog
ShareExtension/         — 共有拡張ターゲット (コア体験① 回収)
  ShareViewController.swift — principal class: pulls URL/text/title from the
                          share sheet, hosts the SwiftUI confirm sheet
  ShareComposeView.swift   — SwiftUI confirm sheet (title + priority + AI
                          おまかせ draft → Storage 直書き, via "共有")
  Info.plist            — NSExtension (share-services activation rule)
  ShareExtension.entitlements — same App Group as the host app
  (reuses Models.swift + Theme.swift via shared target membership)
```

## Core behaviour

- **Live clock** — `Clock` (Models.swift) reads real time. The whole product
  is timing-based nudges, so hero copy, NOW badges, suggestions, and the
  report all follow today's date. Set `Clock.override` to pin a date for
  screenshots/previews.
- **Timing suggestions (コア体験③)** — `AppStore.timingSuggestion()` picks
  a frame from where today sits (年末 > 週末 [Fri–Sun] > 月初 > 季節の
  終わり > 季節中) and offers up to 3 open items ranked by
  season-fit + priority, so weekend frames don't surface "someday" trips.
- **Real report** — items carry `doneAt`; the レポート chart, pace card and
  totals aggregate the user's actual history (last 12 months). Friendly
  empty states when there's no data yet. "これからの季節" starts at the
  current season.
- **Done trail** — done is a filter, not a split section: リスト stays a
  single flat list and `sort()` keeps checked-off items in place (dimmed,
  strikethrough). Checking off fires a tone-aware celebration toast (with
  an undo action); there is no confetti / sparkle animation — the product
  reads as a plain, familiar iOS app.
- **Local notifications** — 設定 toggles schedule real
  `UNCalendarNotificationTrigger`s: season starts (3/1·6/1·9/1·12/1 9:00),
  Friday 17:00 weekend nudge, monthly day-25 19:00 reminder. Permission is
  requested only when the user flips a toggle on, never at launch.
- **3-axis filter model** (priority × season × tag) — clear/multi-select,
  AND across axes, OR within. `ViewOptionsSheet` (FilterSheet.swift) unifies
  sort + filter in one sheet and computes per-chip counts cross-axially.
- **AI classifier** — `Classifier` (Models.swift) regex heuristics draft
  priority/seasons/tags as you *type a title* (instant, offline). Respects the
  設定 › 自動分類 toggle (off = manual pickers, no AI drafts).
- **URL → candidate (on-device)** — paste a link in the add sheet or share one
  to the app, and `Capture/` turns it into an editable "やりたいこと" candidate
  (rewritten title + tags). Metadata comes from LinkPresentation (+ capped
  HTML/OGP only on miss); the draft comes from **Apple Foundation Models**
  (on-device LLM, iOS 26 + Apple Intelligence) and falls back to the keyword
  rules otherwise. Nothing is sent to a backend. The title field selects-all on
  focus so the suggestion can be overwritten in one keystroke; tags/season/
  priority are tap-to-toggle — accept in one tap, override without deleting.
- **Swipe-to-reveal** on list rows: 消化 + 削除 (with undo toast); only one
  row open at a time.
- **Custom tag manager** in 設定: rename / delete, max 10. Removing a tag
  also strips it from every item and any active filter.
- **Persistence** — items + custom tags live in a single JSON document in the
  App Group container, read/written through `NSFileCoordinator` (`SharedStore`
  in Models.swift) so the app and the Share Extension never clobber each other's
  writes; tweaks/prefs stay in the App Group `UserDefaults`. Decoding is tolerant
  and non-destructive: a corrupt record is skipped (not the whole list), an
  unreadable store is recovered from a one-generation backup rather than
  overwritten, and newly-added fields fall back to defaults.

## Known shortcuts (vs production)

- **Fonts**: the design originally called for Zen Maru Gothic / Zen Kaku
  Gothic New / Klee One / JetBrains Mono. Every `Theme.Font` role now maps
  to the plain system font (`.system(design: .default)`) — the earlier
  rounded / serif-italic / monospaced "paper + crayon" variants were
  dropped in favour of a plain, familiar iOS look. Drop the `.ttf` files in
  the bundle and switch the helpers to `.custom(...)` if custom type is
  wanted again.
- **Share extension** (Safari/YouTube/X → app) — implemented (コア体験①).
  The `ShareExtension` target writes captured items straight into the shared
  App Group store; the app picks them up on the next foreground (scenePhase
  `.active` → `AppStore.reload()`). On a real device / TestFlight you must
  plug a `DEVELOPMENT_TEAM` into both targets and register the App Group in
  the Apple Developer portal; the simulator needs neither.
- **Foundation Models availability** — the on-device LLM only runs on iOS 26
  with Apple Intelligence on a capable device/model-downloaded. The framework
  is **weak-linked** (`-weak_framework FoundationModels`) and all use is behind
  `@available(iOS 26, *)`, so the iOS-17 deployment target still builds and
  runs; where the model is absent (incl. most simulators) the rule-based
  fallback handles URL candidates.
- **iCloud sync toggle** is not present; export is a JSON ShareLink.

## Verifying

```sh
# typecheck against the iOS 17 SDK
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos swiftc -typecheck -sdk "$SDK" \
    -target arm64-apple-ios17.0 $(find BucketList -name '*.swift')

# or a full simulator build
xcodebuild -project BucketList.xcodeproj -scheme BucketList \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
```
