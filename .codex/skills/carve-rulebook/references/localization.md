# Localization Rules (Carve)

## Goal
- 앱 화면을 **기기 언어 · iOS 앱별 언어 · 앱 안에서 고른 언어**(ko · en)로 보인다. 영어 앱 이름은 **Carve** 다.
- 설정 › 화면 › 언어에서 앱 안에서도 바꾼다(2026-10-13). 저장은 iOS 앱별 언어와 같은 값(앱 도메인 `AppleLanguages`, ClientInterfaces `AppLanguageClient`)이고,
  지금 실행은 앱 루트가 환경 `locale` 을 바꿔(`appLanguageOverride`) **다시 시작하지 않고 화면 전체가 바뀐다** — 키 기반 `Text("…", bundle:)` 은 저절로,
  미리 만드는 `String` 은 넘긴 locale 의 언어로(아래 9, 즉시 전환 단계 1 · 2 · 3). 새 화면 문구는 키 기반 `Text("…", bundle:)` 를 우선한다.
- 영어 성경(KJV · BSB) 필사와 개역개정 필사를 **섞지 않는다** — 이미 나간 2.0.0 · 1.3.0 기기와 같은 iCloud 저장소를 쓴다.
  2.2 의 필사책끼리도 같은 방식으로 섞지 않는다(아래 「필사책 귀속」, 설계 `docs/notebook-design.md`).
- 결정의 원문과 이유는 설계 `docs/english-localization-design.md`(「결정 n」)다. 이 문서는 코드를 쓸 때 지킬 규칙만 둔다.

---

## Current state (현 구성)
- 원문 언어는 ko 다(`developmentRegion: "ko"` · `defaultKnownRegions: ["en", "ko"]` — `Plugins/ProjectDescriptionHelpers/Project+Templates.swift`).
- 카탈로그는 모듈마다 하나다. 컴파일러 자동 추출이 모듈 단위로 돌고, 작업이 자기 모듈 카탈로그만 고쳐 겹치지 않는다.

  | 모듈 | 카탈로그 | 쓰는 번들 |
  |---|---|---|
  | App | `App/CarveApp/Resources/Localizable.xcstrings` · `InfoPlist.xcstrings`(앱 이름 · 권한 안내) | `.main` |
  | 위젯 | `App/CarveApp/Widget/Resources/Localizable.xcstrings` · `InfoPlist.xcstrings` | `.main` |
  | CarveFeature · ChartFeature · SettingsFeature | `Feature/<모듈>/Resources/Localizable.xcstrings` | `.module` |
  | UIComponents | `Supports/UIComponents/Resources/Localizable.xcstrings` | `.module` |
  | Domain | `Domain/Domain/Resources/Localizable.xcstrings` — 권 이름 · 참조 형식 · 번역본 이름 · 글꼴 이름 등 | `.module` |

  CarveToolkit · ClientInterfaces · Resources 에는 카탈로그가 없다 — 화면 문구를 두지 않는다.
- `String` 으로 꺼내는 도우미는 모듈마다 하나다 — `DomainCatalog` · `CarveFeatureCatalog` · `ChartCatalog` · `SettingsCatalog` · `UIComponentsCatalog` ·
  `AppCatalog`(앱 타깃 — 위젯 · 호스트 없는 `CarveAppTest` 에는 들어가지 않는다)의 `string(_:locale:)`. **locale 은 늘 받는다(비옵셔널, 기본값 없음)** —
  `LocalizedStringResource` 의 locale 로 그 언어를 골라 푼다(아래 7 · 9). 직접 `String(localized:)` 는 이 도우미 파일(`*Catalog.swift`)에만 있다.
  위젯은 도우미가 없다 — 키 기반 `Text("…", bundle: .main)` 만 쓰고, 앱이 App Group 에 적은 화면 언어로 환경 locale 을 넣는다(`VerseWidgetSharing.displayLocale`).

---

