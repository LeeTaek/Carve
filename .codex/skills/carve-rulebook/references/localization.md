# Localization Rules (Carve)

## Goal
- 앱 화면을 **기기 언어 · iOS 앱별 언어**(ko · en)로 보인다. 영어 앱 이름은 **Carve** 다.
- 설정 › 화면 › 언어에서 앱 안에서도 바꾼다(2026-10-13). 저장은 iOS 앱별 언어와 같은 값(앱 도메인 `AppleLanguages`, ClientInterfaces `AppLanguageClient`)이고,
  지금 실행은 앱 루트가 환경 `locale` 을 바꿔 키 기반 `Text("…", bundle:)` 을 바로 바꾼다(`appLanguageOverride`). 미리 만든 `String` 은 다음 실행부터 바뀐다 —
  그래서 **새 화면 문구는 키 기반 `Text("…", bundle:)` 를 우선한다.** `String` 경로를 환경 locale 에 맞추는 규칙은 즉시 전환 단계 2 에서 정한다.
- 영어 성경(KJV · BSB) 필사와 개역개정 필사를 **섞지 않는다** — 이미 나간 2.0.0 · 1.3.0 기기와 같은 iCloud 저장소를 쓴다.
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
- `String` 으로 꺼내는 도우미는 모듈마다 하나다 — `DomainCatalog` · `CarveFeatureCatalog` · `ChartCatalog` · `SettingsCatalog` 의 `string(_:locale:)`.
  locale 이 nil 이면 `String(localized:bundle: .module)` 그대로이고, 값이 있으면 그 언어로 푼다(아래 7).

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
   | `String` 으로 흐르는 문구(Copy enum · 컴포넌트 인자 · Popup · Action 페이로드 · UIKit 라벨) | `String(localized: "…", bundle: .module, comment: "…")` 또는 그 모듈의 `…Catalog.string` |
   | TCA 알림 · 확인창 | `TextState("…", bundle: .module)` · `ButtonState { TextState("…", bundle: .module) }` |
   | App · 위젯 | 같은 형식에 `bundle: .main` |
   | 옮기지 않는 글자(이미 현지화된 값 · 사용자 내용 · Debug) | `Text(verbatim:)` |

   - `comment` 에는 그 문구가 어디에 나오는지 한 줄로 적는다 — 영어 문구 검토(결정 7)에서 화면을 찾는 근거다.
   - 기계 검사: `localized_text_needs_bundle`(`.swiftlint.yml` `custom_rules`, error) — 한글이 든 `Text` · `Button` · `Label` · `TextState` 리터럴에 `bundle:` 이 없는 경우. Debug 폴더 · 프리뷰 · 컴포넌트 갤러리는 `excluded` 다.
     `String(localized:)` 의 번들 누락은 이 규칙이 보지 않으므로 리뷰로 본다.
3) **수 · 단위는 카탈로그 형식 문자열과 복수형 변형으로 쓴다.** 장 · 절 · 개 · N번째를 문자열로 이어 붙이지 않는다. en 은 `one` · `other` 변형을 채운다(예 `%lld절` → 「%lld verse」 · 「%lld verses」).
   한국어 수사(「하루」 · 「이틀」)는 en 에서 숫자형으로 쓴다. 여러 값을 넣는 문구는 위치 지정 인자(`%1$@ %2$lld`)로 언어마다 순서를 바꿀 수 있게 한다.
4) **날짜 · 수 서식은 기기 로케일을 따른다.** `Date.FormatStyle(locale: locale ?? .autoupdatingCurrent)` · `.number…locale(…)` 처럼 쓴다. 고정 `ko_KR` `DateFormatter` 를 새로 만들지 않는다.
   리듀서의 현재 시각은 여전히 `@Dependency(\.date)` 다(testing.md).
5) **권 이름 · 장절 표기는 기기 언어를 따른다 — 번역본 언어가 아니다**(결정 3). 한국어 기기는 KJV 를 봐도 「창세기 1장 1절」, 영어 기기는 개역개정을 봐도 「Genesis 1:1」 이다.
   - 참조 문자열은 `BibleReference` 로만 만든다(`.text` · `.text(locale:)`). 권 이름은 `BibleTitle.localizedName`, 번역본 이름은 `Translation.displayName`(약칭) · `fullName` 이다.
     「\(권) \(장)장」 처럼 손으로 잇지 않는다. `koreanTitle()` 은 Domain 카탈로그 키의 원문이고, 제품 코드에서는 Debug 에만 남았다.
   - 번역본 약칭은 참조 뒤에 「 · KJV」 처럼 붙인다. 2.0 부터 번역본을 적어 온 곳(이미지 저장의 출처 · 위젯 · 필사 헤더 · 즐겨찾기 카드 · 위젯 설정 목록)은 개역개정도 「개역개정」 을 적는다.
     2.1 에 새로 번역본이 섞인 목록(차트 최근 절 · 최근 장 · 가장 많이 쓴 장, 확인이 필요한 필기)은 **KJV · BSB 만** 약칭을 붙이고 개역개정은 생략한다(결정 17).
   - 위젯은 Domain 을 링크하지 않는다. 앱이 지정할 때 만든 참조 문자열을 payload 에 담아 쓴다.
