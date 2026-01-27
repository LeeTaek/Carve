# Carve Rulebook Overview

## Project identity
- iPad 전용 성경 필사 앱
- PencilKit 기반 드로잉 (UIKit bridge)
- 아키텍처: TCA + MicroArchitecture
- 빌드: Tuist
- 데이터: SwiftData + CloudKit

## MicroArchitecture (Decision)
목표: Feature가 UIKit/DB/파일 같은 인프라에 직접 의존하지 않도록 “경계”를 강제한다.

이 룰북은 “운영 앱(앱스토어 배포)”이면서 “스터디 목적”을 함께 만족하도록, 다음 두 가지를 동시에 지향한다.
- 운영 안정성: 코드 일관성과 디버깅 가능성을 최우선으로 한다.
- 학습 확장성: 필요 시 대안을 비교하되, 최종 적용은 룰북 규칙을 따른다.

### Layer guideline
- Feature: State/Action/Reducer + View(SwiftUI). UI 이벤트를 Action으로 변환하고 상태를 표현한다.
- Domain: 순수 모델/정책/유즈케이스. 외부 프레임워크 의존을 최소화한다.
- ClientInterfaces: 외부 의존성을 추상화한 계약(프로토콜/DTO)을 정의한다.
- Client(Implementation): PencilKit/SwiftData/파일 I/O 등 외부 시스템을 캡슐화한 구현체를 둔다.

## Current module map (Tuist targets)
현재 레포는 Tuist 기반 모듈화로 구성되어 있으며, 다음 모듈명을 기준으로 대화를 진행한다.
- CarveApp: Composition Root. 의존성 조립과 앱 엔트리 포인트를 담당한다.
- CarveFeature: 앱의 핵심 Feature 모음(TCA).
- SettingsFeature / ChartFeature: 독립 Feature 모듈(TCA).
- UIComponents: 재사용 UI 컴포넌트/스타일.
- Domain: 도메인 모델/정책. (현재 일부 SwiftData 관련 코드가 포함될 수 있으며, 추후 분리 가능성을 열어둔다.)
- ClientInterfaces: 외부 의존성 인터페이스(프로토콜/DTO).
- Resources / CarveToolkit: 리소스/공용 유틸.

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
- verse rect / underline rect / changedRect 등 geometry 값의 기준 좌표계를 문서화하고, 변환(스크롤/스케일/회전)은 한 곳에서만 수행한다.
- 좌표/레이아웃 계산은 단일 소스(예: VerseLayoutEngine)에서만 수행하고, Feature는 계산 결과만 사용한다.
- 회전/리사이즈(iPad) 이슈 재현을 위해 debug overlay 또는 debug log를 쉽게 켜고 끌 수 있어야 한다.

## Output expectation
응답은 항상:
1) 결론(추천 구조)
2) 스케치(State/Action/Reducer)
3) 테스트/리스크
4) 체크리스트
순으로 제시한다.
