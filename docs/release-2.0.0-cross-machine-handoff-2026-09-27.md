# Carve 2.0.0 metadata·소유권 작업: 다른 Mac 인계 (2026-09-27)

> **2026-09-28 갱신(다른 Mac · Xcode 26.3):** HEAD가 Xcode 26.3에서 컴파일되지 않던 문제를 고쳤다. 실행 중 첫 로그인 재연결은 실패함을 실측했고, 사용자 결정으로 **2.0.0은 로그인 뒤 재실행으로 연결**한다(재실행 안내 UI 구현). 이 방식으로 iPadOS 18.6(실제 입력)과 17.5(실제 1.3.0 저장소 + 합성 행)에서 업데이트 → 로그인 → 재실행 연결 → 서버 → 독립 peer까지 통과했다. 같은 날 iPadOS 27.2 실기기 · 18.6에서 매 실행 소유 판정이 연결을 영구 보류하는 결함(27 전부 · 빈 저장소 · 대응 전 종료 행 · 오프라인 초안)을 확인했고, 같은 날 수정을 반영해 해소를 실측했다. 배포 관문이 남아 출시 판정은 아직이다. 이어받기 전 [시험 계획 09-28 절](./icloud-sync-compatibility-test-plan.md)과 [핸드오프 09-28 요약](./release-2.0.0-migration-sync-handoff.md)을 먼저 읽는다.

이 문서는 **2026-09-27 현재 코드와 관측**의 시작점이다. 날짜가 더 이른 [출시 범위](./release-2.0.0-migration-sync-scope.md), [누적 핸드오프](./release-2.0.0-migration-sync-handoff.md), [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)의 미완료 목록과 수치는 해당 시점 기록이다. 제품 정책은 출시 범위 문서를 우선한다. 출시 판정은 **NO-GO**다.

## 소스와 환경

- 작업 브랜치: `codex/2-0-0-migration-sync-release`. 이 문서 작성 직전 HEAD는 `60128829e48d751c271ff5fbd89611153cca0392`이며 작업 트리는 깨끗했다. 인계 커밋과 push 후 HEAD는 새 Mac에서 다시 확인한다.
- 27일 확인 환경: macOS 27.2 (`26B5086k`), Xcode 27.0 (`27A266a`), Swift 6.4 (`6.4.0.34.1`), Tuist 4.208.0. 이 값은 **원래 Mac의 관측**이다. 새 Mac은 직접 확인한다.
- 기존 최소 지원 OS를 유지한다. 정상 1.3.0 필기의 payload·좌표·표시 보존, 최초 로그인 시 기존 무계정 V3의 귀속·전송, 불확실한 소유권에서 원본 보존과 업로드 금지가 필수다. 2.0.0 신규 무계정 초안은 별도 로컬 자료다. C14 전체 충돌 보존은 이번 범위 밖이다.
- 사용 계정 별칭: `b`는 Development 시험용 Gmail 계정, `a`는 Hanpass 계정, `never`는 기존 원본 계정이다. 이 문서와 Git에는 계정 주소·암호·토큰을 넣지 않는다. 기존 사용자 자료가 든 시뮬레이터의 계정을 임의로 바꾸지 않는다.

## 현재 구현과 판정 근거

| 영역 | 현재 상태 |
|---|---|
| metadata | [LegacyRowLinkageReader.swift](../Domain/Domain/Sources/SwiftData/LegacyRowLinkageReader.swift)의 reader v5가 관측된 iPadOS 17·18·26 구조를 제한된 profile로 읽는다. `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`는 관측된 SQLite 정수 boolean 형식만 검사한다. 이 private key의 **완료 의미는 확인되지 않았으며** 소유권 근거로 사용하지 않는다. |
| ownership | [CloudKitStoreOwnershipProofClient.swift](../Domain/Domain/Sources/SwiftData/CloudKitStoreOwnershipProofClient.swift)가 보존 원시 V3의 manifest를 먼저 검증하고 별도 작업 사본을 읽는다. 원본을 SQLite로 직접 열어 `-shm`을 바꾸던 결함을 `842eb931`에서 고쳤다. 로컬 행의 내용·연결과 계정 identity·private CloudKit record를 대조하고, 비동기 서버 조회 뒤 현재 계정을 재확인한다. 불일치·불명확·손상은 hold한다. 계정 조회와 실제 attach 사이의 원자성까지 보장한 것은 아니다. |
| 실행 중 재연결 | [AppCoordinatorFeature.swift](../App/CarveApp/Sources/Coordinator/AppCoordinatorFeature.swift), [ChapterCanvasEditSession.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasEditSession.swift), [iCloudSettingReducer.swift](../Feature/SettingsFeature/Sources/Details/iCloud/iCloudSettingReducer.swift) 등에 `60128829`의 마지막 획/초안 인계, 이전 컨테이너 해제 확인, 설정 재시도·앱 재활성화 후 재확인이 있다. 해제가 지연되면 기존 local-only 열람·초안 화면으로 돌아간다. **실제 실행 중 첫 로그인 연결 성공은 아직 입증하지 못했다.** |