6) **옮기지 않는 것:** 로그(`Logger` · `Log` · `print`) · `#if DEBUG` · `Debug` 폴더 · 프리뷰 · 컴포넌트 갤러리 · 분석 이벤트 이름 · 저장 키와 저장값(`@Shared` 키 · `FontCase` rawValue 등) ·
   메일 제목의 `UserFeedback` rawValue · 성경 본문(번역본 파일 그대로). 저장값에 한국어가 들어 있으면 표시용 이름(`localizedName` · `title(locale:)`)을 따로 더한다.
7) **시험은 ko-KR 로 돈다.** 스킴의 시험 언어 · 지역이 `ko` · `KR` 로 고정돼 있다(`Workspace.swift` · `Project+Templates.swift` 의 `testLanguage` · `testRegion` — 손으로 만드는 스킴에도 같은 값을 넣는다).
   기존 한국어 단언은 그대로 둔다. 새로 만든 시뮬레이터는 기본 언어가 영어라, 고정하지 않으면 결과가 기기마다 달라진다.
   - 영어는 **언어를 실제로 고르는 경로**로 본다. `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
     `LocalizedStringResource(…, locale: Locale(identifier: "en"), bundle: .atURL(Bundle.module.bundleURL))` 를 `String(localized:)` 로 풀거나,
     locale 을 받는 API(`localizedName(locale:)` · `BibleReference.text(locale:)` · `Translation.displayName(locale:)` · 모듈 `…Catalog.string(_:locale:)`)를 쓴다.
   - 표시용 문구를 만드는 함수는 **`locale: Locale` 을 받는다(기본값 없음)** — 뷰는 환경 `locale` 을, 시험은 `Locale(identifier: "en")` 등을 넘긴다(아래 9).
     옛 함수의 `locale: Locale? = nil`(nil = 기기 언어)은 즉시 전환 단계 3 에서 없앤다 — 새 코드는 nil 경로를 쓰지 않는다. 영어 문구 시험은 모듈의 영어 시험 파일(예 `DomainEnglishCopyTesting` · `CarveFeatureEnglishCopyTesting`)에 둔다.
   - 시험 헬퍼는 자기 시험 파일 안에 둔다. 여러 모듈이 함께 쓰는 공용 시험 헬퍼는 새로 만들지 않는다.
8) **영어 문구는 짧고 평이하게 쓴다.** iPad 사이드바 · 팔레트처럼 폭이 좁은 곳에서 잘리지 않게 한다. 같은 한국어는 모듈이 달라도 같은 영어로 쓴다 —
   새 문구를 넣기 전에 다른 모듈 카탈로그에서 같은 한국어 키를 찾아 본다. 글꼴 표시 이름은 Domain `FontCase.title(locale:)` 하나만 쓴다
   (ko 「나눔명조」 · 「나눔고딕」 · 「나눔손글씨 꽃내음」, en 「Nanum Myeongjo」 · 「Nanum Gothic」 · 「Nanum Flower Scent」 — 번들 글꼴 파일의 패밀리 이름에 맞춘다, 결정 18).

---

9) **화면 언어는 환경 `locale` 이 정한다 — 앱 안에서 언어를 고르면 다시 시작하지 않고 바뀐다**(2026-10-13, 즉시 전환 단계 1 · 2).
   - 앱 루트(`AppCoordinatorView`)가 고른 언어(`appLanguageOverride`)로 환경 `locale` 을 바꾼다. 키 기반 `Text("…", bundle:)` 은 저절로 따라온다.
   - 뷰에서 미리 만드는 문구(카탈로그 도우미 · 표시용 함수 · 접근성 이름 · 컴포넌트에 넘기는 `String`)는 `@Environment(\.locale) private var locale` 을 읽어 넘긴다.
     그러면 SwiftUI 가 의존성을 알고 그 뷰를 다시 그린다. `Locale.current` · `.autoupdatingCurrent` 를 뷰 문구에 쓰지 않는다.
   - **따로 만든 호스트에는 환경 locale 을 넣는다 — 만들 때와 갱신 때 모두.** 예: `ChapterCanvasView.updateUIViewController`(캔버스 컬럼),
     `TouchIgnoringContextMenu`(절 행 — 호스트를 Coordinator 에 붙잡고 언어가 바뀐 때만 `rootView` 를 다시 넣는다). `ImageRenderer` 는 요청에 locale 을 담는다.
   - 리듀서 · effect · Domain 은 한 번 얻은 locale 을 인자로 받고, 상태에는 해석한 문자열 대신 의미 값을 둔다(단계 3).
   - 이미 떠 있는 알림은 표시된 순간의 언어로 남는다. 루트에서 `.id` 로 화면 전체를 다시 만들지 않는다 — 필사 화면이 장을 다시 읽어 캔버스 · undo 가 비워진다.

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

---

## Checklist (리뷰)
- 새 화면 문구에 번들이 있는가(`.module` · 앱 · 위젯은 `.main`), ko · en 이 모두 `translated` 인가
- 수 · 날짜를 이어 붙이거나 `ko_KR` 로 고정하지 않았는가
- 참조 · 권 이름을 `BibleReference` · `localizedName` 으로 만들었는가, 약칭 규칙(5)을 지켰는가
- SwiftData 행에 영어 `translation` 값을 쓰지 않았는가, `titleName` 을 `StoredBookKey` 로만 짓고 풀었는가
- 영어 시험이 언어를 실제로 골랐는가(`String(localized:bundle:locale:)` 만으로는 영어가 나오지 않는다)
- 뷰의 미리 만든 문구가 환경 `locale` 을 넘기는가, 따로 만든 호스트 · 렌더러에 locale 을 넣었는가(9)