## Core principles
1) **키는 한국어 문장 그대로, 원문 언어는 ko 다.** 항목마다 ko · en 둘 다 `stringUnit` state `"translated"` 로 적는다 — ko 값은 키와 같은 한국어다.
   - 이유: ko 값이 없는 항목은 컴파일된 ko 표에 들어가지 않아, 완결성 시험이 영어 누락을 잡지 못한다. Xcode IDE 빌드가 자동으로 더한 추출 항목(ko 값 없음)도 같은 방식으로 채운다.
   - 보간 값은 키에 형식 지정자로 들어간다 — `"\(count)절"` 의 키는 `%lld절` 이다.
   - 예외: Domain 「개역개정판」 키는 ko 값이 「개역개정」 이다. 키 하나에 영어 값이 하나뿐이라, 약칭(en 「NKRV」)과 전체 이름(en 「New Korean Revised Version」)을 다른 키로 나눴다. 이런 예외는 코드 주석에 이유를 적는다.
   - 기계 검사: 모듈마다 `<모듈>LocalizationCatalogTesting`(컴파일된 ko 키 ⊆ en 키). 원본 `.xcstrings` 의 ko 값 누락은 이 시험이 못 보므로 리뷰로 본다.
2) **문구에는 늘 번들을 준다.** 모듈은 static framework 라 리소스가 `<모듈>_<모듈>.bundle` 에 있다. 번들을 주지 않으면 앱 번들에서 찾다 못 찾아 한국어 키가 그대로 보인다.

   | 경우 | 쓰는 법 |
   |---|---|
   | SwiftUI 리터럴 | `Text("…", bundle: .module)`. `Button` · `Label` · `Section` · `navigationTitle` · `accessibilityLabel` 등은 bundle 을 받는 이니셜라이저나 `Text(…, bundle:)` 로 — 예 `.navigationTitle(Text("즐겨찾기", bundle: .module))` |
   | `String` 으로 흐르는 문구(Copy enum · 컴포넌트 인자 · Popup · Action 페이로드 · UIKit 라벨) | 그 모듈의 `…Catalog.string("…", locale:)` — 도우미가 번들을 정한다. 직접 `String(localized:)` 는 쓰지 않는다(9) |
   | TCA 알림 · 확인창 | `TextState("…", bundle: .module)` · `ButtonState { TextState("…", bundle: .module) }` |
   | App · 위젯 | 같은 형식에 `bundle: .main` |
   | 옮기지 않는 글자(이미 현지화된 값 · 사용자 내용 · Debug) | `Text(verbatim:)` |

   - `Text` · `TextState` 의 `comment` 에는 그 문구가 어디에 나오는지 한 줄로 적는다 — 영어 문구 검토(결정 7)에서 화면을 찾는 근거다.
   - 기계 검사: `localized_text_needs_bundle`(`.swiftlint.yml` `custom_rules`, error) — 한글이 든 `Text` · `Button` · `Label` · `TextState` 리터럴에 `bundle:` 이 없는 경우. Debug 폴더 · 프리뷰 · 컴포넌트 갤러리는 `excluded` 다.
     도우미 밖 직접 `String(localized:)` 는 `localized_string_outside_catalog` 가 막는다(9).
3) **수 · 단위는 카탈로그 형식 문자열과 복수형 변형으로 쓴다.** 장 · 절 · 개 · N번째를 문자열로 이어 붙이지 않는다. en 은 `one` · `other` 변형을 채운다(예 `%lld절` → 「%lld verse」 · 「%lld verses」).
   한국어 수사(「하루」 · 「이틀」)는 en 에서 숫자형으로 쓴다. 여러 값을 넣는 문구는 위치 지정 인자(`%1$@ %2$lld`)로 언어마다 순서를 바꿀 수 있게 한다.
4) **날짜 · 수 서식은 넘긴 locale 을 따른다** — 화면 언어에 지역 · 달력 · 시간제는 기기 것(`AppLanguage.locale(base:)`). `Date.FormatStyle(locale: locale)` · `.number…locale(locale)` 처럼 쓴다
   (뷰는 환경 `locale`, 뷰 밖은 `AppLanguage.displayLocale()` — 9). 고정 `ko_KR` `DateFormatter` 를 새로 만들지 않는다. 리듀서의 현재 시각은 여전히 `@Dependency(\.date)` 다(testing.md).
