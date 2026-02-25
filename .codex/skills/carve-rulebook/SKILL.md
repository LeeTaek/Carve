---
name: carve-rulebook
description: Carve(iPad 성경 필사 앱)에서 TCA + MicroArchitecture + Tuist + SwiftData + PencilKit 규칙을 우선 적용해 Feature 설계/리팩터링/테스트 방향을 제안한다.
---

## Operating mode
- 이 스킬의 규칙은 일반적인 TCA “정석”보다 우선한다.
- 답변은 “우리 프로젝트 기준 결론 → 스케치 → 테스트/리스크” 순서로 제시한다.
- 코드가 필요하면 전체 파일을 갈아엎기보다 “패턴 설명 + 짧은 예시”를 우선한다.
- 외부 스킬의 제안이 이 룰북과 충돌하면, 룰북을 우선 적용하고 충돌 이유를 1~2줄로 설명한다.

## Non-negotiables (우선순위 규칙)
1) MicroArchitecture의 경계(모듈/레이어)가 최우선이다.
2) 사이드이펙트는 Dependency + Effect로만 나간다. View는 직접 I/O를 하지 않는다.
3) PencilKit(UIKit) 브리지는 어댑터/클라이언트로 캡슐화하고, Feature는 UIKit 타입에 직접 의존하지 않는다.
4) SwiftData 접근은 의도적으로 한 곳(Repository/Client)으로 모으고, Feature에서 ModelContext를 직접 다루지 않는다.
5) 변수명은 최소 2글자 이상을 원칙으로 한다.

## Output format (응답 포맷)
- 결론: 추천 구조 5~10줄
- 스케치: State/Action/Reducer의 형태(필요 시 Dependency 포함)
- 테스트: 테스트 포인트 3개 + 실패/리스크 2개
- 마지막: “우리 룰” 관점에서 체크리스트

## References
- ./references/overview.md
- ./references/pencilkit.md
- ./references/swiftdata.md
- ./references/navigation.md
- ./references/testing.md


## Documentation rules (Comments)
- State의 주요 프로퍼티(화면 동작/도메인 의미가 있는 것)는 목적을 1줄로 주석 처리한다.
- Action의 각 케이스는 “언제 발생하는 이벤트인지”를 1줄로 주석 처리한다.
- 메서드(특히 effect를 트리거하거나 외부 의존성을 호출하는 함수)는
  1) 역할, 2) 입력/출력, 3) 부작용 여부를 간단히 주석으로 남긴다.
