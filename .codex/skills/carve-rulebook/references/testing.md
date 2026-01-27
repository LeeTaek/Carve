# Testing Rules (Carve)

## Goal
- 운영 앱(배포) 품질을 지키기 위해 핵심 로직을 자동화된 테스트로 보호한다.
- 스터디 목적을 위해, 테스트를 “나중에”가 아니라 Feature 설계 과정에 함께 포함한다.
- 현재 Domain 모듈에서 SwiftData 관련 테스트에 사용 중인 Testing 프레임워크를 확장하여
  Domain뿐 아니라 Feature(Reducer)와 네비게이션(AppCoordinator)까지 커버한다.

## Current state
- Domain 모듈에서 SwiftData 마이그레이션/저장 로직 중심의 테스트가 일부 존재한다.
- 추후 목표:
  - Feature(Reducer) 테스트를 Testing + TCA TestStore로 확대
  - AppCoordinator(Feature 간 네비게이션) 테스트 추가

## Testing layers
### 1) Domain unit tests
- 순수 로직/정책/유즈케이스를 검증한다.
- 외부 시스템(SwiftData/PencilKit/파일 I/O)은 직접 다루지 않거나 최소 boundary로만 검증한다.

### 2) Persistence tests (SwiftData)
- SwiftData 스키마/마이그레이션/저장·조회 규칙을 검증한다.
- 테스트는 가능한 한 임시 컨테이너/파일 URL 또는 in-memory 설정으로 독립적으로 수행한다.

### 3) Feature reducer tests (TCA)
- Reducer의 상태 변화와 Effect 트리거를 검증한다.
- 의존성은 Dependencies로 주입하고, 테스트에서는 mock/in-memory 구현으로 치환한다.

## Preferred tools
- 기본 테스트 프레임워크: Testing
- Feature(Reducer) 테스트: TCA TestStore + Testing
- 의존성 주입: Dependencies (withDependencies로 주입/오버라이드)

## Naming & documentation
- 테스트 함수명은 “시나리오-기대결과”가 드러나게 작성한다.
- 변수명은 2글자 이상을 기본으로 한다.
- Arrange/Act/Assert(Given/When/Then) 블록을 분리하고, 중요한 의도는 1줄 주석으로 남긴다.

## SwiftData testing guideline
- 테스트마다 고유한 ModelConfiguration(url:) 또는 in-memory 설정으로 상호 간섭을 차단한다.
- 마이그레이션 테스트는 다음 구조를 따른다.
  1) V1 컨테이너 생성 → 데이터 저장
  2) 동일 URL로 최신 컨테이너 생성 + migrationPlan 적용
  3) 최신 컨텍스트 fetch → 결과 일치 검증
- teardown(삭제/파일 정리)은 테스트 안정성을 위해 반드시 수행한다.

## Feature reducer testing guideline
- State 변화: Action 입력에 따른 상태 변경
- Effect 트리거: 특정 Action이 dependency 호출을 발생시키는지
- Cancellation: debounce/저장 작업이 취소/대체되는지(필요한 경우)

## Navigation testing guideline (AppCoordinator)
- child 이벤트 입력 → root 전환이 발생하는지
- child 이벤트 입력 → path.append / path.removeLast가 올바른지
- pop 후 특정 화면으로 이동시키는 send가 필요한 경우 함께 검증

## Geometry related tests (추천)
- verse rect 계산
- changedRect → verse 매핑
- clip 영역(inset/lineHeight 보정 포함) 계산

## Minimum bar
- 새 Feature 추가/리팩터링 시 Reducer 테스트 1개 이상
- SwiftData 스키마 변경 시 마이그레이션(또는 저장/조회) 테스트 1개 이상
- AppCoordinator path 목적지 추가 시 네비게이션 테스트 1개 이상

## Test writing checklist
- [ ] 테스트는 독립적으로 실행 가능해야 한다(순서 의존 금지)
- [ ] 외부 의존성은 Dependencies로 주입/대체한다
- [ ] teardown(삭제/파일 정리)을 수행한다
- [ ] 실패 시 원인 파악이 쉽도록 Given/When/Then을 명확히 나눈다