5) **권 이름 · 장절 표기는 화면 언어를 따른다 — 번역본 언어가 아니다**(결정 3). 한국어 화면은 KJV 를 봐도 「창세기 1장 1절」, 영어 화면은 개역개정을 봐도 「Genesis 1:1」 이다.
   - 참조 문자열은 `BibleReference` 로만 만든다(`text(locale:)`). 권 이름은 `BibleTitle.localizedName(locale:)`, 번역본 이름은 `Translation.displayName(locale:)`(약칭) · `fullName(locale:)` 이다.
     「\(권) \(장)장」 처럼 손으로 잇지 않는다. `koreanTitle()` 은 Domain 카탈로그 키의 원문이고, 제품 코드에서는 Debug 에만 남았다.
   - 번역본 약칭은 참조 뒤에 「 · KJV」 처럼 붙인다. 2.0 부터 번역본을 적어 온 곳(이미지 저장의 출처 · 위젯 · 필사 헤더 · 즐겨찾기 카드 · 위젯 설정 목록)은 개역개정도 「개역개정」 을 적는다.
     2.1 에 새로 번역본이 섞인 목록(차트 최근 절 · 최근 장 · 가장 많이 쓴 장, 확인이 필요한 필기)은 **KJV · BSB 만** 약칭을 붙이고 개역개정은 생략한다(결정 17).
   - 위젯은 Domain 을 링크하지 않는다. 앱이 지정할 때 만든 참조 문자열을 payload 에 담아 쓴다.
6) **옮기지 않는 것:** 로그(`Logger` · `Log` · `print`) · `#if DEBUG` · `Debug` 폴더 · 프리뷰 · 컴포넌트 갤러리 · 분석 이벤트 이름 · 저장 키와 저장값(`@Shared` 키 · `FontCase` rawValue 등) ·
   메일 제목의 `UserFeedback` rawValue · 성경 본문(번역본 파일 그대로). 저장값에 한국어가 들어 있으면 표시용 이름(`localizedName(locale:)` · `title(locale:)`)을 따로 더한다.