실제 iPadOS 18.6 linked V3는 업데이트 **전** 추가 migrator key가 없고 성공한 업데이트 **후** `true`가 생겼다. 그러나 실패한 이식 표본에서도 `true`가 생겼다. 따라서 key 이름이나 값으로 migration 완료를 추정할 수 없다. 더 자세한 전후 비교는 [시험 계획의 27일 실제 관측](./icloud-sync-compatibility-test-plan.md)에 있다.

## 27일까지 확인한 결과

| 분류 | 확인한 것 | 한계 |
|---|---|---|
| 실제 Development CloudKit · iPadOS 18.6 | 실제 1.3.0 로그인 V3 22행을 동일 OS에서 2.0.0으로 업데이트한 뒤 SQL 값·필기 payload 보존, private attach 성공. 실제 1.3.0 무계정 창세기 22:1의 두 획(로컬 blob 469B)은 업데이트 뒤 보존·표시됐다. `b` 첫 로그인 후 서버 직접 읽기에서 해당 ID·468B CloudKit field hash 일치, 오류 0; 독립 시뮬레이터 peer가 23행 중 해당 1행을 받아 원본 469B 로컬 payload와 두 획 표시가 일치했다. | 서버 전송·peer 수신은 **앱 재실행을 거친 경로**다. 실행 중 로그인 직후 runtime 교체 성공의 증거는 아니다. 혼합 서버 표본에는 보관 행/빈 활성 행의 표시 차이가 있어 모든 legacy 표시 보존을 일반화하지 않는다. |
| 안전 경로 · iPadOS 18.6 | 다른 소유자 자료가 든 저장소에서 `.none` hold, 원래 2개 drawing/record metadata 전후 동일, private attach/account-change purge 없음. | 서버 전체 불변을 직접 조회한 시험은 아니다. 계정 확인 불가의 실제 현장 UI·draft 경로도 별도 확인이 필요하다. |
| CLI 자동 테스트 | ownership snapshot 재판독 iPadOS 17.5·18.6 각 9 cases/10 runs 통과. 재연결 관련 iPadOS 18.6 58 cases/59 runs 통과. 무계정 hold 재시도 UI는 17.5·18.6 각 1/1 통과, 실패·skip·runtime warning 0. 최종 앱 컴파일 성공. | test double/무계정 UI로 실제 로그인·전송을 대체할 수 없다. 27일 변경 후 6개 runtime 전체 회귀는 재실행하지 않았다. 강제 컨테이너 해제 지연 fallback UI 시험도 없다. |
| 수동 스모크 | Device Hub에서 실제 18.6 무계정 입력 두 획의 업데이트 후 표시 및 독립 peer 수신 표시를 확인했다. | Apple Pencil 실기기·배포 후보 스모크가 아니다. |

CLI 결과 bundle은 원래 Mac의 `/private/tmp/carve-ownership-snapshot-ios17-r2-20260927.xcresult`, `/private/tmp/carve-ownership-snapshot-ios18-20260927.xcresult`, `/private/tmp/carve-reconnect-related-ios18-20260927.xcresult`, `/private/tmp/carve-reconnect-ui-ios17-r5-20260927.xcresult`, `/private/tmp/carve-reconnect-ui-ios18-20260927.xcresult`에 있다. 최종 컴파일 로그는 `/private/tmp/carve-reconnect-final-build-20260927.log`다. 작성 시점에 모두 존재함을 확인했다. 이전 Xcode 27 전체 6-runtime 회귀 결과는 [AGENTS.md](../AGENTS.md)에 있으나 위 변경의 사후 전체 회귀 결과로 간주하지 않는다.

## 원래 Mac에만 있는 표본

