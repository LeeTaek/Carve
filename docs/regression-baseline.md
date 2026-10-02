# 회귀 기준선

> 회귀 기준선 **1187** — `Carve-Workspace` 전체 회귀의 **통과 수**(Xcode 27 · iPad mini (A17 Pro) · iPadOS 26.2). **통과 수가 줄면 회귀다.**
> 이 파일이 기준선의 유일한 원본이다. [AGENTS.md](../AGENTS.md) · [설계 문서](./single-canvas-design.md) · [런북](./phase-0a-d-device-test.md)은 여기를 가리킨다.

## 현재 값 (2026-10-02, 커밋 `8edd0c89`, Xcode 27.0 27A266a · Swift 6.4 · 언어 모드 6)

| iPadOS 런타임 | 기기 | 통과 | 실패 | 건너뜀 | 예상 실패 | 총 |
|---|---|---:|---:|---:|---:|---:|
| 26.2 | iPad mini (A17 Pro) | 1187 | 0 | 8 | 4 | 1199 |
| 27.0 | iPad mini (A17 Pro) | 1186 | 0 | 9 | 4 | 1199 |
| 18.6 | iPad mini (A17 Pro) | 1187 | 0 | 8 | 4 | 1199 |
| 17.5 | iPad mini (6th generation) | 1186 | 0 | 9 | 4 | 1199 |

- 네 런타임은 한 번의 `xcodebuild test`(destination 4개, 동시 2대)로 돌렸고, 수는 xcresult 의 Test Case → Device 단위로 셌다(summary 의 기기별 수는 매개변수 케이스까지 센다).
- 17.5 · 27.0 에서만 하나 더 건너뛰는 것은 `LocalStoreLoadFailureTesting/v1OnlyContainerDropsDrawingSavesSilently()` 다(런타임 조건).
- 건너뜀 8 은 표준 실행에서 늘 건너뛰는 기기 스모크 · 장 이력 메뉴 · 스크롤 UI 시험 6개와 `RemoveAdsStoreKitUITests` 2개(`CarveApp-StoreKit` 스킴에서만 돈다)다.
- 1186 → 1187: Swift 언어 모드 6 전환 DAG 의 N-Canvas 이력 복원 시험 +1(`SingleCanvasRollbackTesting.restoredSnapshotKeepsRowAddress`).
- Xcode 26.x 는 이 전환부터 지원하지 않는다(AGENTS.md 「툴체인 제약」). 그 전 값은 아래 이력에 있다.

## 고치는 법

- 전체 회귀를 새로 돌려 통과 수가 늘면 위 요약 줄과 표를 고치고 아래 이력에 한 줄 더한다. **이 파일만 고친다.**
- 수치를 낮추는 것은 테스트를 의도적으로 지운 커밋에서만 한다(`ios-verify` 는 `--full --accept-baseline`).
- `ios-verify` 는 이 파일의 첫 「회귀 기준선 **N**」 을 정규식으로 읽는다. 요약 줄의 형식을 바꾸지 않는다.

## 이력

rev.37(2026-09-29) 까지의 이력은 [설계 문서](./single-canvas-design.md) §19-4-2 에 있다.

| 날짜 | 기준선 | 커밋 | 내용 |
|---|---:|---|---|
| 2026-09-29 | 1112 | `c3c320ad` | 설정 「의견 보내기」 · 「앱 버전」 시험 9 추가(설계 rev.37 과 같은 값) |
| 2026-09-30 | 1112 | `b9a8b438` | 기준선 원본을 이 파일로 옮김. 값은 그대로 |
| 2026-10-01 | 1175 | `8853b0ac` | release/2.0.1 본문 파싱 시험 +22, `CarveAppTest` +41(AI 적합성 2차 묶음 DAG 통합 브랜치 게이트) |
| 2026-10-02 | 1186 | `795746bd` | develop 역병합 — Xcode 27 빌드의 `.appStorage` 해석 핫픽스, 저장 형식 · JSON 되돌림 시험 +11 |
| 2026-10-02 | 1187 | `8edd0c89` | Swift 언어 모드 6 전환(Xcode 27 기준으로 옮김, 26.3 비교 기준 내림) — N-Canvas 이력 복원 시험 +1. 17.5 · 18.6 · 26.2 · 27.0 실패 0 |
