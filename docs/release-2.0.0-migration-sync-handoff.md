# Carve 2.0.0 iCloud 동기화 인계

작성: 2026-09-23 · worktree: `migration-sync-release` · 브랜치: `codex/2-0-0-migration-sync-release`

## 현재 판정

출시 판정은 **NO-GO**다. production 저장소 소유 증명 공급자는 연결했고 증거가 맞지 않거나 읽히지 않으면 계속 fail-closed 한다. 현재 `LegacyRowLinkageReader.validatedOSMajors`는 `[26]`이다. iOS 17 런타임과 iOS 19~25 런타임은 설치되어 있지 않다.

iOS 18.6에서 실제 1.3.0을 실행해 만든 V3 저장소는 기본 무계정 metadata 네 key 외에 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`가 하나 더 있다. 값은 정수 boolean `true`였다. 이 private Core Data 키의 의미를 확인할 공개 근거가 없어, iOS 18을 안전하게 허용할 수 없다. 현재 정확한 key profile 규칙은 이 표본을 거절한다. `Carve-Ownership-iOS18-6`에는 계정 로그인을 하지 않았다.

## 코드 상태

- `App.swift`가 production `CloudKitStoreOwnershipProofClient`를 live `DrawingEditEnvironment`에 주입한다.
- 소유 증명은 빈 새 저장소, 무계정 1.3.0 V3 원본, 기존 private CloudKit 저장소의 세 갈래다. 계정 확인만으로 소유를 만들지 않는다. 표식은 계정 간 재귀속되지 않는다.
- 기존 private 저장소는 현재 계정 identity 일치, 로컬 행·미러링 레코드 일대일성, 대기 작업 없음, private DB 전체 레코드 조회를 요구한다.
- reader v4는 metadata key 집합과 각 SQLite 값 열의 형식·비어 있지 않음, metadata migration 미요청, identity 확인 상태를 함께 판정한다. 추가·누락·중복·NULL·잘못된 형식은 소유 proof에서 거절한다.
- `SyncedWriteBlock` 경로가 필사 외 즐겨찾기·위젯 보관·이력 복원·N-Canvas 직접 쓰기도 막는 기존 규칙을 유지한다. 계정 변경 차단, server-work 표, 삭제 기준점 K, 원본 보존, 마이그레이션 실패 차단, 무계정 신규 로컬 초안의 자동 업로드 금지도 유지한다.
- 기존 `Carve-ACC-dut` Genesis 1:1·1:2 표본과 `Carve-ACC-B` 상태는 보존했다. 이번 후속 실험에서 이 두 simulator 앱을 실행·변경하지 않았다.

## 실제 iOS 18.6 관측

- Xcode 26.3 (17C529), iPadOS 18.6 전용 simulator `Carve-Ownership-iOS18-6`에서 historical 1.3.0 build를 실행했다.
- 기존 표본을 쓰지 않고 Genesis 1:3에 합성 PencilKit stroke를 가진 V3 행을 추가했다. 터치·드래그는 필기 표본을 만들지 못했다. 압력·기울기·Apple Pencil 결과로 간주하지 않는다.
- 저장소 snapshot은 `/private/tmp/carve-ios18-live-proof-evidence/snaps/ios18-1-3-initial-state`와 `.../ios18-1-3-v3-seeded`에 있다. 이 경로는 해당 머신의 임시 자료다.
- simulator는 로그인하지 않은 채 유지한다. 앞선 18.3.1·18.6 test-double 집중 결과는 현재 허용 OS 판정의 증거가 아니다.

## 검증 기록과 현재 실패

- 현재 Xcode: 26.3 (17C529). runtime 확인: iOS 16.4, 18.3.1, 18.6, 26.2. iOS 17 및 19~25는 없음. iOS 16.4는 배포 최소 버전보다 낮다.
- `Carve-ACC-dut`, `Carve-ACC-B`는 iPadOS 26.2에서 기존 sandbox 계정으로 로그인된 채 부팅되어 있었다. 계정을 바꾸지 않았고 인증정보를 입력하지 않았다.
- 이 변경 전 iOS 18.3.1·18.6 집중 test-double suite 66/66 통과, iOS 26.2 Domain 452개(448 통과, 4 expected failure), SettingsFeature 54/54, CarveFeature 457/457, 앱 빌드 성공 결과가 있다. strict metadata profile 적용 뒤 live CloudKit proof는 재실행하지 않았다.
- strict reader 변경 뒤 iOS 18.6 `DomainTest`의 `build-for-testing`은 성공했다. 같은 산출물의 `test-without-building`은 67개/5 suite 실행 후 3 issue로 실패했다. 주요 원인은 `productionClientClaimsVerifiedLegacySnapshot` fixture의 실제 metadata profile 판정 실패, reader 버전을 3으로 기대하던 낡은 assertion이었다.
- 테스트 실패 뒤 reader 버전 assertion을 4로 수정했고, fixture에서 실제로 읽힌 `metadataValueProfileComplete`, `metadataNeedsMigration`, key 집합을 확인할 assertion을 추가했다. **이 마지막 test-source 변경은 아직 다시 빌드·실행하지 않았다.** 이어받는 작업은 이를 첫 단계로 재검증해야 한다.
- 직전 산출물: `/private/tmp/carve-migration-sync-release-followup-ios18-derived`
- 직전 로그: `/private/tmp/carve-migration-sync-release-followup-ios18-build.log`, `/private/tmp/carve-migration-sync-release-followup-ios18-tests.log`
- `git diff --check`는 최근 통과했다. SwiftLint와 iOS 26.2 최신 strict-profile 검증은 아직 실행하지 않았다.

## 이어서 할 일

1. 현재 브랜치에서 지정한 다섯 Domain suite를 iOS 18.6에서 다시 `build-for-testing`한 뒤, 성공한 같은 DerivedData로 `test-without-building`한다. 우선 fixture reader가 metadata profile을 왜 거절하는지 새 assertion으로 분리한다. 의미를 모르는 migration marker를 허용하도록 바꾸지 않는다.
2. fixture가 안전한 metadata profile을 재현하도록 고친 다음, iOS 18.6에서 알 수 없는 marker와 iOS 18 proof가 fail-closed임을 확인한다. 계정 로그인을 하지 않는다.
3. Xcode 26.3 iPadOS 26.2에서 같은 ownership/read/snapshot/write-gate 범위를 좁게 빌드·실행한다. strict rule 적용 뒤 현재 private-store metadata profile과 live proof를 따로 판정한다. ACC simulator 사용 전에는 저장소와 서버를 snapshot하고 Genesis 1:1·1:2 표본이 보존되는지 전후 비교한다. 계정 전환이나 로그아웃은 하지 않는다.
4. 가능한 경우 일반 Domain·SettingsFeature·CarveFeature 회귀 수를 이전 기준선과 비교한다. `build-for-testing` 성공 전에는 `test-without-building`을 실행하지 않는다.
5. iOS 17 시험에는 Xcode 26.3과 호환되는 iPadOS 17 simulator runtime 또는 iOS 17 실기기가 필요하다. 실험 가능한 환경이 제공되지 않으면 미실행 이유와 필요한 runtime/device를 기록하고 NO-GO를 유지한다. iOS 19~25는 해당 runtime과 OS별 metadata 관측이 필요하다.
6. 위젯 보관·이력 복원·N-Canvas의 실제 CloudKit 왕복과 로그인 상태 1.3.0 덮어쓰기도 미검증이다. 기존 C14 F44~F57 실험 기록은 완료 근거로 승격하지 않는다.
7. 문서의 OS별 실행 결과·실패·미검증 범위·최종 go/no-go를 갱신한다.

추가 로그·문서·프롬프트에 iCloud 계정 식별 원문, 이메일, 토큰 또는 비밀정보를 적지 않는다. 앱 설치·계정 로그인 조작이 필요해지면 실행하지 말고 사용자에게 단계와 예상 데이터 영향을 설명한다. 계정less iOS 18.6 sample은 현재 상태를 보존한다.

새 컴퓨터에서 사용할 복사 가능한 작업 지시는 [continuation prompt](./release-2.0.0-migration-sync-continuation-prompt.md)에 있다.
