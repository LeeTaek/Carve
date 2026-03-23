---
name: 🐞 Bug report
about: 사용자 문제/오류/크래시 제보 및 재현 기록
title: "[Bug] "
labels: ["status:needs-repro", "prio:p2", "go:test"]
assignees: []
---

## 요약
- 무엇이 문제인지 한 줄로:

## 재현 단계 (Repro)
1.
2.
3.

## 기대 결과 (Expected)
-

## 실제 결과 (Actual)
-

## 환경 (Environment)
- App version:
- iOS/iPadOS:
- Device:
- Locale:

## 증거 (Evidence)
- 스크린샷/영상:
- 로그/에러 메시지:
- 관련 링크(Sentry/Crashlytics 등):

## 영향 범위
- area 라벨 후보: (예: area:carve / area:settings / area:domain / area:infra / area:build-ci)

## 테스트 계획 (Test plan)
> 버그를 고치면서 회귀 방지 테스트를 함께 추가하고 싶을 때 작성.

### 어떤 테스트를 추가할까?
- [ ] Unit test (순수 로직)
- [ ] Reducer test (TCA TestStore)
- [ ] Integration test (SwiftData/파일/네트워크 등)
- [ ] UI test

### 재현/검증 시나리오를 테스트로 옮기기
- Given:
- When:
- Then:

### 완료 조건 (Definition of Done)
- [ ] 재현 케이스에서 더 이상 발생하지 않는다
- [ ] 회귀 방지 테스트가 추가되었다 (또는 테스트 추가가 불가능한 이유를 기록했다)
- [ ] 관련 이슈/에러 로그(AnalyticsErrorId 등)와 연결해 추적 가능하다

## 체크리스트
- [ ] 재현 단계가 구체적이다
- [ ] 기대/실제 결과가 명확하다
- [ ] 환경 정보가 포함되어 있다
- [ ] 로그/스크린샷 등 증거가 있다 (없으면 status:needs-log 유지)
- [ ] (선택) 회귀 방지 테스트를 추가했다 (또는 추가가 어려운 이유를 기록했다)