7) **시험은 ko-KR 로 돈다.** 스킴의 시험 언어 · 지역이 `ko` · `KR` 로 고정돼 있다(`Workspace.swift` · `Project+Templates.swift` 의 `testLanguage` · `testRegion` — 손으로 만드는 스킴에도 같은 값을 넣는다).
   기존 한국어 단언은 그대로 둔다. 새로 만든 시뮬레이터는 기본 언어가 영어라, 고정하지 않으면 결과가 기기마다 달라진다.
   - 영어는 **언어를 실제로 고르는 경로**로 본다. `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
     `LocalizedStringResource(…, locale: Locale(identifier: "en"), bundle: .atURL(Bundle.module.bundleURL))` 를 `String(localized:)` 로 풀거나,
     locale 을 받는 API(`localizedName(locale:)` · `BibleReference.text(locale:)` · `Translation.displayName(locale:)` · 모듈 `…Catalog.string(_:locale:)`)를 쓴다.
   - 표시용 문구를 만드는 함수 · Copy 정적 멤버는 **`locale: Locale` 을 받는다(비옵셔널, 기본값 없음)** — 뷰는 환경 `locale`, 리듀서 · effect · 인프라는 `AppLanguage.displayLocale()`,
     시험은 `Locale(identifier: "en")` 등을 넘긴다(아래 9). locale 없는 편의 속성(`localizedName` · `text` · `displayName` · `fullName` · `FontCase.title` 등)과
     `Locale?` · nil(= 기기 언어) 경로는 없다 — 즉시 전환 단계 3(2026-10-13)에서 지웠고, 되살리지 않는다. 영어 문구 시험은 모듈의 영어 시험 파일(예 `DomainEnglishCopyTesting` · `CarveFeatureEnglishCopyTesting`)에 둔다.
   - 리듀서가 만드는 문구가 앱 안에서 고른 언어를 따르는지는 `withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() }` 안에서
     `@Shared(.appLanguageOverride)` 에 언어를 넣고 리듀서를 돌려 본다(예 `SettingsFeatureEnglishCopyTesting.reducerPopupFollowsInAppLanguage`). 고른 언어가 없으면 `displayLocale()` 은 시험 언어(ko-KR)다.
   - 시험 헬퍼는 자기 시험 파일 안에 둔다. 여러 모듈이 함께 쓰는 공용 시험 헬퍼는 새로 만들지 않는다.
8) **영어 문구는 짧고 평이하게 쓴다.** iPad 사이드바 · 팔레트처럼 폭이 좁은 곳에서 잘리지 않게 한다. 같은 한국어는 모듈이 달라도 같은 영어로 쓴다 —
   새 문구를 넣기 전에 다른 모듈 카탈로그에서 같은 한국어 키를 찾아 본다. 글꼴 표시 이름은 Domain `FontCase.title(locale:)` 하나만 쓴다
   (ko 「나눔명조」 · 「나눔고딕」 · 「나눔손글씨 꽃내음」, en 「Nanum Myeongjo」 · 「Nanum Gothic」 · 「Nanum Flower Scent」 — 번들 글꼴 파일의 패밀리 이름에 맞춘다, 결정 18).

---

9) **화면 언어는 환경 `locale` 이 정한다 — 앱 안에서 언어를 고르면 다시 시작하지 않고 바뀐다**(2026-10-13, 즉시 전환 단계 1 · 2 · 3).
   - 앱 루트(`AppCoordinatorView`)가 고른 언어(`appLanguageOverride`)로 환경 `locale` 을 바꾼다. 규칙은 `AppLanguage.displayLocale()` 하나라
     화면 문구와 리듀서가 만든 문구가 같은 언어다. 키 기반 `Text("…", bundle:)` 은 저절로 따라온다.
   - **뷰 = 환경 locale.** 뷰에서 미리 만드는 문구(카탈로그 도우미 · 표시용 함수 · 접근성 이름 · 컴포넌트에 넘기는 `String`)는 `@Environment(\.locale) private var locale` 을 읽어 넘긴다.
     그러면 SwiftUI 가 의존성을 알고 그 뷰를 다시 그린다. `Locale.current` · `.autoupdatingCurrent` 를 뷰에 쓰지 않는다. 본보기 `HeaderView` · `SettingsView` · `LanguageSettingsView`.
   - **리듀서 · effect · 인프라 = `AppLanguage.displayLocale()`.** 문구(알림 · 안내 · 결과 한 줄 · 대화상자)를 만들 때 한 번 얻어 쓴다. 상태 구조는 그대로라
     이미 만든 문구는 만든 때의 언어로 남는다 — 떠 있는 알림과 같고, 다시 만들 때 새 언어가 된다.
     저장되는 표시 문자열(위젯 payload 의 권 이름 · 참조, 백업 파일 이름, 의견 메일 본문 머리)도 쓰는 순간의 화면 언어다. 저장 키 · 저장 형식 · 분석 이벤트 이름 · 로그는 옮기지 않는다(6).
   - **새 코드는 상태에 의미 값을 두고, 뷰가 환경 locale 로 문장을 만드는 것을 권한다** — 그러면 떠 있는 안내도 언어를 바꾸면 바로 바뀐다.
     본보기 `ChapterCanvasArrivalFeature` 의 `ArrivalNotice`(상태) · `message(locale:)`(뷰가 부른다).
   - **표시 함수 = 비옵셔널 `Locale`.** 모듈 도우미 `…Catalog.string(_:locale:)` 와 Domain 표시 함수(`BibleReference.text(locale:)` · `BibleTitle.localizedName(locale:)` ·
     `Translation.displayName(locale:)` · `fullName(locale:)` · `FontCase.title(locale:)` · `UserFeedback.FeedbackType.localizedName(locale:)` · `BackupExportFileName.defaultName(for:timeZone:locale:)`)는
     locale 을 늘 받는다(7). 직접 `String(localized:)` 는 도우미 파일(`*Catalog.swift`)에만 둔다 — 실행 시작 때의 번들 언어로 굳는다.
   - 한 번만 만드는 정적 저장 프로퍼티(`static let`)에 문구를 담지 않는다 — 처음 부른 때의 언어로 굳는다. 처음 상태처럼 문구가 든 값은 부를 때마다 만든다
     (예 `UserFeedback.initialState` · `SendFeedbackFeature.State.initialState` — 본문 머리 「- 문의 내용:」).
   - **따로 만든 호스트에는 환경 locale 을 넣는다 — 만들 때와 갱신 때 모두.** 예: `ChapterCanvasView.updateUIViewController`(캔버스 컬럼),
     `TouchIgnoringContextMenu`(절 행 — 호스트를 Coordinator 에 붙잡고 언어가 바뀐 때만 `rootView` 를 다시 넣는다). `ImageRenderer` 는 요청에 locale 을 담는다.
   - 이미 떠 있는 알림은 표시된 순간의 언어로 남는다. 루트에서 `.id` 로 화면 전체를 다시 만들지 않는다 — 필사 화면이 장을 다시 읽어 캔버스 · undo 가 비워진다.
   - 남는 한계(시스템이 그리는 화면 · 위젯에 담은 참조 · UIKit 접근성 문구 등)는 설계 `docs/english-localization-design.md` §8-5 다.
   - 기계 검사: `localized_string_outside_catalog`(Sources 의 직접 `String(localized:)` — 도우미 `*Catalog.swift` · Debug · 프리뷰 · 갤러리 밖) ·
     `view_no_current_locale`(뷰 파일 `*View.swift` · `*View+*.swift` 의 `Locale.current` · `.autoupdatingCurrent`). 리듀서 · 인프라가 `displayLocale()` 을 쓰는지는 리뷰로 본다.

## 번역본 귀속 (결정 1 — 동결)

**영어 행은 권 이름(`titleName`)에 번역본 접두를 붙여 구분한다. SwiftData 스키마 · 마이그레이션 · CloudKit 설정은 바꾸지 않는다.**

| 행 | `titleName` | `translation` 열 | 읽을 때 번역본 |
|---|---|---|---|
| 개역개정 | `BibleTitle.rawValue`(예 `1-01Genesis.txt`) — 2.0 과 같다 | `.NKRV`(옛 행은 nil 일 수 있다) | NKRV |
| KJV · BSB | `"<Translation.rawValue>-<BibleTitle.rawValue>"`(예 `KJV-1-01Genesis.txt`) — 본문 리소스 파일 이름과 같다 | **늘 nil** | 접두의 번역본 |
| 접두나 권 이름을 모름 | — | — | 풀지 못함(nil) — 건너뛴다 |

1) SwiftData 의 `translation` 열(`BibleDrawing` · `BiblePageDrawing` · `FavoriteVerse` · `VerseDrawingVersion`)에는 `.NKRV` 나 nil 만 쓴다. **영어 값은 절대 쓰지 않는다** —
   이미 나간 2.0.0 기기가 모르는 열거값을 디코딩하다 죽을 수 있다(U3, 미검증). 구버전은 모르는 `titleName` 을 `BibleTitle(rawValue:)` 로 풀지 못해 건너뛴다 — 이 동작에 기댄다.
2) 행을 읽을 때 번역본은 **`titleName` 접두로 먼저 정한다.** 접두가 없으면 열이 nil 이든 `.NKRV` 든 NKRV 다.
3) **짓고 푸는 것은 Domain `StoredBookKey` 만 쓴다** — `titleName(for:)` · `titleName(title:translation:)` · `decode(_:)` · `translationColumn(for:)`.
   `titleName` 문자열을 직접 이어 붙이거나 자르지 않는다. 조회 술어의 `titleName == …` 도 `StoredBookKey.titleName(for:)` 로 짓는다. `"NKRV-"` 접두는 만들지 않는다.
4) 이 열 규칙은 SwiftData 행에만 걸린다. 동기화하지 않는 곳과 파일 형식에는 실제 번역본 값을 쓴다 — `@Shared(.appStorage("title"))` 의 `BibleChapter` JSON(`translation` 키) ·
   기기 안 초안 `VerseDraftKey` · 위젯 payload · 백업 파일의 `BackupVerseKey.translation`(영어 행은 `titleName` 접두에서 온 값).
5) **번역본은 장과 함께 나른다.** `BibleChapter.translation` 이 지금 번역본이고(`@Shared("title")` 에 저장된 장), `==` · `hash` 는 권 · 장 · 번역본 셋 다 본다.
   번역본을 함수마다 따로 인자로 받지 않는다. 기존 공개 시그니처에 번역본이 필요하면 `BibleChapter` 를 받는 경로로 흐르게 하거나 `translation: Translation = .NKRV` 기본값 인자를 더한다.
   옛 JSON(`translation` 키 없음)은 NKRV 로 읽는다.
6) `DrawingSchemaV*` 의 저장 속성 · `@Model` 정의 · 마이그레이션 플랜 · CloudKit 설정 · `ChapterLayoutSignature` · `DrawingLayoutMetadata` 는 바꾸지 않는다. init 인자 · 계산 속성 · 확장만 더한다.
- 기계 검사: lint 없음 — 리뷰와 시험으로 본다(`StoredBookKeyTesting` · `TranslationDrawingIsolationTesting` · `TranslationFavoriteDraftTesting` · `BackupTranslationRoundTripTesting` —
  같은 절의 번역본이 섞이지 않고, 영어 행의 열이 nil 이고, 개역개정 행 형식이 그대로인지).
- 실제 두 기기 공존(2.0.0 기기와 iCloud)은 설계 §9 M4 가 출시 전 관문으로 본다.

## 필사책 귀속 (2.2 회차별 필사책 — 동결)

**다른 필사책의 행은 권 이름(`titleName`) 앞에 필사책 접두를 붙여 구분한다. 기본 필사책 행은 지금 형식 그대로다. 필사책 정보(이름 · 상태 · 시각)는 V7 엔티티 `DrawingNotebook` 에 둔다.**
번역본 귀속과 같은 방식 · 같은 근거다. 결정의 원문과 이유는 설계 `docs/notebook-design.md`(「결정 n」 · 혼재 버전 규칙 ①~⑥)다.

| 행 | `titleName` | `translation` 열 | 읽을 때 필사책 |
|---|---|---|---|
| 기본 필사책(지금까지의 모든 필사) | 번역본 귀속 그대로 — `1-19Psalms.txt` · `KJV-1-19Psalms.txt` | 번역본 귀속 그대로 | `NotebookID.default` |
| 다른 필사책 | `"nb_" + NotebookID.rawValue + "~" + 기본 형식`(예 `nb_0f3a…~KJV-1-19Psalms.txt`) — rawValue 는 소문자 16진 32자리 | 번역본 귀속 그대로 — 필사책을 열에 적지 않는다 | 접두의 필사책 |
| 접두 형식이 틀림(대문자 · 길이 · `~` 없음 · `nb_default~`) | — | — | 풀지 못함(nil) — 건너뛴다 |

1) **혼재 버전 규칙(동결).** 같은 iCloud 를 2.0.0 · 2.1 기기가 함께 쓴다. 옛 앱은 `BibleDrawing` 을 `titleName ==` 로만 찾고 모르는 `titleName` 은 건너뛴다 — 이 동작에 기댄다.
   - ① 기본 필사책 행 형식(`titleName` · `translation` 열 · business id)을 바꾸지 않는다. 기존 행은 고치지 않는다.
   - ② 필사책을 `translation` 등 기존 열로 판정하지 않는다 — 옛 앱이 레코드에 없는 열을 스키마 기본값으로 채워 되올린다(2.1.0 출시 시험 EN-M4 관찰 ①).
   - ③ `FavoriteVerse` 에 필사책 접두를 쓰지 않는다(즐겨찾기 · 위젯은 필사책 공통 사본). V6 의 `VerseDrawingVersion` · `DrawingEraseEpoch` 에는 아무것도 쓰지 않는다(운영 배포 대상이 는다).
   - ④ `DrawingNotebook` 상태는 열거형 열이 아니라 String 열이고, 모르는 값 · nil 은 active 로 읽는다(`NotebookStatus(stored:)`) — 번역본 귀속 1) 의 U3 와 같은 이유.
   - ⑤ 백업은 `formatVersion` 2 로 쓴다. 2.2 는 1 · 2 를 모두 읽고 1 은 전부 기본 필사책이다. 2.1 은 형식 2 파일 전체를 거부하고 업데이트를 안내한다.
   - ⑥ 지운 필사책의 행이 늦게 오거나 메타데이터보다 행이 먼저 오면 「이름 없는 필사책」 으로 보인다 — 숨기거나 기본 필사책에 합치지 않는다.
2) **짓고 푸는 것은 Domain `StoredBookKey` 만 쓴다** — `titleName(for: NotebookChapter)` · `titleName(title:translation:notebook:)` · `decodeRow(_:)`(`StoredRowKey` — 권 · 번역본 · 필사책).
   `"nb_"` · `"~"` 를 직접 이어 붙이거나 자르지 않고, 조회 술어의 `titleName == …` 도 page 로 짓는다. 기본 필사책에 접두(`nb_default~`)를 만들지 않는다.
   옛 `titleName(for: BibleChapter)` · `titleName(title:translation:)` · `decode(_:)` 의 뜻은 「기본 필사책」 이고(옛 `decode` 는 접두 행에 nil) 과도기 뒤 지운다 — 새 코드는 부르지 않는다.
   기기 안 초안 파일 이름도 같은 토큰을 앞에 붙인다(기본 필사책은 지금 이름 그대로).
3) **저장 경로는 `NotebookChapter`(필사책 + 장)를 기본값 없는 인자로 나른다** — 저장소 · 캔버스 · 초안 · 이전 필사 · 탐색 칠하기 · 가져오기 · 백업.
   `NotebookChapter.init(notebook:chapter:)` 와 page · notebook 인자에 기본값(`.default`)을 두지 않는다 — 빠뜨린 곳이 조용히 기본 필사책에 쓰지 않고 컴파일 오류로 드러나게.
   `BibleChapter` 에 필사책 필드를 더하지 않는다(`==` 가 바뀌면 탐색 선택 비교가 흔들린다). 본문 · 탐색 선택 · 위젯은 `BibleChapter` 그대로다.
   DTO 에 더하는 필드(`VerseDrawingSnapshot.notebook` · `DrawingActivity.page`)만 init 끝에 기본값을 둘 수 있다.
4) **지금 필사책은 `@Shared(.currentNotebookID)`**(`.appStorage("currentNotebookID")`, 기본 「default」, 기기마다 — 동기화하지 않는다). 읽을 때 `NotebookID(rawValue:)` 가 nil 이거나
   목록에 없으면(다른 기기에서 지움) 기본이다. 위젯 · 필사 알림 · 즐겨찾기에서 여는 장은 지금 필사책으로 연다.
5) **표시.** 필사책 이름은 사용자 입력이라 옮기지 않는다(`Text(verbatim:)` 꼴). 메타데이터에 이름이 없는 기본 필사책은 화면 언어의 「첫 번째 필사」(en 「First Notebook」),
   그 밖의 이름 없는 필사책은 「이름 없는 필사책」(en 「Untitled Notebook」). 영어 용어: 필사 = Writing, 필사책 = Notebook, 책장 = Notebooks.
   이름 제안은 ko 「두 번째 필사」 … 「열 번째 필사」 · 「11번째 필사」 꼴, en 「Notebook 2」 꼴 — 서수를 문자열로 잇지 않고 카탈로그로 쓴다(3). 쓴 절 수는 복수형, 시작 월은 환경 locale 서식(4).
   기존 문서의 「회차」 는 절의 보관 행(`isPresent`)이다 — 필사책을 코드 · 문서 · 화면에서 「회차」 라고 부르지 않는다.
- 기계 검사: lint 없음 — 리뷰와 시험으로 본다(`StoredBookKeyNotebookTesting` · `NotebookIDTesting` · `DrawingSchemaV7MigrationTesting` · `NotebookDrawingIsolationTesting` ·
  `NotebookRepositoryTesting` · `NotebookDraftTesting` · `BackupNotebookRoundTripTesting` · `NotebookSwitchTesting` — 기본 필사책 행 형식이 옛 함수와 같고, 같은 절의 필사책이 섞이지 않고,
  옛 술어(`titleName == rawValue`)로 찾으면 접두 행이 잡히지 않는지).
- 실제 두 기기 공존(2.0.0 · 2.1 기기와 iCloud)은 설계 §9 공존 C1 · C2 가 출시 전 관문으로 본다.

---

## Checklist (리뷰)
- 새 화면 문구에 번들이 있는가(`.module` · 앱 · 위젯은 `.main`), ko · en 이 모두 `translated` 인가
- 수 · 날짜를 이어 붙이거나 `ko_KR` 로 고정하지 않았는가
- 참조 · 권 이름을 `BibleReference.text(locale:)` · `localizedName(locale:)` 으로 만들었는가, 약칭 규칙(5)을 지켰는가
- SwiftData 행에 영어 `translation` 값을 쓰지 않았는가, `titleName` 을 `StoredBookKey` 로만 짓고 풀었는가
- 필사책: 기본 필사책 행 형식을 그대로 두고 필사책을 열이 아니라 `StoredBookKey` 접두로만 갈랐는가, 저장 경로가 `NotebookChapter` 를 기본값 없이 나르는가, `FavoriteVerse` · V6 엔티티에 필사책을 쓰지 않았는가, 필사책 이름(사용자 입력)을 옮기지 않았는가
- 영어 시험이 언어를 실제로 골랐는가(`String(localized:bundle:locale:)` 만으로는 영어가 나오지 않는다)
- 뷰의 미리 만든 문구가 환경 `locale` 을 넘기는가, 따로 만든 호스트 · 렌더러에 locale 을 넣었는가(9)
- 리듀서 · effect · 인프라가 문구를 `AppLanguage.displayLocale()` 로 만드는가, 새 표시 함수가 비옵셔널 `locale: Locale` 을 받는가,
  문구를 `static let` 에 담아 처음 언어로 굳히지 않았는가(9)
