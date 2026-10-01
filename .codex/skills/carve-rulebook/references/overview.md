# Carve Rulebook Overview

## Project identity
- iPad 전용 성경 필사 앱
- PencilKit 기반 드로잉 (UIKit bridge)
- 아키텍처: TCA + MicroArchitecture
- 빌드: Tuist
- 데이터: SwiftData + CloudKit

## MicroArchitecture (Decision)
목표: 리듀서(State · Action · reduce 본문)가 UIKit · PencilKit · SwiftData · 파일 같은 인프라에 직접 의존하지 않도록 “경계”를 강제한다.
경계는 모듈이 아니라 리듀서다 — 같은 모듈 안의 브리지 · 코덱 · 뷰는 인프라를 알아도 된다(SKILL.md 규칙 3 · 4, `.swiftlint.yml` `custom_rules` 가 error 로 검사).

이 룰북은 “운영 앱(앱스토어 배포)”이면서 “스터디 목적”을 함께 만족하도록, 다음 두 가지를 동시에 지향한다.
- 운영 안정성: 코드 일관성과 디버깅 가능성을 최우선으로 한다.
- 학습 확장성: 필요 시 대안을 비교하되, 최종 적용은 룰북 규칙을 따른다.

### Layer guideline
- Feature: State/Action/Reducer + View(SwiftUI). UI 이벤트를 Action으로 변환하고 상태를 표현한다. PencilKit 은 같은 모듈의 브리지와 `Drawing/` 코덱이 맡는다(pencilkit.md).
- Domain: 모델 · 정책 · 본문, SwiftData 스키마와 저장소(`Sources/SwiftData/`), 동기화. Feature 에는 저장소 계약과 DTO 만 보인다(swiftdata.md).
- ClientInterfaces: 외부 클라이언트의 프로토콜과 미구현 기본값 · 공유 키를 정의한다.
- App(조립): 실제 클라이언트 구현(`App/CarveApp/Sources/Infrastructure`)을 `App.swift` 의 `withDependencies` 로 넣고, 화면 사이 이동(`AppCoordinatorFeature`)을 맡는다.

## Module map
모듈 지도 · 의존 방향 · 본보기 파일 · 용어의 원본은 AGENTS.md 「아키텍처」 다(「모듈 지도」 · 「본보기 파일」 · 「용어」). 여기에 따로 적지 않는다.

## Conflict resolution
- 룰북 규칙이 일반적인 TCA “정석”보다 우선한다.
- 외부 스킬 제안과 충돌 시: 룰북 적용 + 충돌 이유 1~2줄 설명

## Naming & documentation conventions
- Feature 타입: `SomethingFeature` / View 타입: `SomethingView` / Client 타입: `SomethingClient` 또는 `SomethingRepository` 형태를 기본으로 한다.
- View에서 접근하는 Action은 ViewAction 기능을 적용한다.
- 주석 규칙:
  - State의 주요 프로퍼티는 목적을 1줄로 주석 처리한다.
  - Action의 각 케이스는 “언제 발생하는 이벤트인지”를 1줄로 주석 처리한다.
  - 메서드(특히 effect를 트리거하거나 외부 의존성을 호출하는 함수)는 역할/부작용을 간단히 남긴다.

## Geometry & layout principle
- 좌표 영역(writingRect · captureRect · 밑줄 anchor · 높이)은 단일 소스 `ChapterLayoutBuilder`(Domain)에서만 계산하고, Feature는 계산 결과(`ChapterLayout`)만 사용한다.
- 드로잉에 transform(`columnOrigin` 평행이동 · reflow · `storageOrigin` localize)을 적용하는 곳은 `DrawingCodec` 하나다. 기준 좌표계 정의는 pencilkit.md 「좌표계 정의」.
- 회전/리사이즈(iPad) 이슈 재현을 위해 debug overlay 또는 debug log를 쉽게 켜고 끌 수 있어야 한다(`-ChapterLayoutOverlay` 등, `docs/device-simulator-verification.md`).

## App Store 제출 — 필수 사유 API
- 규칙: 필수 사유 API(required reason API)를 새로 쓰면 같은 변경에서 앱 매니페스트 `App/CarveApp/Support/PrivacyInfo.xcprivacy` 의 `NSPrivacyAccessedAPITypes` 에
  그 범주와 사유가 있는지 확인하고, 없으면 더한다.
  - 대상: 파일 속성(`FileManager.attributesOfItem` · `resourceValues` 의 날짜 키 — 범주 `NSPrivacyAccessedAPICategoryFileTimestamp`), 시스템 부팅 시간, 디스크 공간, 활성 키보드, UserDefaults 계열
  - 지금 선언: UserDefaults `CA92.1` · 파일 타임스탬프 `C617.1`(앱 컨테이너 안 파일)
- 이유: 선언이 없으면 App Store 업로드 때 ITMS-91053 경고 · 거절이 난다. 코드 리뷰나 회귀 시험으로는 잡히지 않는다.
- 확인: `plutil -p App/CarveApp/Support/PrivacyInfo.xcprivacy` 로 선언을 보고, 바꾼 코드에서 위 API 를 찾는다. 매니페스트는 `makeAppTarget`(`Plugins/ProjectDescriptionHelpers/Target+Templates.swift`)이 앱 번들에 넣는다.
  위젯 익스텐션(`CarveWidget`)에는 매니페스트가 없다 — 위젯에서 이런 API 를 쓰게 되면 위젯에도 매니페스트를 더한다.
- 기계 검사: 없음(리뷰).

## Output expectation
응답은 항상:
1) 결론(추천 구조)
2) 스케치(State/Action/Reducer)
3) 테스트/리스크
4) 체크리스트
순으로 제시한다.