- `/private/tmp/carve-peer-correct-20260926`은 실제 V3 전후 사본, 서버 조회 JSON, 앱 로그, 수동 화면을 포함한다. **Git에는 없다.** 개인 필기·계정 정보가 있을 수 있으므로 공개 첨부하거나 원본 DB를 직접 열어 변경하지 않는다. 새 Mac에서 필요하면 안전한 별도 경로로 전달받아 일관성 있는 복사본을 조사한다. `peer-startup-cli.png`에는 계정 주소가 보여 공개하지 않는다.
- 같은 루트의 `Historical-1.3.0.app`은 iPadOS 18.6 시뮬레이터에서 회수한 실제 1.3.0(1) 앱이다. 바이너리 SHA256 `de8893a70a0f2bd2bf2a1605247aaa89cea5dfafec5116460df5f7a94889bfbd`; Xcode 26.3/SDK 26.2 산출물이다. 새로운 Mac의 소스 checkout만으로 이 **동일 바이너리**가 생기지 않는다. 안전하게 전달받거나 실제 역사 앱을 다시 확보해 출처와 hash를 기록한다.
- Development 서버 읽기 전용 임시 관측기는 `/private/tmp/carve-ownership-server-read-20260927/ReadProbe-v2.dylib`에 있다. 저장소 도구가 아니다. 새 Mac에서 없으면 기존 결과를 재실행했다고 쓰지 말고 별도 읽기 관측기를 준비한다.
- 시뮬레이터 이름·UDID와 `/private/tmp` 경로는 원래 Mac 전용이다. `simctl clone`이 원본 앱 컨테이너를 가리킨 전력이 있으므로 clone을 격리된 peer로 간주하지 않는다.

## 바로 이어서 할 일

1. `git status --short --branch`, `git diff`로 현재 변경을 확인하고 [AGENTS.md](../AGENTS.md), [출시 범위](./release-2.0.0-migration-sync-scope.md), [누적 핸드오프](./release-2.0.0-migration-sync-handoff.md), [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md), [동기화·백업 정책](./icloud-sync-and-backup-policy.md), [기기 CLI 절차](./device-debugging-cli.md)를 읽는다. 날짜별 과거 관측과 현행 코드를 구분한다.
2. 새 Mac에서 `xcode-select -p`, `xcodebuild -version`, `xcrun swift --version`, `mise x -- tuist version`, `xcrun simctl list runtimes`를 기록한다. 기본 Xcode 27을 확인하고 `mise x -- tuist generate --no-open`으로 workspace를 만든다. 자동 빌드·테스트는 CLI와 iPad destination만 쓴다.
3. **가장 가까운 출시 차단:** 원래 Mac의 독립 iPadOS 17.5 `Carve-2.0.0-ActualV3-iOS17.5-20260927`(원래 Mac UDID `B60A857B-34C3-4710-8795-5FC93877376C`)에 역사 1.3.0이 무계정·창세기 23장으로 열려 있다. Device Hub 포인터 자동 입력은 DB drawing 0행이었고, 사용자에게 직접 23:1에 짧은 획을 그리되 **아직 로그인하지 말아 달라**고 요청한 상태다. 사용자 완료 응답은 아직 없다. 먼저 실제 획이 저장됐는지 확인하고 앱을 종료해 Application Support를 일관성 있게 보존한다. 획이 없으면 성공 표본으로 세지 않는다. 새 Mac이라면 별도 독립 iPadOS 17.5 시뮬레이터에서 이 단계를 재구성한다.
4. 실제 17.5 V3의 DB/WAL·metadata·drawing·표시를 사본에서 기록한 다음 **같은 시뮬레이터**를 현재 Xcode 27 2.0.0 앱으로 업데이트한다. 무계정 원본·좌표·표시와 local-only 보류를 비교한다. 이후 `b` 계정의 iCloud 첫 로그인을 거쳐 **앱을 종료하지 않은 자동 재연결**의 ownership ledger, Development 서버 field bytes/hash, 별도 독립 peer 수신·표시를 대조한다. 서버 container는 `iCloud.Carve.SwiftData.iCloud.dev`, environment는 Development/Sandbox로 확인하고 Production은 변경하지 않는다. 계정 변경 전 보존 대상과 영향을 다시 확인한다.
5. 같은 프로세스 첫 로그인 실패, pending export 중 영구 hold, 계정 확인 불가/불일치의 로컬 열람·초안·무전송 여부를 실제 표본으로 추가 확인한다. 수정이 필요하면 가장 좁은 관련 `xcodebuild test`를 iPad destination에서 먼저 돌린다. 자동 테스트·실제 서버·수동 UI 결과를 분리해 [시험 계획](./icloud-sync-compatibility-test-plan.md)과 [누적 핸드오프](./release-2.0.0-migration-sync-handoff.md)를 갱신한다.

현재 **출시 NO-GO**의 직접 이유는 정상 지원 OS인 17.5의 실제 사용자 V3 업데이트/첫 로그인 경로와 17.5·18.6의 실행 중 로그인 재연결을 서버·독립 peer까지 완료한 live 증거가 없기 때문이다. Distribution 서명 Archive/export·TestFlight·Production entitlement·실기기 후보 스모크도 별도 출시 게이트로 남아 있다. 과거 전체 회귀나 iPadOS 18.6 재실행 수신 결과만으로 이 빈칸을 통과 처리하지 않는다.
