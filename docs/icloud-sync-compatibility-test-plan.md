# iCloud 구·신 버전 호환성 및 복구 테스트 계획

> **현행 출시 판정(2026-09-25):** 2.0.0의 필사 이전·첫 로그인 동기화 기준과 **NO-GO** 사유는 [출시 범위 문서](./release-2.0.0-migration-sync-scope.md)를 따른다. 현행 주 검증 대상은 macOS 27.2 / Xcode 27.0이고 Device Hub는 기기 확인·수동 스모크에 사용하며 자동 빌드·테스트는 CLI로 수행한다. Xcode 27 Tuist workspace Debug iPad simulator build와 iPadOS 17.5 전체 회귀(998 통과·4 expected failure·6 skip), iPadOS 18.6·26.2·26.4·26.5 전체 회귀(각 999 통과·4 expected failure·5 skip), iPadOS 27.0 전체 회귀(998 통과·4 expected failure·6 skip)가 통과했다. 여섯 runtime 모두 총 1008건·실패 0·xcresult runtimeWarnings 없음이다. iOS 17.5 전체 로그의 임시 migration/store fixture 관련 SQLite 경고는 테스트 failure나 xcresult runtime warning이 아니며, 정리 시점과 컨테이너 수명 관계는 미확정이다. 최초 iPadOS 27.0 전체 실행의 cancellation timing 실패는 focused rerun과 후속 전체 회귀에서 재현되지 않았다. 최초 SwiftData 네 실패는 iOS 27의 새 `SwiftDataError.unknownDataStoreSchema`를 확인된 1.0.x store shape에 한해 스키마 불일치로 처리하도록 고친 뒤 focused migration suite와 전체 회귀에서 통과했다. 수정 뒤 첫 전체 run에서 난 reader fixture의 SQLite 잠금 한 건도 reader suite 단독 재실행과 후속 전체 회귀에서 재현되지 않았다. 최초 F60의 XCFramework `ProcessXCFramework` 서명 실패는 workspace build에서 재현되지 않았다. 개별 `-project CarveApp` SwiftPM 모듈 오류와 읽기 전용 artifact 서명 상태 이상은 별도 관측이며 인과관계는 미확정이다. Xcode 26.3의 과거 회귀 결과는 비교 기준이지 Xcode 27 자격 증거가 아니다. Xcode 26.3의 전체 회귀와 Xcode 27 focused migration suite 결과는 아래 기록에 분리했다. Device Hub 수동 UI smoke는 새 iPadOS 27.0 simulator에서 빈 reader 표시와 창세기 1장→2장→1장 이동을 확인했으나 앱 시작 시 iCloud 필사 수신 대기 UI가 나타났다. live CloudKit proof·실기기 필기 입력·App Store 배포 서명 Archive·배포 entitlement·TestFlight는 미완료다. 로컬 Development 서명 Archive는 성공했지만 배포 증거로 보지 않아 NO-GO다. 아래 SEP 시험은 C14 분리 설계의 관측 기록이다.

작성: 2026-09-16 · 최신 결과 추가: 2026-09-25 · 목표: 2.0.0 · **현행 판정은 위 출시 범위 문서와 §5-2/F59/F60을 따른다.** 단계 A~D와 CK/SEP 표의 날짜별 상태는 당시 계획·관측 기록으로 보존한다.

> **2026-09-16 범위 변경** — 필사 백업 기능이 **2.1** 로 이관됐다. 단계 D 는 그때 수행하고, 2.0.0 출시 판정은 단계 A~C 로 한다.

## 5-2. 2.0.0 출시 후보 구현·검증 결과 (2026-09-23)

이번 후보는 `codex/2-0-0-migration-sync-release` 브랜치의 별도 worktree에서 검증했다. Xcode 26.3 (17C529), iPad mini (A17 Pro) · iOS 26.2를 사용했다. 세 테스트 scheme 각각에서 `build-for-testing` 성공을 확인한 뒤 같은 DerivedData 산출물로 `test-without-building`을 실행했다.

코드 리뷰에서 확인한 차단 사유는 배포 `DrawingEditEnvironment.storeOwnership`에 값을 공급하는 구현이 없어, 계정 확인이 끝나도 캔버스 필사가 초안에만 남고 즐겨찾기·위젯 보관·이력 복원 같은 동기화 저장소 쓰기가 차단된다는 점이었다. `CloudKitStoreOwnershipProofClient`를 앱의 live 환경에 연결했다. 계정 확인만으로는 소유를 인정하지 않는다. 다음 중 하나가 별도로 입증되고, 확인 세대가 계속 유효할 때만 저장소 범위를 준다.

- 원래 저장소 파일이 없었다는 `raw-not-needed` 기록과 빈 앱 모델 행 수.
- 보존된 업데이트 전 V3 사본이 계정 미연결·미러링 대응 없는 1.3.0 legacy 필사임을 판독한 결과.
- 기존 미러링 저장소의 계정 식별이 현재 확인 계정과 정확히 같고, 모든 로컬 모델 행과 안정된 CloudKit 레코드가 일대일이며 현재 계정 private DB에서도 모두 조회된 결과.

성공한 소유 범위는 CloudKit 저장소 바깥의 내구성 표식에 해시된 계정 범위로 한 번 기록하고 다른 계정으로 바꾸지 않는다. 표식 손상, 미러링 정보 불완전, 네트워크 조회 실패, 다른 계정, K 읽기 실패, 계정 확인 세대 변경은 실패 닫힘이다. 전체 로컬 삭제 뒤에도 소유자는 다시 바인딩하지 않는다. 필사 저장 외에 즐겨찾기 추가·해제·실행 취소, 위젯 보관, 이력 복원, N-Canvas 쓰기는 모두 같은 `SyncedWriteBlock` 판정을 거친다. 계정·서버 작업 표·K·세대 차단은 유지했다. C14의 행별 분리·삭제 코드는 보존했고 2.0.0 시작 경로는 원시 사본 후 로컬 마이그레이션·CloudKit 연결로 바꿨다.

직접 쓰기 경로는 `SyncedWriteBlock` 사용처와 기존 Feature 저장 차단 시험으로 확인했다. 실제 private DB 왕복은 즐겨찾기 추가·해제에서 확인했다. 위젯 보관·이력 복원·N-Canvas의 별도 UI 동작은 이번 시험 계정에서 직접 실행하지 않았으며, 이 경로별 라이브 서버 확인은 남아 있다.

2.0.0에서 로그아웃 상태로 새로 쓴 필사는 기존 비동기화 초안 파일에 남는다. 그 편집 문맥은 로그인하면 계정 변경으로 끝나며, 해당 초안을 새 계정 저장소에 자동 채택하지 않는다. 옛 1.3.0 V3 표본만 첫 로그인 귀속 예외다.

자동 검증 결과:

- 출시 경로 단위 시험 5개 통과, 소유·C14 판독기 관련 Domain 집중 시험 46개 통과.
- `DomainTest` 전체 445개 통과. 기준선 441개에 신규 시험 4개를 포함했다. 실제 sep 표본·지시서가 이 worktree에 없는 기존 probe 4개는 known issue로 보고됐으며 시험 실행은 성공했다. **아래 지원 OS 후속 재검증에서 이 수를 갱신했다.**
- `SettingsFeatureTest` 54개, `CarveFeatureTest` 457개 통과. 전체 Feature 회귀에는 즐겨찾기·위젯 보관·복원·삭제 경로의 저장 차단 시험이 포함됐다.
- `CarveApp` iPad simulator 빌드와 변경 Swift 파일 SwiftLint 통과. `git diff --check`도 통과했다.
- iPadOS 18.6 `Carve-SEP-ios18`에서 `build-for-testing` 뒤 같은 산출물로 V3 마이그레이션·legacy 판독 시험 34개 통과했다. 당시 production reader는 iOS 26만 허용했다. **지원 OS 후속 결과는 아래 표를 따른다.**

### 지원 OS 판독 후속 (2026-09-23)

첫 로그인 예외는 업데이트 전 원시 사본의 매니페스트·전체 파일 지문 검증, V3 스키마, 무계정 metadata key 네 개의 정확한 집합과 예상 값 형식, migration 미요청, 계정 식별·CloudKit 대응·대기 작업 부재, 전체 로컬 행 수 일치를 모두 요구한다. 기존 로그인 저장소는 iOS 26.2에서 관측한 private metadata key 일곱 개의 정확한 집합·예상 값 형식, migration 미요청, identity 확인 완료, 현재 계정과의 identity 일치, private DB 내 모든 대응 레코드 조회를 요구한다. NULL·중복·미지 key, 예상 열이 아닌 값, migration 요청, identity 불일치, 서버 오류는 실패 닫힘이다.

기존 `Carve-ACC-dut`의 업데이트 전 원시 V3 사본은 앱을 실행하지 않고 SQLite 읽기 전용으로 확인했다. `integrity_check=ok`, metadata 행 4개, 무계정 key 네 개가 각 1회, 미러링 대응 행 0개였다. 이 사본의 metadata 값은 읽지 않았다. 별도 임시 iOS 18.6 simulator에서 출시본 1.3.0을 실행하고 Genesis 1:3에 synthetic V3 행을 처음 저장한 뒤, 키 이름·키별 SQLite 값 형식과 두 boolean 상태만 요약했다. 이때 정확한 무계정 네 key 외에 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`가 나타났고 해당 필드의 정수 boolean 상태는 `true`였다. 이 private Core Data key의 의미는 확인할 근거가 없어, iOS 18의 이 profile은 첫 로그인·기존 계정 proof 모두에서 거절한다. 계정·이메일 값은 쿼리하거나 기록하지 않았다. DUT·B의 Genesis 1:1·1:2 표본은 수정하지 않았다.

**검증 환경 스냅샷(2026-09-24):** 현재 별도 Mac은 macOS 27.2 (26B5086k), 기본 `xcode-select` 경로 `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0 (27A266a)이다. Tuist 4.208.0이고, 검증용 Xcode 26.3 (17C529)도 `/Applications/Xcode-26.3.0.app/Contents/Developer`에 설치돼 있다. 9/24 자동 회귀는 이 경로를 `DEVELOPER_DIR`로 지정해 Xcode 26.3에서 실행했다. 기본 Xcode 27에서 `simctl list runtimes`와 `list devices available`은 성공했다. Xcode 26.3을 지정한 sandbox 조회는 CoreSimulatorService 연결 오류를 냈으나, 권한을 높인 read-only runtime 조회는 성공했다. runtime은 iOS 17.5·18.6·26.2·26.4·26.5·27.0이며 iOS 19~25는 없다. iPad mini (6th generation) iOS 17.5 simulator(UDID `0347221E-08F5-48C9-9F8E-6D7995C25D9F`)로 회귀를 실행했다. Device Hub는 iPadOS 27.2 실기기를 표시했고, 보호 표본이나 실기기 앱은 조작하지 않았다.

| OS | iPad simulator | 빌드 경로 | 테스트 실행 경로 | 결과·범위 |
|---|---|---:|---:|---|
| iPadOS 18.3.1 | iPad mini (A17 Pro) | 선행 실행 성공 | 선행 실행 성공 | 당시 규칙의 집중 66/66 통과(test double); 현재 허용 OS 아님 |
| iPadOS 18.6 | 일반 iPad mini (A17 Pro); 보호 표본 simulator는 미사용 | `xcodebuild test` 빌드 성공, 미완성 초안 제외 설정 없이 실행(9/24) | 최신 전체 999 통과·4 expected failure·5 기기 전용 UI test skip·실패 0 (총 1008); 집중 migration 6/6 테스트 정의 통과(동적 parameter 포함 7회 실행) | blank/no-account 시작 화면 smoke는 9/23 기록. migration marker 의미와 실제 CloudKit proof는 미확인; OS 18 ownership은 fail-closed |
| iPadOS 26.2 | iPad mini (A17 Pro); iPad Air 11-inch (M3)는 9/23 기록 | mini `xcodebuild test` 빌드 성공, 미완성 초안 제외 설정 없이 실행(9/24) | mini 최신 전체 999 통과·4 expected failure·5 기기 전용 UI test skip·실패 0 (총 1008); 집중 migration 6/6 테스트 정의 통과(동적 parameter 포함 7회 실행). Air는 9/23 결과 | Air blank/no-account 시작 화면 smoke는 9/23 기록. Release build는 unsigned simulator build; strict 변경 뒤 live CloudKit proof는 미실행 |
| iPadOS 17.5 | iPad mini (6th generation) | `Carve-Workspace` 전체 시험 빌드 성공, 미완성 초안 제외 설정 없이 실행(9/24) | 전체 998 통과·0 실패·6 skip·4 expected failure (총 1008); migration 집중 6/6 테스트 정의 통과(동적 parameter 포함 7회 실행) | 최초 발견한 migration 실패 3건은 V1 DTO 전달과 V2 시작 plan 선택으로 해결. 조건부 iOS 18·26 전용 V1-only 동작 시험 1개는 skip. CloudKit ownership proof·UI smoke는 미실행 |
| iPadOS 19~25 | 현재 runtime 목록에 없음 | 미실행 | 미실행 | reader 검증도 없음. 해당 OS runtime과 iPad simulator가 필요하며, OS별 V3·private-store metadata profile 관측 뒤에만 허용 검토 |

새 규칙 뒤 최초 iOS 18.6 실행은 67개/5 suite 중 `productionClientClaimsVerifiedLegacySnapshot`의 성공 경로를 OS 구분 없이 기대해 실패했다. 당시 reader의 허용 OS는 `[26]`이므로 iOS 18.6에서 판독이 unknown으로 끝나는 것이 production 정책상 맞았다. 이 실패는 iOS 18에서 소유를 허용할 근거가 아니라 테스트 기대의 오류였다. test는 허용 OS에서는 정확한 metadata profile 뒤 claim 성공을 확인하고, 그 밖의 OS에서는 unknown 판정·claim 거부·ledger 미생성을 확인하도록 고쳤다. reader 버전 assertion도 v4로 맞췄으며, raw SQLite fixture 쓰기에는 5초 busy timeout을 둔다.

**최신 소스의 iPadOS 26.2 후속 검증(2026-09-23):** 일반 iPad mini (A17 Pro)에서 위 다섯 suite를 `build-for-testing`한 뒤 동일 DerivedData로 실행해 67/67 통과(실패·건너뜀 0)를 확인했고, `CarveApp` 타깃 빌드도 성공했다. 이 결과는 실기기 CloudKit proof가 아니다. 당시 첫 빌드는 checkout의 미추적 `LegacyRowCorrespondence.swift` 컴파일 오류로 실패해 파일을 보존하고 해당 미추적 파일만 빌드에서 제외했다. 최종 DerivedData는 `/private/tmp/carve-migration-sync-release-26.2-intended-derived`, 로그·결과는 `/private/tmp/carve-migration-sync-release-26.2-final-build.log`, `/private/tmp/carve-migration-sync-release-26.2-locked-tests.log`, `/private/tmp/carve-migration-sync-release-26.2-locked-tests.xcresult`, `/private/tmp/carve-migration-sync-release-26.2-app-build.log`에 있다. 이들은 현재 머신의 임시 자료다.

**iPadOS 18.6 최신 소스 재검증(2026-09-23):** macOS 27.2 + Xcode 26.3 (17C529), iPad mini (A17 Pro), build 22G86에서 집중 다섯 suite를 새 `build-for-testing` 후 동일 DerivedData로 실행했다: **67/67 통과, 실패·건너뜀 0**. 이어 Domain 전체는 xcresult 기준 449 통과·4 expected failure·실패 0·건너뜀 0, SettingsFeature 54/54, CarveFeature 457/457을 각각 빌드 성공 뒤 동일 산출물로 실행해 통과했다. `Carve-Workspace` iPadOS 18.6 simulator 빌드도 성공했다. 로그·결과 bundle은 `/private/tmp/carve-migration-sync-release-ios18.6-final-build2.log`, `/private/tmp/carve-migration-sync-release-ios18.6-final-tests2.log`, `/private/tmp/carve-migration-sync-release-ios18.6-final-tests2.xcresult`, `/private/tmp/carve-migration-sync-release-ios18.6-domain-full-build.log`, `/private/tmp/carve-migration-sync-release-ios18.6-domain-full-tests.log`, `/private/tmp/carve-migration-sync-release-ios18.6-domain-full-tests.xcresult`, `/private/tmp/carve-migration-sync-release-ios18.6-settings-tests.xcresult`, `/private/tmp/carve-migration-sync-release-ios18.6-carve-feature-tests.xcresult`, `/private/tmp/carve-migration-sync-release-ios18.6-app-build.log`에 있다. 기존 미추적 `LegacyRowCorrespondence.swift`만 빌드에서 제외했고, 보호된 `Carve-Ownership-iOS18-6`·ACC 기기와 실제 CloudKit 계정은 사용하지 않았다.

**전체 회귀·시작 smoke·Release configuration 후속(2026-09-23):** `Carve-Workspace` 전체 테스트를 Xcode 26.3에서 일반 iPad mini (A17 Pro) iPadOS 18.6, iPad mini iPadOS 26.2, iPad Air 11-inch (M3) iPadOS 26.2로 각각 실행했다. 세 실행 모두 **997 passed, 4 expected failures, 5 skipped, 0 failed (총 1006)**였다. skip 5개는 실기기 전용 UI test다. 별도 blank/no-account simulator에서 iPadOS 18.6 mini와 iPadOS 26.2 Air가 FirstRunGuide까지 크래시 없이 표시되는 것을 확인했다. 이 smoke는 안내의 시작 버튼을 누르거나 실제 필사·계정 흐름을 확인한 것은 아니다. `CarveApp` Release configuration simulator build는 성공했고 Info.plist의 버전은 2.0.0 (build 1)이었다. 서명을 끈 simulator compile이므로 archive·배포 서명·entitlement 검증으로 세지 않는다. 결과는 `/private/tmp/carve-release-2.0-current-ios18-regression.xcresult`, `/private/tmp/carve-release-2.0-current-ios26.2-regression.xcresult`, `/private/tmp/carve-release-2.0-current-ios26.2-air-regression-run2.xcresult`, 로그는 각 `...-regression.log` 및 `/private/tmp/carve-release-2.0-current-ios26.2-air-regression-run2.log`, Release log는 `/private/tmp/carve-release-2.0-current-release-config-build.log`에 있다.

**전체 자동 회귀 재실행(2026-09-24, 이전 후보):** macOS 27.2 / Xcode 26.3 (17C529), Tuist 4.208.0으로 생성한 `Carve.xcworkspace`, iPad mini (A17 Pro)에서 iPadOS 18.6과 26.2 전체 `Carve-Workspace` 테스트를 다시 빌드·실행했다. 두 OS 모두 **997 passed · 4 expected failures · 5 skipped · 0 failed (총 1006)**로 통과했다. skip 5개는 실기기 전용 UI 테스트다. 이 실행은 미추적 초안을 제외한 당시 소스 기준이었다. 상세 결과 bundle은 `/private/tmp/carve-2-0-0-autotest-20260924-full-ios18.6.xcresult`, `/private/tmp/carve-2-0-0-autotest-20260924-full-ios26.2.xcresult`다.

재현한 전체 실행 명령은 아래와 같다. 두 명령 모두 동일한 iPad mini 대상과 검증된 Xcode 26.3을 사용했다.

```bash
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=18.6' -derivedDataPath /private/tmp/carve-2-0-0-autotest-20260924-derived -resultBundlePath /private/tmp/carve-2-0-0-autotest-20260924-full-ios18.6.xcresult EXCLUDED_SOURCE_FILE_NAMES=LegacyRowCorrespondence.swift -quiet
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2' -derivedDataPath /private/tmp/carve-2-0-0-autotest-20260924-derived -resultBundlePath /private/tmp/carve-2-0-0-autotest-20260924-full-ios26.2.xcresult EXCLUDED_SOURCE_FILE_NAMES=LegacyRowCorrespondence.swift -quiet
```

최초 집중 실행은 파일 제외 값을 셸 환경 변수로 전달해 Xcode 빌드 설정에 적용하지 못했고, `LegacyRowCorrespondence.swift`에서 `LegacyJudgementDoubt: Error` 미준수와 `Int64`/`Int` 형식 오류가 나 테스트 시작 전에 실패했다(`/private/tmp/carve-2-0-0-autotest-20260924-focused.xcresult`). 빌드 설정 인자로 제외를 전달한 재실행은 통과했다. 해당 미추적 파일은 현재 미완성 코드이며 `fatalError` 자리표시자도 있어 이 문서의 성공 결과에 포함되지 않는다. 파일을 배포 후보에 넣으려면 구현을 완성하고 제외 없이 다시 빌드·테스트해야 한다. 이번 실행은 테스트/앱 컴파일 경로 회귀이며, 별도 UI 조작·Apple Pencil 입력·iCloud 로그인·CloudKit 왕복은 수행하지 않았다.

변경한 두 테스트 파일의 SwiftLint도 `mise x -- swiftlint lint --quiet --config .swiftlint.yml Domain/Domain/Tests/DrawingStoreOwnershipProofTesting.swift Domain/Domain/Tests/LegacyRowLinkageReaderTesting.swift`로 실행해 통과했다. 문서 수정 뒤 `git diff --check`도 통과했다. Xcode 빌드의 저장소 범위 lint 단계에서 나온 기존 경고는 별도로 남아 있으며 전체 저장소 lint 무경고를 뜻하지 않는다.

당시 이 빌드·회귀에서는 checkout의 미추적 `Domain/Domain/Sources/SwiftData/LegacyRowCorrespondence.swift`가 Swift 오류(throw된 `LegacyJudgementDoubt`가 `Error`를 따르지 않음, `Int64`/`Int` 인자 불일치)를 내서 파일은 보존하고 `EXCLUDED_SOURCE_FILE_NAMES=LegacyRowCorrespondence.swift`로 제외했다. 따라서 그 결과를 checkout의 모든 미추적 소스 기준 빌드 성공으로 표현하지 않았다. 테스트한 tracked 후보 소스와 문서의 통계는 성공했지만, 파일을 커밋 후보에 포함한다면 먼저 컴파일을 고치고 제외 없이 다시 빌드해야 한다.

strict-profile 변경 후 live CloudKit proof를 수행하려고 기존 ACC simulator의 clone을 준비했으나, clone 앱을 실행하는 작업은 기존 필기가 private Development CloudKit DB로 자동 전송·서버 상태 변경을 일으킬 수 있다는 auto-review 사유로 차단됐다. 앱을 실행하지 않았고 원본 ACC simulator는 변경하지 않았으며 임시 clone은 삭제했다. 이 gate는 통과가 아니라 미실행으로 둔다. 이어 실제 private DB proof를 하려면 기존 ACC 합성/필기 payload의 전송과 Development private DB 변경을 사용자가 명시적으로 승인하거나, 별도 synthetic 표본·계정으로 범위를 바꿔야 한다.

### 미완성 초안 이동 후 파일 제외 없는 회귀 (2026-09-24)

`Domain/Domain/Sources/SwiftData/LegacyRowCorrespondence.swift`는 실제 호출처가 없는 이전 판독기 초안이었다. 같은 목적의 실제 경로는 `LegacyRowLinkageReader`가 담당하며 초안에는 컴파일 오류와 `fatalError` 자리표시자가 있었다. 초안을 덮어쓰거나 병렬 구현으로 승격하지 않고, 원본을 복구할 수 있도록 `/private/tmp/carve-legacy-row-correspondence-draft-20260924.swift`로 이동했다. Tuist 프로젝트를 다시 생성한 뒤 새 DerivedData에서 `EXCLUDED_SOURCE_FILE_NAMES` 없이 Xcode 26.3 `Carve-Workspace` 전체 회귀를 세 iPadOS runtime에 실행했다.

| iPadOS | 기기 | 결과 | xcresult |
|---|---|---|---|
| 17.5 | iPad mini (6th generation) | **998 통과 · 실패 0 · 6 skip · 4 expected failure (총 1008)** | `/private/tmp/carve-2-0-0-candidate-unexcluded-ios17.5.xcresult` |
| 18.6 | iPad mini (A17 Pro) | **999 통과 · 실패 0 · 5 skip · 4 expected failure (총 1008)** | `/private/tmp/carve-2-0-0-candidate-unexcluded-ios18.6.xcresult` |
| 26.2 | iPad mini (A17 Pro) | **999 통과 · 실패 0 · 5 skip · 4 expected failure (총 1008)** | `/private/tmp/carve-2-0-0-candidate-unexcluded-ios26.2.xcresult` |

세 번 모두 기존 test plan의 실기기 전용 UI skip과 선언된 expected failure만 남았다. 빌드에 연결된 저장소 범위 SwiftLint는 5~6개 기존 warning을 출력했으며 xcodebuild/test 결과에는 실패가 없었다. 이번 실행은 UI smoke·실기기 입력·CloudKit 로그인/왕복을 포함하지 않는다.

Tuist 생성 후 아래 명령을 같은 새 DerivedData에서 순서대로 실행했다. 세 명령 모두 `EXCLUDED_SOURCE_FILE_NAMES` 설정 없이 실행했다.

```bash
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -destination 'platform=iOS Simulator,id=0347221E-08F5-48C9-9F8E-6D7995C25D9F' -derivedDataPath /private/tmp/carve-2-0-0-candidate-unexcluded-derived -resultBundlePath /private/tmp/carve-2-0-0-candidate-unexcluded-ios17.5.xcresult -parallel-testing-enabled NO -quiet
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' -derivedDataPath /private/tmp/carve-2-0-0-candidate-unexcluded-derived -resultBundlePath /private/tmp/carve-2-0-0-candidate-unexcluded-ios18.6.xcresult -parallel-testing-enabled NO -quiet
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -destination 'platform=iOS Simulator,id=086F17F4-649B-4AE5-9C78-22659E0F93F6' -derivedDataPath /private/tmp/carve-2-0-0-candidate-unexcluded-derived -resultBundlePath /private/tmp/carve-2-0-0-candidate-unexcluded-ios26.2.xcresult -parallel-testing-enabled NO -quiet
```

### iOS 18 metadata migration marker 공개 근거 조사 (2026-09-24)

`PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`의 정확한 이름을 Carve 문서·소스와 Xcode 26.3 iOS Simulator SDK Core Data headers에서 검색했으나 정의를 찾지 못했다. Apple의 [NSPersistentCloudKitContainer 문서](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)에는 공개 container·event API가 설명돼 있고, [TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)은 동기화 내부 작업을 sysdiagnose 로그로 분석하는 자료다. 이 공개 자료만으로 private marker가 완료·진행 중 어느 상태를 뜻하는지, 행의 CloudKit 귀속에 어떤 의미를 갖는지는 입증되지 않는다. 따라서 metadata profile과 reader allowlist `[26]`은 유지한다. 이 조사는 private key 의미를 확정한 결과가 아니며, live CloudKit 시험도 수행하지 않았다.

따라서 iOS 18.6 집중·전체 자동 회귀는 최신 소스에서 통과했지만, 이것은 실제 1.3.0의 미지 marker를 허용하거나 계정 소유 proof가 안전하다는 증거가 아니다. 이 두 항목은 OS metadata의 의미 확인과 격리된 라이브 CloudKit 시험이 별도로 필요하다.

앞선 iOS 18 시험의 `CloudAccountIdentityClient`와 private-record lookup은 test double이므로 실제 로그인·private DB·CloudKit 왕복 증거가 아니다. `Carve-Ownership-iOS18-6`은 계정 없는 상태로 두며 iCloud 로그인은 요청하지 않는다. 의미가 확인되지 않은 migration marker가 존재하므로 현재 구현은 그 profile을 거절한다. iOS 26.2의 최신 전체 회귀와 Release configuration compile도 live CloudKit proof가 아니다.

추후 Apple의 공개 문서나 검증 가능한 OS별 관측으로 migration marker가 완료 상태를 나타내는지와 계정 귀속에 안전하게 쓸 수 있는 조건이 확인된 뒤에만 별도 프로필을 설계한다. 그때의 로그인 실험은 사용자가 `Carve-Ownership-iOS18-6`의 **설정 > Apple 계정 > 로그인**에서 DUT·B와 같은 sandbox 계정을 선택해야 한다. 이 조작은 Development private DB에 Genesis 1:3 합성 표식을 만들고, 같은 계정의 DUT·B를 재실행할 경우 해당 새 표식이 전파될 수 있다. 현재는 그 단계에 도달하지 않는다. 자격 증명을 에이전트에 입력하지 않는다.

**판정:** 허용 OS는 iOS 26뿐이다. iOS 18.6 자동 회귀가 통과해도 실제 1.3.0 migration marker의 의미와 계정 동기화 proof는 확인되지 않았으므로 iOS 18 소유는 열지 않는다. iOS 17.5 전체 회귀는 migration 수정 후 통과했지만 ownership proof·CloudKit 경로는 시험하지 않았다. iOS 17.0 직접 시험과 iOS 19~25 runtime·profile 근거도 없다. 2.0.0 출시 판정은 **NO-GO**다.

실제 필기 표본과 업데이트 전후 증거는 앞 절차의 관측을 이어 썼다. 사용자가 `Carve-ACC-dut`에서 로그아웃한 뒤 1.3.0 V3로 창세기 1장 1절 지그재그(27점, bounds x=36 y=23 w=86 h=27), 2절 고리(37점, bounds x=33 y=14 w=40 h=47)를 작성했다. V3 업데이트 전 `BibleDrawing`은 2행이며 SQLite blob은 655B·795B였다. 업데이트 후 로컬 V6 표본의 실제 필기 payload는 654B·794B, SHA-256 앞 16자리 `3a267e075d4d23e7`·`4f38e8eb0d805fa2`, 미러링 대응은 0건이었다. 두 획의 PencilKit 내용·좌표·화면 표시가 업데이트 전후 같았고, 원시 사본도 같은 지문을 가졌다.

이 표본은 로그아웃한 1.3.0 설치의 업데이트 경로다. **1.3.0에서 이미 iCloud에 로그인해 둔 상태로 2.0.0을 덮어 설치하는 별도 경로는 실행하지 않았다.** 출시 범위가 요구한 로그인 상태 업데이트 분기는 아직 미검증이다.

자동 회귀·후보 덮어 설치·미로그인 실행 뒤에도 DUT 저장소는 2행, 같은 내용·레이아웃 지문, 미러링 대응 0건이었다. 복사본은 `/private/tmp/carve-release-sync-evidence/snaps/dut-before-login`, `dut-after-automated-tests`, `dut-after-candidate-install`, `dut-after-final-candidate-launch`에 두었다. 최종 실행 화면(`/private/tmp/carve-release-sync-evidence/dut-after-final-candidate.png`)에서도 두 획이 표시됐다. 로그인 직후 DUT는 2행 그대로였고 미러링 표가 아직 없었다(`dut-after-account-login-pre-probe`). 앱을 재실행한 뒤 CloudKit에서 기존 행 15개를 받고 실제 표본 두 행에 대응이 생겨 총 17행·매핑 17건·업로드 대기 0건이 됐다(`dut-after-account-login-relaunch`).

로그인 전 서버 probe는 60초 내 완료되지 않아 서버 기준선은 얻지 못했다. 당시 B 로컬 13행을 서버 행 수로 간주하지 않는다. 이후 사용자가 두 시뮬레이터를 같은 시험 계정에 로그인시켰다. DUT 재실행 뒤 private DB probe는 `CD_BibleDrawing` 17개를 읽었고, Genesis 1:1은 654B / `3a267e075d4d23e7`, 1:2는 794B / `4f38e8eb0d805fa2`로 DUT 로컬 표본 payload와 각각 일치했다. B는 DUT export 전 15행에서 B 앱 재실행·probe 뒤 17행·매핑 17건으로 늘었으며 같은 두 payload 지문을 보유했다. 스냅숏은 `b-after-account-login-pre-probe`, `b-after-dut-server-export-before-probe`, `b-after-dut-first-export-and-b-probe`다. B 화면 캡처(`/private/tmp/carve-release-sync-evidence/b-after-dut-first-export.png`)에서도 1:1 지그재그와 1:2 고리가 보였다. AdMob 안내창은 본문 일부를 덮었지만 필기 획은 가리지 않았다. 서버 로그는 `0923-105645-probe-after-dut-login-first-export.log`와 B 조회용 probe 로그이며 계정 식별 원문은 문서에 기록하지 않았다.

첫 로그인 옛 필사의 서버 전송과 같은 계정 다른 iPad 수신 관문은 iOS 26.2 시뮬레이터에서 통과했다. 사용자가 두 시뮬레이터를 같은 시험 계정에 직접 로그인시켰다. DUT는 설정에서 돌아온 실행 중에는 전송하지 않았고, 앱 재실행 뒤 CloudKit 연결이 붙어 첫 export가 완료됐다. 서버 payload bytes 지문·B 저장소·화면이 일치했다.

일반 저장의 첫 방향도 확인했다. DUT에서 Genesis 1:7에 새 행을 만들었고 B는 다른 시점에 앱을 재실행한 뒤 같은 payload를 받았다. 로컬·서버·B의 payload는 모두 840B / `d4b13df878550d24`, 레이아웃 지문은 `933cf04e6b43b1a7`이었다. 이어 B에 후보 앱을 기존 컨테이너를 유지한 채 덮어 설치했고, 18개 행과 18개 매핑이 보존됐다. 후보 소유 ledger는 현재 계정 private DB 전체 레코드 조회에 근거해 `currentPrivateCloudRecords`로 기록됐다. 계정 식별 값은 관측·보고하지 않았다.

B에서 보고된 1:7 추가 획은 후보 설치 전 만든 미확인 초안이 이미 있는 절에 그린 것이었다. 화면에는 추가 획이 보였으나 canonical 행 지문과 초안 revision은 바뀌지 않아 저장·수정으로 인정하지 않았다. 기존 초안은 저장소 소유 근거가 없으므로 후보가 자동 업로드하지 않는다. 이 동작은 2.0.0 로그인 없는 신규 초안을 자동 귀속하지 않는 안전 규칙을 유지한다.

빈 절 Genesis 1:8의 일반 생성·전송은 통과했다. B의 새 행은 19행·19매핑 중 하나였고, 서버 private DB에는 `isPresent=1`, 965B / `261787e7b7ead104`로 있었다. 앱 재실행 뒤 DUT가 같은 rowUUID·payload를 받아 19행·19매핑, 업로드 대기 0건이 됐다. 서버 probe는 B에서, 일정 시간 뒤 fetch probe는 DUT에서 각각 실행했다. 저장소 사본은 `b-after-1-8-create-before-probe`, `b-after-1-8-server-export`, `dut-before-1-8-receive`, `dut-after-1-8-delayed-receive`이며 화면 캡처는 `/private/tmp/carve-release-sync-evidence/b-after-1-8-export.png`, `/private/tmp/carve-release-sync-evidence/dut-after-1-8-delayed-receive-settled.png`다.

역방향 수정과 지연 payload 수신은 통과했다. DUT에서 1:8에 두 번째 획을 더한 뒤 payload가 965B / `261787e7b7ead104`에서 1802B / `de5df55aa6147ab5`로 바뀌었고 layout metadata 지문은 `2bfaf8b7d683127c`였다. DUT의 재실행 probe는 private DB에 같은 payload와 metadata, `isPresent=1`을 확인했다. 30초 넘게 열린 B의 로컬 사본은 이전 965B payload였고, B 앱 재실행 후에는 1802B payload를 받았다. B의 local layout metadata 지문은 `2cd2d9d9c1ba25ca`로 서버·DUT와 달랐지만, 사용자가 B에서 Genesis 1:8을 확인해 두 획과 좌표가 맞게 표시됨을 확인했다(`/private/tmp/carve-release-sync-evidence/b-1-8-after-reverse-receive-visible.png`). 즐겨찾기 추가·해제와 일반 필사 지우기 왕복도 통과했다. 이 문장은 2026-09-22 당시 남은 확인 범위다. 2026-09-23 후속 검증에서 iOS 18의 제한된 V3 증거 판독을 추가했지만, iOS 18 실제 로그인 소유 증명·왕복과 로그인된 1.3.0 업데이트는 여전히 미검증이다. iOS 17과 설치 런타임이 없는 iOS 19~25는 계속 fail closed다.

즐겨찾기 추가·해제의 실제 저장 경로도 확인했다. B에서 Genesis 1:8을 즐겨찾기에 넣은 뒤 로컬은 즐겨찾기 1건·매핑 20건·대기 0건이었고, private DB probe는 Genesis 1:8 `CD_FavoriteVerse`를 포함한 활성 레코드 20건을 읽었다. 30초 뒤 DUT도 즐겨찾기 1건을 수신했다. B에서 즐겨찾기를 해제하자 로컬은 즐겨찾기 0건·매핑 19건이 됐고 서버는 그 레코드의 삭제 tombstone을 반환하며 활성 레코드 수가 19건으로 줄었다. 다음 30초 지연 수신 뒤 DUT도 즐겨찾기 0건·매핑 19건이 됐고 1:8 필사 payload는 1802B / `de5df55aa6147ab5` 그대로였다. 증거 사본은 `b-after-favorite-add-before-probe`, `dut-after-favorite-add-delayed-receive`, `b-after-favorite-remove-before-probe`, `dut-after-favorite-remove-delayed-receive`; server logs는 `logs/probe-favorite-add-after-export-run.txt`와 `logs/probe-favorite-remove-after-export-run.txt`다.

일반 「지우기」도 검증했다. B에서 1:8을 지운 뒤 서버에는 payload 없는 현재 행(`isPresent=1`)과 지워진 1802B payload 행(`isPresent=0`)이 남았다. 30초 뒤 DUT는 같은 상태를 20행·20매핑·대기 0건으로 받았고, 사용자는 1:8 화면이 비어 있음을 확인했다. 원래 1:1·1:2 표본도 표시됐다. 증거 사본은 `b-after-1-8-erase-before-probe`, `dut-after-1-8-erase-delayed-receive`; server logs는 `logs/probe-erase-1-8-server-export-run.txt`와 `logs/probe-erase-1-8-delayed-receive-run.txt`다. 남은 필수 실측 분기는 로그인 상태의 1.3.0 덮어쓰기다. 전체 출시 판정은 supported OS coverage 문제도 해결될 때까지 보류한다.

동시 두 iPad의 같은 절 편집을 양쪽 모두 보존하는 충돌 해결과 1.3.0·2.0.0 혼용 편집은 이번 출시 범위 밖의 알려진 제한으로 남긴다. 이 제한을 안전성 통과로 해석하지 않는다.

이 문서는 [동기화·백업 설계](./icloud-sync-and-backup-policy.md)의 실행 계획이다. 이번 후보 구현과 시험 결과는 §5-2에 기록했다. 기존 [호환성 결정](./data-compatibility-decision.md)의 U4·R27·R28을 통과로 바꾸지 않는다.

## 1. 검증 질문과 판정 원칙

1. 현재와 같이 `BibleDrawing` 행을 공유하면 1.3.0이 크래시하는가, 동기화가 중단되는가, 실행하면서 좌표·내용을 잘못 저장하는가?
2. 새 불변 버전 엔티티를 같은 개발 CloudKit 컨테이너에 추가해도 구버전의 기존 데이터 사용이 유지되는가?
3. 구버전의 편집·삭제가 새 원본을 변경하지 않으며, 새 앱은 관찰된 legacy 변경을 별도로 보존하는가?
4. 로컬 초안과 확정 버전 사이에 종료돼도 저장 완료로 보고한 필사가 복구되는가?
5. 과거 좌표 형식의 필사도 암호화 백업 왕복에서 보존되는가?

동일 기기의 DB 다운그레이드와 다른 기기에서의 CloudKit 수신은 별개 실험이다. 크래시하지 않았다는 사실만으로 통과하지 않으며, 구버전이 크래시하거나 동기화가 멈춘 것을 쓰기 차단 성공으로 보지도 않는다.

## 2. 환경과 준비 조건

### 2-1. 대상 빌드·기기

| 표기 | 구성 |
|---|---|
| OLD | 출시본으로 기록된 `49f2dc27`·1.3.0·스키마 V3. 출시 저장·표시 코드를 보존한 테스트 빌드 |
| CURRENT | 실험 시작 시점의 현행 커밋. 같은 가변 행을 공유하는 대조군 |
| NEW | 별도 불변 버전 모델·legacy 수용·로컬 초안을 넣은 최소 실험 후보. 전체 백업 UI는 불필요 |
| iPad A | OLD 설치, 테스트 전용 로컬 데이터 |
| iPad B | CURRENT 또는 NEW 설치. 대조군과 후보는 실험을 분리 |

두 iPad가 동일 테스트 Apple 계정, 동일 개발 CloudKit 컨테이너·환경을 사용해야 한다. 미지 필드·엔티티를 수신하는 구버전을 시험하려면 OLD 단독 상태로 먼저 데이터를 만든 뒤 새 스키마를 도입한다. 이미 새 스키마가 있는 환경만으로 최초 도입 결과를 대신하지 않는다.

**⛔ 선행 조건 — 전용 계정과 폐기 가능한 컨테이너 (2026-09-16 현재 미확보 → 2026-09-17 샌드박스 계정으로 확보, 아래 표).** 단계 A 이후는 이것 없이 시작하지 않는다.

| 항목 | 왜 필요한가 | 현재 |
|---|---|---|
| 테스트 전용 iCloud 계정 | 실사용 계정의 private DB 에 시험 레코드를 남기지 않기 위해 | ✅ **2026-09-17 샌드박스 계정** — 시뮬레이터 두 대(§6)에 같은 샌드박스 계정으로 로그인했다. 실사용 계정과 분리된다. ⚠️ CloudKit 콘솔은 샌드박스 계정의 private DB 를 열어 주지 않는다 — 서버 필드는 §5-1 의 조회 도구로 읽는다 |
| 폐기 가능한 CloudKit 컨테이너 | 시험이 끝나면 통째로 버릴 수 있어야 한다. 배포한 레코드 타입은 Production 에서 지울 수 없다 | ⚠️ **2026-09-17 사용자 결정** — dev 컨테이너(`iCloud.Carve.SwiftData.iCloud.dev`, Debug 빌드 · `Carve.dev.sqlite`)는 지우거나 고쳐도 된다. 연결된 iPad 한 대로 쓴다. 단 **같은 계정의 private DB 라 계정 격리는 아니고**, 두 번째 클라이언트도 아직 없다 → 2026-09-17 부터 샌드박스 계정으로 이 컨테이너를 써서 실사용 계정의 dev 데이터와 섞이지 않는다. 두 번째 클라이언트는 시뮬레이터로 해결했다(CK-A0) |
| 환경·zone 확인 | 컨테이너 ID 뿐 아니라 Development/Production 환경과 zone 까지 맞는지 | ⚠️ **부분 확인 (2026-09-17)** — zone 은 `com.apple.coredata.cloudkit.zone`(조회 도구 · 미러링 메타데이터). 환경은 **Development 로 추정**한다 — 시뮬레이터 Debug 빌드이고 환경을 지정하는 엔타이틀먼트가 없다. 콘솔 교차 확인은 샌드박스 계정이라 하지 못했다 |

⚠️ **로컬 파일이 갈린 것과 서버가 격리된 것은 다르다.** Debug 빌드가 `Carve.dev.sqlite` 를 쓴다고 해서 CloudKit 까지 안전한 것이 아니다. dev 컨테이너(`iCloud.Carve.SwiftData.iCloud.dev`)도 **같은 iCloud 계정의 private DB** 이고 개발 중 쌓인 데이터가 이미 있다. 파일명만 보고 "격리됐다" 고 판단하지 않는다.

실사용 계정·운영 레코드에는 편집·삭제 시험을 하지 않는다. 기존 개발 컨테이너에 개인 데이터가 있다면 시험용 컨테이너를 별도로 준비한다. 계정·서명·권한 변경은 필요 범위를 기록하고 별도 승인 규칙을 따른다. 구버전 테스트를 이유로 사용자 앱을 지우거나 운영 CloudKit 스키마를 초기화하지 않는다.

**2026-09-16 확인 — OLD 재빌드가 된다.** `49f2dc27` 을 worktree 로 떼어 `.mise.toml` 이 고정한 tuist 4.39.0 으로 `install` → `generate` → `build` 가 **코드 수정 없이** 통과했다(Xcode 26.3 / 17C529). 이 문서의 OLD 케이스 전부를 막고 있던 선행 불확실성이 해소됐다. 기록은 §5-1 PRE-0.

OLD를 테스트용으로 다시 빌드해야 하면 컨테이너·서명·관측용 변경만 최소 적용하고 diff를 보관한다. 현재 SDK로 재빌드한 OLD는 실제 출시 바이너리와 완전히 같지 않으므로 결과에 이 제한을 적는다. 빌드가 안 된다는 이유로 저장·모델 코드를 고쳐 놓고 1.3.0 검증이라고 부르지 않는다.

Xcode 경로·버전은 실행 시 확인한다. 현행 2.0.0 후보는 기본 선택된 Xcode 27.0 / macOS 27.2를 주 검증 대상으로 삼는다. Tuist workspace Debug build와 iPadOS 17.5·18.6·26.2·26.4·26.5·27.0 전체 회귀가 통과했다. iPadOS 27.0의 초기 다섯 실패는 SwiftData 오류 처리 수정과 후속 전체 회귀에서 해결됐으며, 최초 F60 `ProcessXCFramework` 실패도 workspace 경로에서 재현되지 않았다(날짜별 명령·로그·결과는 아래에 기록). Xcode 26.3 결과는 과거 회귀 비교 근거로 표시하며 현행 후보 통과로 간주하지 않는다. Device Hub는 기기 확인과 수동 스모크에 사용하고 자동 테스트는 CLI로 수행한다. Tuist는 각 checkout의 고정 버전을 `mise x -- tuist`로 실행한다. OLD의 툴체인·의존성 제약이 다르면 먼저 기록한다. 일반 테스트는 iPad destination을 사용한다. 실제 동기화 검증에는 **독립 저장소를 가진 클라이언트 두 개**가 필요하며 한 대나 인메모리 테스트로 통과를 대신하지 않는다. 시뮬레이터는 CK-A0 에서 실제 양방향 동기화를 확인한 경우 쓸 수 있고, 최종 출시 후보의 실기기 검증 필요 여부는 별도로 기록한다.

### 2-2. 표본

개인 필사 대신 고유한 테스트 표식을 가진 합성 필사 또는 시험용 손글씨를 사용한다.

| 표본 | 목적 |
|---|---|
| L1 | OLD로 작성한 필사: legacy 좌표, 메타데이터·rowUUID 없음 |
| L2 | 같은 절의 보관·현재 필사 여러 행, 비어 있는 현재 행 |
| L3 | 같은 business ID지만 내용이 다른 행을 격리 환경에서 주입: 잘못된 병합 방지 |
| N1 | CURRENT의 좌표 형식 3과 메타데이터를 가진 행: R28 대조 실험 |
| N2 | NEW의 새 불변 버전: 부모·자식·동시 분기·복원 선택 |
| E1 | 빈 drawing, 지우개로 획 0개, 손상 payload·미지원 좌표 형식 |
| B1 | legacy와 새 형식, 현재·보관·충돌을 함께 가진 백업 표본 |

L3·손상 표본 주입용 코드가 없으면 최소 테스트 도구를 다음 세션에 작성한다. 도구가 이미 존재한다고 가정하지 않는다. 폭·회전 변환과 원본 보존을 구분하기 위해 세로·가로 기준 화면을 함께 남긴다.

### 2-3. 관측 자료

- 빌드 커밋·테스트 변경 diff·기기 OS·환경을 기록한다. 계정은 별칭만 사용한다.
- 양쪽 로컬 원본의 해시, 좌표 형식, 메타데이터 해시, 논리 ID·부모 ID·상태·건수·저장 성공 시각을 비교한다. 출처 ID가 불안정하면 매핑 방법을 기록한다.
- 원본 bytes 비교와 표시용 변환 후의 화면 비교를 구분한다. bytes 재인코딩이 있는 경로는 획·좌표·메타데이터 의미도 비교한다.
- import/export의 시작·종료·성공·오류와 앱 생존·크래시 로그를 남긴다. 이벤트 성공 하나만으로 해당 표본 도착을 인정하지 않는다.
- 구버전이 모르는 필드의 보존 여부는 NEW의 재조회와 필요한 개발 CloudKit 레코드 조회로 확인한다. 실제 iCloud 필드 조회를 못 하면 해당 판정은 미확인이다.

각 전송은 수신 기기에서 예상 표본을 재조회한 것이 완료 증거다. 실행당 관찰 예산은 예를 들어 5분으로 기록하고, 기한 내 미수신이면 ‘관찰 시간 내 미수신·판정 보류’로 남긴다. 5분은 제품의 타임아웃이나 CloudKit SLA가 아니다. 실패 로그가 있으면 지연과 구분하고, 네트워크·계정·환경을 확인한 뒤 재실행 조건을 기록한다.

## 3. 실행 순서

### 단계 L — CloudKit 없이 먼저 확인하는 로컬 마이그레이션

테스트 계정도 기기 두 대도 필요 없는 범위다. 여기가 깨지면 CloudKit 단계는 볼 필요가 없다.

| ID | 절차 | 확인할 결과 |
|---|---|---|
| MIG-L0 | 한 기기에 OLD 설치 → 직접 필사 → **앱을 지우지 않고** CURRENT/NEW 덮어 설치 → 같은 장 조회 | 행·필드 보존, 좌표 형식 유지, 화면상 필기 위치. **수행 완료 — §5-1** |
| MIG-L1 | 실기기의 **실사용 store 를 그대로 관측**한다. 왕복을 새로 만들지 않는다 — TestFlight 로 2.0.0 을 설치한 시점에 이미 일어났다 | 마이그레이션 결과·좌표 형식 분포·행 규모·화면. **수행 완료** — §5-1 |
| DOWN-L2 | **역방향** — V5 로 올라간 store 에 OLD 를 덮어 설치한다. 단계 A 의 시간 분할이 매번 무엇을 요구하는지 정한다 | 앱이 열리는가·데이터는 어떻게 되는가. **수행 완료 — §5-1** |

MIG-L0 의 표본은 두 절뿐이다. 통과를 "실사용 데이터가 안전하다" 로 일반화하지 않는다.

### 단계 A — 현재 공유 행의 실제 위험 확인

이 단계는 결함 대조군이다. 문제가 재현돼도 NEW 후보 실패와 혼동하지 않는다.

**클라이언트 두 개를 어떻게 만드나.** 실기기 두 대가 없으므로 **독립된 저장소를 가진 클라이언트 두 개**가 필요하다. iPad 시뮬레이터 두 대에 OLD 와 NEW 를 각각 유지하는 구성을 먼저 시험한다. 다만 시뮬레이터는 **CK-A0 에서 실제 양방향 CloudKit 동기화를 확인한 경우에만** A·B 실험에 쓴다. 최종 출시 후보에 실기기 검증이 필요한지는 별도로 기록한다. ✅ **2026-09-17 CK-A0 에서 양방향 전송을 확인했다** — `Carve-CK-A-old` · `Carve-CK-B-upgrade`(§6)로 A·B 실험을 진행한다.

⚠️ **시뮬레이터는 개별 오프라인을 만들 수 없다.** `simctl status_bar --wifiMode` 는 **상태바 아이콘만** 바꾸고 실제 연결은 호스트 네트워크를 그대로 쓴다. `simctl` 에 네트워크 차단 옵션이 없다. 그래서 오프라인 편집은 **두 클라이언트를 동시에** 오프라인으로 만든 뒤 각자 편집하는 방식으로 만들고, 아래 순서를 지킨다.

1. **활성 네트워크 경로를 모두 차단한다.** Wi-Fi 만 끄는 것으로는 부족하다 — 유선(이더넷·USB 테더링 등)이 살아 있으면 호스트는 계속 연결된 상태다.
2. 같은 부모 버전에서 양쪽이 각자 편집한다.
3. 양쪽 모두 **로컬 저장이 끝났고 내용이 서로 다른지** 확인한다.
4. **양쪽 앱을 종료한다.** 네트워크를 복구할 때 두 앱이 함께 살아 있으면 순서를 만들 수 없다.
5. 네트워크를 복구한다.
6. A 를 실행하고 **그 표본이 서버에 반영됐는지** 확인한다.
7. B 를 실행하고 실제 전달 순서를 기록한다.

앱 종료는 **순서를 만들기 위한 조치**일 뿐이다. 순서가 실제로 성립했다는 판정은 아래 관측으로 내린다.

⚠️ **이 Mac 의 네트워크를 끊으면 시험을 돕는 에이전트(Claude Code)도 함께 끊긴다 (2026-09-17 정리).** 1~5 는 사람이 조작하고(앱 종료는 `xcrun simctl terminate` 로 네트워크 없이 할 수 있다), 에이전트는 복구 뒤 3 의 로컬 저장 대조와 6·7 의 관측을 맡는다. 네트워크를 끊지 않는 변형은 §5-1 F8 을 참고하되 별도 케이스로 기록한다(§6).

⛔ **재연결 순서를 앱 실행 순서로 갈음하지 않는다.** `NSPersistentCloudKitContainer` 의 import·export 는 비동기이고 실행 시점을 시스템이 정한다. A 를 먼저 실행했다고 A 의 export 가 끝난 뒤에 B 가 연결된다는 보장이 없다. 순서는 **관측으로 확정한다.**

1. A 의 export 종료 이벤트와 **서버 레코드 변경**을 확인한다.
2. 그 뒤에 B 를 실행한다.
3. B 의 import·export 순서를 기록한다.
4. 반대 순서로도 같은 절차를 반복한다.
5. **실제 전달 순서를 확인하지 못하면 CK-A4 · B5 · B8 은 판정 보류다.**

⛔ **U4 검증에 DOWN-L2 상태의 OLD 를 쓰지 않는다.** V1 폴백을 탄 저장소가 서버의 `CD_BibleDrawing` 을 어떻게 다루는지는 **아직 관측하지 않았다.** 확실한 것은 **그 OLD 가 동일 레코드를 수정했다는 증거가 없다**는 것뿐이고, 그 상태에서 원본 필드가 그대로인 것을 "구버전이 미지 필드를 보존했다" 로 읽으면 오판이다. 그러므로 U4 판정에는 쓰지 않는다.

**U4 의 기본 경로는 OLD 저장소를 그대로 유지하는 것이다.** A·B 를 모두 OLD 로 맞춘 뒤 **B 만 CURRENT 로 업데이트**하고, A 는 **기존 V3 저장소를 유지한 채** 수신·수정한다(CK-A1~A3 의 구조가 이미 그렇다). 앱을 지우고 새로 설치하는 경로는 "신규 설치·전체 가져오기" 라는 **별도 케이스**로 두며, 기본 경로를 대신하지 않는다 — 앱 삭제를 필수로 만들면 확인하려던 증분 동기화 경로를 스스로 없애게 된다.

| ID | 절차 | 확인할 결과 |
|---|---|---|
| CK-A0 | OLD만 설치한 상태에서 L1 생성 → 다른 기기에서 기존 스키마로 수신 | 기본 계정·환경·전송이 동작하는지 먼저 확인 |
| CK-A1 | B를 CURRENT로 업데이트 → 기존 L1 조회 | legacy 원본과 표시 유지. 마이그레이션 자체의 문제를 분리 |
| CK-A2 | CURRENT에서 같은 절 편집해 N1 저장 → OLD에서 조회·재실행 | 크래시·동기화 오류·좌표 오표시·정상 표시를 각각 기록 |
| CK-A3 | OLD에서 수신된 행에 표식 추가·지우기 → CURRENT에서 수신 | 내용·`drawingVersion`·메타데이터·rowUUID 전후 비교. 라벨과 좌표 불일치 및 U4 확인 |
| CK-A4 | 양쪽 오프라인에서 같은 원본 수정 → A 먼저, 다음에는 B 먼저 재연결 | 승자·유실·중복·대표 선택 결과 기록. 특정 도착 순서를 안전성 근거로 삼지 않음 |
| CK-A4b | **CK-A4 의 온라인 변형 (2026-09-17 추가).** 두 앱을 같은 부모로 켜 둔 채 한쪽이 먼저 편집해 업로드하고, 그것을 모르는 다른 쪽이 같은 절을 편집한다(F8 — 켜 둔 앱은 재실행 전까지 가져오지 않았다). 순서를 바꿔 반복한다. 두 번째 작성자는 자기 저장이 끝날 때까지 재실행하지 않는다 | 승자 · 유실 · 중복 · 라벨. 순서는 업로드 · 가져오기 로그 시각으로 확정한다. **CK-A4 를 대체하지 않는다** |
| CK-A4c | **CK-A4b 를 2.0.0 끼리 (2026-09-17 추가).** 세 번째 시뮬레이터 C 에 CURRENT 를 설치해 B 와 짝짓고, 같은 방법으로 순서를 바꿔 반복한다 | 1.3.0 이 섞이지 않아도 같은 결과인지 |
| CK-A5 | **R27 (2026-09-17 추가).** 비어 있는 절에 두 앱이 서로 모르는 채 각자 필기한다(CK-A4b 와 같은 방법) | 행 중복 여부, 기기별 대표 선택, 가려진 필기 |

⚠️ **OLD 를 깔 때마다 그 기기의 NEW 로컬 데이터는 사라진다(F7).** V5 store 를 OLD 가 열지 못하고 V1 스키마로 갈아치우며, 그 과정에 경고도 크래시도 없다. 그러므로 한 기기에서 OLD ↔ NEW 를 번갈아 쓰는 시간 분할은 **매번 로컬이 초기화된 상태에서 시작**한다고 전제한다. 이때 **로컬 변경 토큰과 미러링 메타데이터는 유실될 수 있다.** 다만 다음 실행이 실제로 전체 import 인지, 서버에 남은 기존 구독을 재사용하는지 새로 만드는지는 **관측 전에 단정하지 않는다** — 서버 측 subscription 은 로컬 저장소 초기화로 사라지는 객체가 아니다. 실제 이벤트와 서버 상태로 확인한다. 또한 **V1 스키마가 된 store 가 CloudKit 에 붙었을 때의 거동이 미확인**이다 — 서버에는 `CD_BibleDrawing` 이 있는데 클라이언트는 `CD_DrawingVO` 를 기대한다. 이 관측은 **A1~A3 의 선행 조건이 아니다.** 기존 V3 저장소를 유지하는 경로에는 V1 폴백이 나타나지 않으므로, **별도 격리 시험 환경에서 따로** 수행한다(§6).

⚠️ **OLD 는 절을 저장할 때마다 `BiblePageDrawing` 도 쓴다**(`CombinedCanvasFeature` 의 `upsertPageDrawing`). 그런데 그 CloudKit 레코드 타입은 2026-09-09 에 지웠고, 로컬 실측에서도 그 테이블은 **0행**이었다(§5-1 MIG-L0). A2·A3 에서 동기화 오류가 보이면 **새 스키마 탓으로 먼저 돌리지 말고** 이 경로부터 분리해 기록한다.

A2에서 크래시하면 A3는 진행 불가로 남기고 크래시 위치·원본을 수집한다. A2가 정상이라고 A3를 생략하지 않는다. A에서 새 스키마를 도입한 OLD와 처음부터 새 환경을 만나는 OLD를 각각 확인한다.

### 단계 B — 별도 버전 모델의 최소 적합성 시험

대조군과 분리된 시험 데이터로 시작한다. 단순 엔티티 추가만이 아니라 최소 읽기·쓰기·legacy 후보 보존이 가능해야 한다.

| ID | 절차 | 통과 기준 |
|---|---|---|
| CK-B1 | OLD로 L1 생성 → NEW 수용 → NEW에서 N2 생성 → OLD 재실행·기존 필사 편집 | OLD의 기존 기능·동기화가 유지되고 NEW 원본은 수정되지 않음. N2가 OLD에 표시되지 않는 것은 의도된 제한 |
| CK-B2 | OLD가 기존 L1 수정 → NEW 수신 → 다시 편집 | 새 후보가 남고 NEW의 현재 필사를 자동 교체하지 않음. 원본 좌표 정보 보존 |
| CK-B3 | OLD의 단건 삭제 또는 가능한 지우기, 별도 실험에서 전체 데이터 삭제 | 이미 보존된 NEW 원본·이력 유지. 실제 제공되는 동작만 실행하고 삭제 범위를 확인 |
| CK-B4 | A·B 모두 NEW로 업데이트 → 같은 L1 수용·재실행 | 동일 legacy의 논리 중복 없음. L3의 서로 다른 내용은 잘못 합치지 않음 |
| CK-B5 | 두 NEW가 같은 부모에서 오프라인 편집 → 역순 재연결 | 양쪽 버전 보존, 분기 판정과 최종 조회가 수렴 |
| CK-B6 | OLD가 오프라인에서 여러 번 편집 후 연결 | 실제로 수신한 최종 상태를 보존. 수신하지 못한 중간 상태까지 복구했다고 주장하지 않음 |
| CK-B7 | 새 스키마가 이미 존재하는 환경에서 OLD 최초 설치·수신 | 기존 데이터 로드·편집·동기화 유지, 새 엔티티로 인한 크래시 없음 |
| CK-B8 | 부모보다 자식 먼저 전달, 동시 복원 선택, 한쪽 지우기·다른 쪽 편집 | 조기 삭제·분기 유실·임의 현재 필사 교체 없이 수렴. 순서 제어는 저장소 테스트로도 검증 |

OLD의 실제 전체 삭제가 특정 모델 삭제인지 컨테이너·존 삭제인지 먼저 코드로 확인한다. 제공되지 않는 삭제 동작을 대신 주입한 결과는 별도의 강건성 시험으로 기록한다. 시험용 레코드만 삭제한다.

### 단계 C — 초안 내구성과 캔버스 마지막 변경

> **2026-09-17 리뷰 — 단계 C 전체를 외부 조건으로 묶지 않는다.** 이 단계의 대부분은 **iCloud 계정 · 두 번째 클라이언트 없이** 시험 앱 한 대에서 수행한다.
> 외부 조건(§2-1 전용 계정 · 폐기 가능한 컨테이너)을 기다리는 것은 원격 수신을 결합하는 **SAVE-C7 뿐**이다.
>
> | 케이스 | 무엇이 있어야 하나 |
> |---|---|
> | SAVE-C1~C4 | 초안 · 확정 버전 저장 구현(NEW). 계정 불필요 |
> | SAVE-C5 · C6 · C8 | 현재 저장 경로(flush · trailing 보고 · 저장 실패 안내)로 **대부분 시험할 수 있다**. C6 의 최대 대기 경로처럼 새 설계가 정하는 부분은 구현 뒤 다시 본다. 계정 불필요 |
> | SAVE-C7 | 원격 새 버전 수신 — §2-1 선행 조건 필요 |

장·절·버전 ID를 포함한 결정적 fixture와 종료 주입 지점을 만든다. 강제 종료는 시험 앱 프로세스만 대상으로 하며 사용자 앱에 수행하지 않는다.

**종료 지점을 시간으로 정하지 않는다.** "몇 초 기다렸다가 종료" 로는 저장 전후 어느 구간을 검증했는지 알 수 없다. 아래 네 지점에 **테스트 전용 중단점**을 두고, 각 지점에 도달했다는 신호를 확인한 **뒤에** 프로세스를 죽인다.

| 중단점 | 대응 케이스 |
|---|---|
| 초안 저장 직전 | SAVE-C1 |
| 초안 저장 완료 직후 | SAVE-C2 |
| 확정 버전 ID·payload 를 내구성 있게 기록한 직후 | SAVE-C3 |
| 확정 버전 저장 완료 후, 초안 완료 처리 직전 | SAVE-C4 |

각 회차의 검사는 **새 프로세스에서 저장소를 다시 열어** 수행한다. 같은 프로세스의 메모리 상태로 판정하지 않는다. 확인할 것은 ① 복구된 내용 ② 같은 논리 ID 의 **중복 생성 여부** 두 가지다.

**정상 종료와 강제 종료를 같은 케이스로 묶지 않는다.** 백그라운드 전환에 따른 정상 저장(앱이 마무리할 기회를 받는 경우)과 강제 종료(마지막 callback 이 없는 경우)는 보장 범위가 다르므로 각각 기록한다.

| ID | 종료·실패 지점 또는 조작 | 통과 기준 |
|---|---|---|
| SAVE-C1 | 초안 커밋 전 종료 | 마지막 성공 저장까지 유지. 아직 커밋하지 않은 변경을 저장 성공으로 표시하지 않음 |
| SAVE-C2 | 초안 커밋 후 확정 전 종료 | 재실행 시 전체 초안과 기준 버전 복구 |
| SAVE-C3 | 확정 ID·payload 기록 후 버전 저장 전 종료 | 같은 ID로 재시도, 중복·유실 없음 |
| SAVE-C4 | 버전 커밋 후 초안 완료 처리 전 종료 | 이미 생성한 버전을 재사용하고 완료 처리 |
| SAVE-C5 | 마지막 변경 후 0.3초 이내 비활성화·장 전환 | 큐에 전달되기 전 마지막 캔버스 변경까지 수집·저장. 이후 재실행 비교 |
| SAVE-C6 | 연속 필기·긴 획·지우개·올가미·Undo/Redo | 최대 대기 경로가 실제 저장하며 도구 종료·레이아웃 상태를 잘못 바꾸지 않음 |
| SAVE-C7 | 초안 복구 전 원격 새 버전 수신 | 초안이 원래 부모의 별도 분기로 복구되고 원격 결과도 유지 |
| SAVE-C8 | 디스크 부족·인코딩·쓰기 실패 | 성공 오표시 없음, 재시도 가능, 기존 성공 데이터 유지 |
| SAVE-C9 | 초안 누적(②) — 장 이동 · 재실행 · 계정 전환을 반복 | ② 는 초안을 지우지 않는다(정책 §12-3 F29 결정). **남는 초안 세션 수 · 파일 수 · 총 바이트(blob 증가량)**를 짧은 절과 긴 장에서 측정해 기록한다. 보이지 않는 초안 개수 안내 · 복구 진입점(④)과 2.1 보관 정책의 입력이다 — 수치 없이 "용량 문제 없음" 으로 적지 않는다 |

2초·10초·30초 값은 실험 시작점이다. 적어도 짧은 절과 긴 장에서 각각 연속 필사 세션을 측정해 저장 지연·프레임 영향·메모리·버전 수·파일 크기를 기록한다. 채택 임계값은 사용자가 체감하는 필기 품질과 용량 예산을 기준으로 구현 세션에서 명시하고, 수치 없이 ‘성능 통과’로 기록하지 않는다.

### 단계 D — 백업 왕복·권한·계정 〈2.1 범위〉

> **2026-09-16 범위 변경 — 이 단계는 2.0.0 검증에서 분리한다.** 필사 백업 기능이 2.1 로 이관됐으므로
> 아래 케이스는 그 구현과 함께 수행한다. 2.0.0 출시 판정은 단계 A~C 로 한다.
>
> 단, **시험 전 데이터 보호를 위한 백업 절차는 제품 기능과 별개로 지금도 필요하다** — 실사용 저장소를
> 건드릴 수 있는 시험 앞에서는 매번 사본을 떠 둔다(§5-1 MIG-L1 이 그 예다).

| ID | 절차 | 통과 기준 |
|---|---|---|
| BACKUP-D1 | B1 암호화 내보내기 → 빈 시험 저장소에 불러오기 | 지원 대상의 원본·좌표 형식·메타데이터·계보·건수 일치, 실제 표시 확인 |
| BACKUP-D2 | 기존 최신 필사 위에 B1 불러오기·반복 불러오기 | 현재 필사 유지, 후보 보존, 논리 중복 없음 |
| BACKUP-D3 | 두 NEW에서 같은 파일 오프라인 불러오기 → 연결 | 동일 버전은 논리적으로 하나, 다른 내용은 보존 |
| BACKUP-D4 | 잘못된 암호·변조·잘림·미지원 형식 | 실제 데이터 적용 전에 거부, 평문·암호 로그 없음 |
| BACKUP-D5 | 다른 테스트 계정 또는 미로그인 상태에서 파일과 암호로 복구 | 계정·구매 제한 없이 복구. 연결 시 동기화 안내와 실제 범위 일치 |
| BACKUP-D6 | 불러오기 도중 종료·취소·공간 부족 → 재시도 | 적용 범위 명확, 중복·기존 데이터 유실 없음 |
| BACKUP-D7 | 광고 제거 기존 구매자와 미구매 상태 | 기존 구매자는 생성 가능, 모두 검사·불러오기 가능 |

계정 변경 실험은 전용 기기 또는 시험 데이터만 있는 상태에서 수행하고, 기존 로컬 필사가 새 계정으로 묵시적으로 전송되는지도 별도 기록한다. 이 결과는 파일 불러오기 허용과 별개의 출시 조건이다.

### 추가 확인 항목 (2026-09-17 리뷰)

외부 리뷰가 목록에 없다고 짚은 항목이다. 백업(단계 D)과 무관하게 **2.0.0** 에서 판정한다.

| ID | 확인할 것 | 통과 기준 | 외부 조건 |
|---|---|---|---|
| ACC-1 | 기기의 Apple 계정을 바꾼 뒤 기존 로컬 필사가 어느 계정에 귀속되고 새 계정으로 전송되는지(**2차 계획 — §3-2**). **계정 범위**(초안 · 복구 사본 · 격리본 · 보존 기록 · 삭제 작업 기록 · K)가 분리되는지, 삭제 작업 도중 전환하면 새 계정에서 재개하지 않는지, 계정을 확인할 수 없을 때 서버 정리 · 업로드를 보류하는지(정책 §12-6 C11) | 묵시적 전송 없음, 로컬 보존 방식이 정책과 일치, 다른 계정 범위의 작업 · 사본이 섞이지 않음 | 전용 계정 두 개(§2-1). **1차 수행 — §5-1**(앱을 끈 채 A→B · 켠 채 B→A · 미전송 편집을 둔 A→B→A · 로그아웃 필기 뒤 B 로그인, F25 ~ F30) |
| SEP-0 ~ SEP-6 | **1.3.0 무계정 legacy 행 분리**(정책 §12-6 C14)의 판정 · 삭제 전파 · 중단 복구 · 보류 차단 · 표시 · 가져오기 · 성능 | 대응 없는 행의 삭제가 전파되지 않고, 분리 대상과 무관한 레코드에 예상 밖 변경 · 삭제가 없다. **SEP-0 ~ SEP-2 통과 전에는 파괴적 분리를 구현하지 않는다** | 전용 계정 두 개 · OLD(V3) 표본 넷. 설계는 §3-3 |
| MIG-F1 | 로컬 저장소 준비 실패 · V1 폴백(F7) 상태에서 편집 화면에 들어가는지 | 정상 저장이 불가능한 채 편집 화면에 진입하지 않음(정책 §3 표 4행) | 없음 — 단계 L · DOWN-L2 와 같은 방법. **1차 수행 — §5-1** (수정 전 실패 · 1차 수정 후 통과, 실기기 미확인). **2026-09-17 리뷰 반영 진행 중 — §5-1 인계** |
| UPD-W1 | 필사 칸 폭(`writingWidth`) 계산이 바뀌는 업데이트 뒤 기존 필사 위치 | 기존 획이 자기 절 · 같은 상대 위치에 놓임 — **업데이트 데이터 호환성**으로 판정 | 없음 |

### 3-1. ACC-1 — 저장소 소유 근거 실험 설계 (2026-09-18, 8차 리뷰)

**왜:** 편집을 계정에 귀속하려면 불러온 데이터가 그 계정의 것이라는 근거가 필요하다(정책 §12-6 구현 순서 ①). 계정 확인이 끝났다는 것도, 마지막으로 확인한 계정과 같다는 것도 근거가 아니다 — 확인이 끝나도 로컬 저장소에는 이전 계정의 필사가 남아 있을 수 있다. 근거가 없는 동안 모든 세션은 **보존만**이다(② 부터 새 필기는 초안에만 남는다). **근거를 얻는 방법은 이 실험으로 검증한 것만 채택하고, 그 전까지 소유 근거는 시험에서만 주입한다.**

**후보와 한계**

| 후보 | 잘못 소유를 인정하는 경우 | 쓰는 방식 |
|---|---|---|
| A. CloudKit 미러링이 저장소 메타데이터에 적는 계정 식별 | 메타데이터는 B 로 바뀌었지만 A 의 행 · 캐시 · 미처리 작업이 남아 있음. 값이 "지금 연결한 계정" 을 뜻할 뿐 모든 행의 출처를 뜻하지 않을 수 있음 | **소유 근거로 채택하지 않는다(2026-09-18, 9차 리뷰) — 진단 · 불일치 탐지에만 쓴다.** F25 에서 식별 변경과 행 삭제가 한 단계가 아니었고, F30 은 식별 없는 행을 다음 계정이 가져가는 경로이며, 쓰기 직전의 일치 검사도 그 뒤 미러링 전환과 원자적으로 묶이지 않는다 |
| B. 동기화되는 저장소 소유 표식 레코드 | B 표식이 먼저 도착하고 A 행이 남아 있음. A 데이터가 남은 저장소에 앱이 B 표식을 직접 만들었음. B 서버에 표식이 있다는 것도 로컬의 모든 행이 B 의 것이라는 증명이 아님 | **불일치는 차단 근거, 일치는 충분조건이 아니다.** 표식과 필사 행의 수신 · 삭제 순서가 같다는 보장이 있어야 쓴다 |

- **채택 조건은 "몇 번 시험에서 일치했다" 보다 강해야 한다.** 메타데이터 · 표식이 바뀌는 동안에도 다른 계정의 행을 귀속하지 않는 구조적 경계가 필요하다.
- 그런 경계가 확인되지 않으면 **앱이 관리하는 계정별 저장소 분리**나 **명시적 데이터 수용 경계**(식별 없는 데이터는 사용자가 고른 뒤에만 계정 데이터가 된다)를 검토한다 — 기존 무표식 데이터는 따로 보존하고 명시적 가져오기로 다룬다. 계정별 저장소도 **미러링 연결 수명**(연결 · 해제 · 재연결 사이에 도착한 쓰기)과 함께 검증한다.
- **사용자 확인 UI** 는 "누구의 데이터였는지 증명" 이 아니라 **"이 사본을 지금 계정으로 가져오겠다" 는 새 결정**으로 설계한다(④).
- 앱에서 확정을 막는 것과 CloudKit 미러링이 멈추는 것은 다르다 — 둘을 나눠 관측한다.

**후보 B 의 부트스트랩**
- 앱이 새로 만든 빈 저장소: 확인된 계정에 연결한 저장소라는 근거를 로컬에 먼저 적고 표식을 만든다. 표식은 그 사실의 보조 기록이다.
- 1.3.0 에서 올라온 데이터가 있는 저장소: 지금 계정 이름으로 표식을 붙여 기존 데이터의 소유까지 확정하지 않는다. 별도 근거나, 대상을 보여 주는 명시적 가져오기가 필요하다.
- 계정 전환 중 비워진 것처럼 보이는 저장소: 행 수 0 만으로 초기화가 끝났다고 보지 않는다 — 아직 도착하지 않은 행이나 지연 작업이 있을 수 있다.

**순서와 관측** — A · B 계정의 같은 절에 서로 알아볼 수 있는 다른 잉크를 넣는다.
- 앱 실행 중 A→B, 앱 종료 중 A→B, A→로그아웃→A, A→B→A
- A 의 미전송 편집이 있는 상태와 모두 전송된 상태를 각각
- 네트워크를 끊은 채 전환한 뒤 재연결 — import · export 순서를 기록
- 계정 조회 완료 · 메타데이터 변경 · 표식 수신 · 행 삭제 사이에서 종료 후 재시작
- 무표식 legacy 저장소, 빈 새 저장소, 표식과 행이 섞여 남은 상태
- 각 시점에 **계정 확인 결과, 저장소 식별, 표식, 원본 행 해시, K, 편집 세션 근거, 양쪽 서버의 실제 레코드**를 함께 대조한다. 행 수와 import 성공만으로 판정하지 않는다
- 계정 식별 원문은 로그에 남기지 않고 시험 별칭(A · B)으로 적는다

**준비:** 두 번째 샌드박스 계정(사용자가 만들고 시뮬레이터에 로그인), 서로 다른 잉크 표본, `tools/cloudkit-observe` 의 서버 조회 · 저장소 비교.

### 3-2. ACC-1 2차 — ②-2 보완 빌드로 다시 (계획, 2026-09-18 9차 리뷰 · 10차 리뷰 보완)

**왜:** 1차(§5-1)는 ②-1 빌드(저장을 아직 `BibleDrawing` 에 함)로 세 가지 실패를 재현했다 — 낡은 화면의 필기가 기존 필기를 가림(F26 · F27), 전송 전 편집의 유실(F29), 로그아웃 필기의 자동 귀속(F30). ②-2 보완 빌드가 그 경로에서 **초안에만 쓰고, 초안을 지우지 않고, 출처를 잇는지**를 실제 계정 전환으로 본다. 소유 근거가 없어 모든 세션이 보존만이므로, 유효 세션 경로는 DEBUG 소유 주입(아래, 10차 리뷰에서 조건을 더해 승인 · 구현)이 있어야 볼 수 있다. **10차 리뷰 보완 1(엄격한 초안 읽기) · 2(초안 먼저, 저장소는 뒤)를 마치고 시험이 통과한 빌드로만 한다.**

**빌드 · 기기:** 기능 브랜치 작업 트리의 Debug 빌드(②-2 보완, 스키마 V6 그대로 — 1차 기기에 덮어 설치해도 마이그레이션 없음). Carve-ACC-dut(계정 전환 대상) · Carve-ACC-B(B 고정 관측) 모두 같은 빌드로 올린다 — B 기기에서 ②-1 빌드로 쓰면 그 필기는 저장소로 올라간다. 관측은 1차와 같다(2초 관측기 · 서버 조회 · CoreData 로그) — 여기에 **초안 폴더**(`Application Support/Preservation/<저장소>/drafts/<계정 묶음>/<세션>/`)의 파일 수 · revision · 계정 근거를 더한다.

| # | 시나리오 | 주입 | 기대(통과 기준) |
|---|---|---|---|
| 1차-2 | 앱을 켠 채 B → A, 빈 1:1 에 필기 | 없음 | 세션을 새로 열고 다시 읽는다. 필기는 A 묶음의 초안에만 남고 저장소 · A 서버에 새 행이 없다 — 지그재그가 가려지지 않는다(F27 없음). 열린 장이 빈 채로 남는 것(F26)은 ③ 까지 남는 제한으로 기록 |
| 1차-3 | 미전송 편집을 둔 채 앱을 끄고 A → B → A | 없음 | W 는 저장소에 쓰지 않았으므로 미러링이 지울 것이 없다. A 로 돌아오면 W 가 초안(보이기만)으로 1:3 에 다시 보인다. B 에서는 보이지 않는다 |
| 1차-4 | 로그아웃 상태 필기 → B 로그인 | 없음 | 삼각형은 이 기기 전용 묶음의 초안에만 있고 B 서버에 없다(F30 재현 안 됨). B 세션에는 보이지 않는다 |
| 오프라인 | Mac 네트워크를 사람이 끊은 채 전환 → 필기 → 재연결 | 없음 | 계정 조회가 안 되는 동안 확인 대기 · 초안만. 재연결 뒤 import · export 순서와 옛 행의 잔존 여부를 기록한다(F25 추정의 확인) |
| ① | 유효 세션의 저장 직후(전송 전) 전환 → 원래 계정으로 복귀 | 필요 | 저장소에 쓴 필기의 초안이 "들어감" 표식(`storeState = .stored`)을 단 채 남아 있다(F29 결정). 복귀해 그 행이 사라졌으면 초안이 다시 보이되 **보이기만** 한다 — 저장소에 다시 올리지 않는다. 행이 남아 있는 절을 지운 뒤 다시 실행해도 그 초안이 되살아나지 않는다 |
| ② | 저장소와 같은 내용이라 겹치지 않는 초안이 있는 채 전환 | 필요 | 그 초안이 지워지지 않고 남는다. 행이 지워진 계정으로 돌아오면 다시 보인다(보이기만) |
| ③ | 보존만 초안을 남긴 뒤(주입 없이) 주입해 다시 실행 → 그 절에 한 획 | 주입 전 · 후 | 초안이 보이기만 한다. 한 획을 더해도 그 절은 저장소 · 서버에 새 행이 없고, 새 초안이 원 초안의 계정 근거 · 소유 근거(없음)를 든다. 다른 절은 저장소에 쓴다 |
| ④ | 인계 — 획 직후 0.3초 안에 홈 · 사이드바를 연 채 전환(캔버스 없음) · 되돌리기 직후 홈 · 인계 뒤 늦은 보고 | 둘 다 | 마지막 획까지 닫는 세션의 초안에 있다. 캔버스가 없으면 곧바로 닫고, 있으면 응답이 늦어도 닫지 않는다(로그: 인계 재요청). 긴 획 중 전환은 한 기기에서 사람 손으로 만들기 어렵다 — 단위 시험(`ChapterCanvasHandoffPresenceTesting`)으로 대신하고 기기에서는 로그만 본다 |
| ⑤ | 초안 저장 · 이어받기 · 전체 삭제 경계에서 종료(감시기로 초안 파일이 생기는 즉시 종료) · 공간 부족 | 둘 다 | 재실행 뒤 초안이 남고 중복 · 유실이 없다. 전체 삭제 뒤의 늦은 초안은 거절된다. 공간 부족은 기기에서 만들기 어렵다 — 단위 시험으로 대신하고 판정 보류로 적는다 |
| ⑥ | 로그아웃 · 미확인 상태에서 즐겨찾기 · 위젯 · 즐겨찾기 목록 되돌리기 · N-Canvas 저장 · 기록 복원 → 다음 로그인 | 없음 | **결정 1(A) — 사유를 보이고 막는다.** 안내가 뜨고, 다음 로그인 뒤 그 계정 서버에 새 행이 없다(단위 시험: `SyncedWriteGateTesting`) |
| ⑦ | A → B → A 뒤 **파일이 아니라 화면에서** 원본을 찾아 복구 | 둘 다 | 기준이 그대로인 초안은 화면에 보인다. 기준이 달라진 초안 · 같은 내용 초안은 화면에 없다 — 복구 진입점(④)이 없어서다. 어느 경우가 화면에서 닿지 않는지 목록으로 남긴다(④ 설계의 입력) |

**10차 리뷰가 더한 합격 조건:**

| 조건 | 확인 방법 | 기대 |
|---|---|---|
| 실제 초안 파일 손상 | 시뮬레이터에서 한 장의 초안 파일을 직접 깨뜨리고(잘린 JSON · 읽기 권한 없음) 그 장을 연다 | 그 장이 "이 기기에 남은 필기를 불러오지 못했어요 · 다시 시도" 로 막히고 입력을 받지 않는다. 파일을 되돌리면 다시 시도로 열린다. 다른 장은 열린다. 단위 시험: `LocalPreservationReadFailureTesting`(잘린 JSON · 빈 파일 · 다른 모양 · 쓰레기 바이트 · 폴더 · 권한 · 묶음 자리가 파일) · `ChapterCanvasDraftFileTesting`(실제 writer 로 막힘 → 되돌림 → 열림) |
| 초안 저장 지연 · 실패 중 저장소 쓰기 차단 | 단위 시험(기기에서 만들기 어렵다) — `ChapterCanvasDraftOrderTesting` | 초안이 남기 전에는 저장소 저장을 시작하지 않고, 초안 실패를 저장소 저장이 대신하지 않는다 |
| 저장 성공 직후 표식 기록 전 종료 | 감시기로 저장소 행이 생기는 즉시 종료 → 다시 실행(단위 시험: `ChapterCanvasDraftOrderTesting`) | 초안이 "보내는 중" 으로 남는다. 행이 그대로면 겹치지 않고, 그 절을 지운 뒤에도 되살아나지 않는다 |
| 기존 필기 수정의 F29 복구 | 1:3 대신 **기존 행이 있는 절**을 고친 뒤 저장 직후 종료 → A → B → A(단위 시험: `ChapterCanvasDraftOrderTesting`) | 올라간 적 있는 행이면 옛 내용 위에 초안이 이어 보인다. 올라간 적 없는 행이면(그 절이 빔) 보이기만 한다 |
| 두 번 연속 전환 뒤 늦은 편집 보존 | 단위 시험 `ChapterCanvasClosedSessionTesting`(A → B → A 뒤 첫 세션의 늦은 보고) | 첫 세션 ID · 근거의 초안이 되고 저장소 · 새 세션에 섞이지 않는다 |

**기록 · 사후:** 주입한 실행과 주입 없는 실행의 결과를 따로 적는다 — 주입은 소유를 가정한 저장 경로 확인이지 소유 증명이 아니다. **시험 데이터를 지우기 전에** 서버 · 초안 폴더 · 저장소 대조 결과와 필요한 표본(초안 파일 · 저장소 스냅숏 · 서버 조회 결과)을 먼저 보관한다.

**사용자가 할 계정 조작 순서(지금 dut = B):** ① 에이전트가 두 기기에 빌드를 설치하고 관측기 · 서버 표본을 준비한다 → ② 1차-4: B 로그아웃 → 실행 · 1:4 삼각형 → 종료 → B 로그인 → 실행 → ③ 1차-3: B → A → 실행 · 1:3 W(저장 직후 종료) → A → B → 실행 → B → A → 실행 → ④ 1차-2: 1장을 연 채 홈 → A → B → 복귀 · 빈 절에 필기 → ⑤ ④ 인계 조작 → ⑥ 오프라인(Mac 네트워크 끊기 → 전환 → 필기 → 재연결) → ⑦ ⑥ 무계정 쓰기 → ⑧ (주입 빌드 승인 뒤) ① · ② · ③ · ⑦. 각 단계 사이에 에이전트가 서버 조회 · 초안 폴더 · 저장소를 대조한다.

**DEBUG 소유 주입 — 구현(10차 리뷰에서 조건을 더해 승인)**

- **켜는 법:** DEBUG 빌드 · **시뮬레이터** · **시험(dev) 컨테이너(`Carve.dev.sqlite`)** · 실행 인자 `-ACC1InjectStoreOwnership` 이 모두 맞을 때만(`StoreOwnershipInjection.isEnabled`). 이 판정과 앱의 분기는 `#if DEBUG` 안이라 Release 에는 **켜는 경로가 없다**(환경 쪽 분기는 남지만 값이 늘 false 다).
- **주입하는 것:** `LiveDrawingEditEnvironment.current()` 가 **확인된 계정일 때만** 저장소 소유 근거를 그 계정으로 채우고 `ownershipInjected` 를 켠다. 미확인 · 로그인 안 함 · K 읽기 실패는 그대로다 — 보존만 경로는 주입 빌드에서도 같다.
- **드러나게:** 켜지면 시작할 때 경고 로그(`소유 주입(DEBUG · 시뮬레이터 · dev 컨테이너) — 소유 증명이 아니다`)와 필사 화면 위 배지("소유 주입(DEBUG) · 소유 증명 아님")를 띄운다.
- **번지지 않게:** 주입한 세션의 초안 · 닫은 세션의 초안 · 늦은 편집의 초안 · 이어 쓴 초안이 `ownershipInjected` 를 잇는다. 주입 없는 실행은 그 초안의 소유 근거를 없는 것으로 읽는다 — 보이기만 하고, **이후 편집도 그 계정에 귀속하지 않는다**(원 초안의 출처를 이은 초안만 쓰고 저장소에 쓰지 않는다).
- **판정 범위:** 주입은 판정 **뒤의** 경로(저장소 쓰기 · 이어 쓰기 · 전환 때 초안 보존)를 재현할 뿐 저장소 소유를 판정하지 않는다. 결과는 "주입된 소유를 전제로 한 경로" 로 한정해 **주입 · 비주입을 따로** 기록하고, 소유 근거 채택(§3-1)의 근거로 쓰지 않는다.
- **사후:** 서버 · 초안 · 저장소 대조와 표본을 보관한 뒤 두 시뮬레이터의 앱 데이터를 지우고 주입 없는 빌드를 설치한다. dev 컨테이너의 샌드박스 계정 데이터는 폐기 가능한 시험 데이터다. 설치 · 삭제는 사용자 확인 뒤에 한다.

### 3-3. SEP — 분리 판정과 삭제 전파 실험 설계 (2026-09-21, 결정 2 검토 반영)

**현재 적용 범위:** 이 절은 분리·삭제 설계를 검토할 때의 실험 계획으로 보존한다. 2.0.0 출시 필수 시험은 [출시 범위 문서](./release-2.0.0-migration-sync-scope.md)의 네 판정 행이다. F44~F57이 모두 맞더라도 실제 1.3.0 필기의 업데이트 보존·첫 로그인 전송이 증명되는 것은 아니다.

**왜:** 정책 §12-6 C14(1.3.0 무계정 legacy 행 분리)의 판정은 **"미러링 레코드 대응이 없는 행은 지워도 서버로 전파되지 않는다"** 에 기댄다. 이것은 아직 **검증 가설**이다 — F25 · F30 은 계정 전환 · 로그아웃 관측이지 행별 대응의 수명이나 삭제 전파를 증명하지 않는다. **SEP-0 ~ SEP-2 가 통과하기 전에는 파괴적 분리(행 삭제)를 구현하지 않는다.**

**순서를 지킨다** — 앞의 결과에 따라 뒤의 구현 방식이 달라진다: 판독 · 마이그레이션 → 삭제 전파 → 중단 복구 → 보류 차단 → 표시 · 가져오기 → 성능.

**전제:** 계정 조작(로그인 · 로그아웃 · 전환)과 실기기 조작은 사용자 몫이다. 시뮬레이터 두 대(전용 계정 A · B, §2-1)가 필요하고, 운영 데이터에는 하지 않는다. 계정 식별 원문 · 이메일은 기록에 남기지 않는다.

| # | 시험 | 무엇을 본다 | 통과 기준 |
|---|---|---|---|
| SEP-0 | **공개 API 타당성** — 작업용 복제본에서 Core Data 의 `recordID(for:)` · `record(for:)` 를 호환 모델 · `cloudKitContainerOptions = nil` · 읽기 전용으로 부른다 | 유효한 대응을 돌려주는가 · 호출이 저장소 파일을 바꾸지 않는가(전후 해시) · 미러링이 깨어나 동작하지 않는가(이벤트 로그 · 네트워크) | **✅ 2026-09-21 수행 — 공개 API 는 쓸 수 없다**(F34). 미러링을 끈 저장소에서 `recordID(for:)` 는 대응이 있는 행에도 nil 을 준다. → **사설 판독기(`ANSCKRECORDMETADATA`)로 가고, 검증한 OS · 모델 범위 밖은 「알 수 없음」**. 기록은 §5-1 SEP-0 |
| SEP-1 | **V3 실저장소 판독과 전체 마이그레이션** — OLD 빌드(`49f2dc27` · 1.3.0 · V3)로 만든 표본 넷: ① 무계정(한 번도 로그인 안 함) ② 전송 완료 ③ 미전송(연결 없이 쓴 행) ④ 혼합(전송 완료 + 로그아웃 뒤에 쓴 행) | V3 → V4 → V5 → V6 를 지난 뒤에도 **기본 키 ↔ 대응**이 유지되는가 · 세 값 판정이 표본마다 기대대로 나오는가 · 엔티티 3종이 구분되는가(기본 키가 같아도 합치지 않는가) | **⚠️ 부분 수행 — 2026-09-21 수행, 2026-09-22 검토로 관측 범위를 정정.** 통과 기준 셋 가운데 「기본 키 ↔ 대응 유지」 · 「세 값 판정」 은 **`BibleDrawing` 표본에서만** 관측했다(F39). **「엔티티 3종이 구분되는가」 는 미관측** — 어느 표본에도 `BiblePageDrawing` · `FavoriteVerse` 행이 없었다. 표본은 ①(무계정, **하네스가 넣은** V3 행 3 — OLD 가 쓴 행이 아니다) · ④(OLD 의 미러링이 받은 7행 + 하네스 3행) · ②(**사용자가 OLD 화면에서 그린 2행** 포함 12행, OLD 가 곧바로 올렸다). ③(OLD 가 쓴 미전송)은 만들지 못했다. 기록은 §5-1 SEP-1. **2026-09-22 보강:** 판독기(`LegacyRowLinkageReader`)를 실장하고 음성 시험 24종(손상 · 표 없음 · 열 이름 다름 · 엔티티 구분 어긋남 · 일부 행만 모호 · 교차 확인 불일치 · 검증 밖 OS · 모델 · 엔티티)을 실제 파일로 붙였다(§5-1 SEP-1 보강). **2026-09-22 G3 — 엔티티 3종의 대응을 실제 미러링 저장소(V6)에서 관측했다(F51):** `BiblePageDrawing` 은 `ZENTITYID` 2 · `FavoriteVerse` 는 4 로 각자의 `Z_ENT` 와 같았고, 가리키는 서버 레코드의 유형 · 행 ID 가 그 행과 같았다. 옮기는 동안 엔티티 번호가 바뀌어도 대응이 따라온다(F49). → 판독기 v2 의 검증 집합을 legacy 3종으로 넓혔다. 원래 기준: 표본 ①③ 은 「검증된 대응 없음」, ② 는 「대응 있음」, ④ 는 행별로 갈린다 |
| SEP-2 | **삭제 전파 (가장 중요)** — `.none` 으로 연 저장소에서 행을 지우고 다시 연결한다. 두 갈래로 나눈다: **같은 계정 재연결** · **계정 변경**. 각 갈래에서 **대응 있는 행**과 **대응 없는 행**을 따로 지운다 | 서버 레코드 ID 목록(전 · 후) · **persistent history 트랜잭션** · 대응 테이블 · 다른 기기(B)에서 본 결과. `.none` 열기에서 **이력 추적을 끌 수 있는지**도 함께 본다 | **⚠️ 부분 수행 — 2026-09-21 수행, 2026-09-22 검토로 관측 범위를 정정.** 같은 계정 갈래: 대응 있는 행의 삭제는 전파됐고(F37) 대응 없는 행의 연결 전 삭제는 흔적이 없었다(F38) — 단 **하네스가 넣은 합성 행(22바이트 · 삽입 이력이 방금 생김 · 계정 식별이 이미 있던 V6 저장소)** 을 **`NSPersistentContainer` + 이력 추적 옵션**으로 지운 것이고, 서버는 B 기기의 수신 목록으로 봤다(레코드 ID 직접 조회가 아니다). 계정 변경 갈래: B → A **한 방향 · 앱을 끈 채 · 대응 있는 행만**(F41) — 대응 없는 행의 계정 변경 삭제, 앱을 켠 채 · 오프라인 전환, `.none` 열기에서 **이력 추적을 끌 수 있는지**, F25 의 순서 관측은 **미수행**. D1 (가) 는 그 범위 안에서 확정. **관문 항목 ① ~ ④ 는 2026-09-22 같은 계정 재연결 시험(G1 ~ G6)으로 관측했다(F50 ~ F55):** ① 이력이 잘린 무대응 행도 연결하면 올라가고, 연결 전에 지우면 흔적이 없다 ② legacy 3종의 대응(F51) ③ 제품의 SwiftData 삭제 경로에서도 F37 · F38 이 세 엔티티에 걸쳐 같다 ④ 레코드 이름 · 삭제 흔적으로 서버를 직접 확인(앞 세션의 F36 ~ F38 · F41 레코드 포함, F50). 1.3.0 무계정 저장소의 대응 없는 행을 연결 전에 모두 지우고 로그인된 기기에서 첫 연결을 해도 서버가 바뀌지 않았다(F54). **⑤ 계정 변경 갈래도 같은 날 봤다(F56 · F57)** — 앱을 끈 채 바꾸면 대응 없는 행은 어느 계정으로도 가지 않고 로컬에서 사라지며, 지운 대응 있는 행의 삭제도 이전 계정으로 새지 않는다. 게이트 빌드는 끈 채 · 켠 채 전환 모두에서 보류하고 저장소를 건드리지 않는다. **남은 것: 오프라인 전환(시뮬레이터에서 만들 수 없음 — 실기기 항목).** `.none` 열기의 이력 추적 끄기는 필요 없다 — 이력이 켜진 채 지워도 대응 없는 행은 흔적이 없다(F53 · F54). 기록은 §5-1 SEP-2. 원래 기준: 대응 없는 행의 삭제가 전파되면 C14 의 판정 전제가 깨진 것이다 → C14 「SEP-1 · SEP-2 가 실패하면」 의 **격리 + 새 동기화 저장소**로 옮긴다 |
| SEP-3 | **중단 복구** — 보존 확인 전 · 후, 삭제 도중, 색인 갱신 전, 완료 표식 전에 종료. 부분 삭제 · 공간 부족 · 표식 불일치 | 다시 실행해 이어가는가(멱등) · **미완료 분리 작업 복구가 C3 지속 대조보다 먼저** 도는가 · 우리가 지운 행에서 `legacyDelete` 가 생기지 않는가 · `.none` 컨테이너가 해제된 뒤 `.private` 로 여는가 | 어느 경계에서 끊겨도 결과가 같고, 분리 기록 · 출처가 남는다. **⚠️ 2026-09-22 부분 수행 — 보존 단계까지만**(삭제 · 색인 · 완료 표식은 연결하지 않았다): 쓰다 끊긴 `.partial` 폴더 · 손상된 분리본 파일 · `job.json` 없는 폴더 · 500행 넘는 묶음을 단위 시험으로 고정했고, 무계정 기기에서 두 번째 실행이 같은 작업 기록을 다시 쓰는 것을 봤다(F45). 삭제 이후 경계는 미수행 |
| SEP-4 | **보류 차단** — 보류 실행에서 전체 삭제 · 재시도 · 즐겨찾기 · 위젯 보관 · 버전 확정 · 서버 정리를 시도. 조건부 연결 동의 직후 계정을 바꾼다 | 모두 막히는가 · 문구가 맞는가 · 삭제를 예약했다가 연결 뒤 자동 실행하지 않는가 · 동의가 계정 · 저장소 상태 변화로 무효가 되는가 · 소유 근거가 생겨도 보류 차단이 풀리지 않는가 | 하나라도 통과하면 구멍이다. 읽지 못한 파일의 개별 정리는 그대로 되어야 한다. **⚠️ 2026-09-22 부분 수행:** 실제 앱(무계정 기기, 보류 상태)에서 전체 삭제 · 즐겨찾기 추가 · 위젯에 추가가 모두 막히고 문구가 맞았다(F45). 재시도 진입점 · 소유 근거가 있어도 풀리지 않음은 단위 시험. 버전 확정 · 서버 정리 · 조건부 연결 동의(D7)는 기능이 아직 없어 미수행 |
| SEP-5 | **표시 · 가져오기** — 분리본 · 초안 · 원격 후보 · K · 세 엔티티. 같은 절에 같은 내용 · 다른 내용 행 수신, 장 왕복, 재실행, 기존 `clear` · 무효 버전과의 조합. 가져오기 → 원격 전체 삭제 → 재가져오기, 가져오는 중 종료, 가져오는 동안 추가 필기 | 분리본이 조용히 가려지지 않는가(F17 재발) · 현재 계정으로 자동 귀속되지 않는가 · 재시도는 같은 ID, 삭제 뒤 새 동의는 새 ID · 현재 K 인가 · 이어 쓴 초안의 출처가 자동으로 바뀌지 않는가 · `BiblePageDrawing` 이 절로 변환되지 않고 원형으로 남는가 | 표시 · 출처 · ID 규칙이 모든 순서에서 같다. **미수행(2026-09-22)** — 분리본 표시(⑤) · 명시적 가져오기(⑥)가 아직 없다 |
| SEP-6 | **성능** — 마지막에 한다 | 매 실행 전체 검사의 시작 시간 · 메모리(F32 와 같은 자리), 빠른 통과를 넣었을 때의 차이 | 측정값을 기록하고, 빠른 통과가 필요한지 그때 정한다. **✅ 2026-09-22 수행(시뮬레이터)** — 결함 둘을 찾아 고쳤다(판정이 행 수의 제곱 · 분리본을 행마다 장치까지 내려 씀). 고친 뒤 31,102행 모두 대응 1.0초 · 5,000행 모두 없음 1.2초(F47). 실기기 측정은 남았다 |

**회귀로 함께 본다:** P0-3 늦은 import 반영 · ②-2 초안 보호 · 결정 1 의 쓰기 차단 · C11 전체 삭제가 C14 를 붙인 뒤에도 그대로인가.

**관문 미확인 항목의 실험 절차 (2026-09-22 준비, 이 맥 기준 — 계정 조작은 사용자 몫).** 도구 · 표본 · 로그는 저장소 밖 `tools/cloudkit-observe/work/sep/`(`scripts/` · `samples/` · `logs/` · `apps/` · `dd/`)에 있다 — `sep-capture.sh` 표본 뜨기 · `read-store.sh` 신호 읽기 · `sep-run.sh` 하네스 한 번 · `sep-putback.sh` 되돌려 놓기 · `sep-wait.sh` 연결 뒤 이벤트가 조용해질 때까지 · `probe-compare.py` 서버 조회와 저장소를 레코드 이름 · 행 ID 로 맞춤, 그리고 **`sep-gate-rounds.sh`(아래 G1 ~ G4 · 게이트 실기기 경로를 한 번에 — 첫 단계 `preflight` 가 자격 증명을 보고 무효면 아무것도 바꾸지 않고 멈춘다)**. 하네스 지시서는 `insert`(`entity` · `id`) · `truncateHistory` · `deleteSwiftData`(`entity`) · `steps`. 서버 확인은 `tools/cloudkit-observe/probe.sh` 로 레코드 이름과 **삭제 흔적(tombstone)** 을 직접 본다(앱을 재실행한다).

| # | 관문 항목 | 절차 | 판정 |
|---|---|---|---|
| G1 | ① 삽입 이력이 잘린 무대응 행 | dut(로그인 · CURRENT · 조용한 상태) 표본 뜨기 → `insert 2` → **`truncateHistory`** → 되돌려 놓고 앱 실행(setup 1 ~ 3분 기다림) → `read-store.sh` 로 대응 · 이벤트 → `probe.sh` 로 서버 레코드 이름 | 이력 없이도 올라가면 F36 의 확장(게이트가 막아야 할 대상). 올라가지 않으면 그 행은 연결 뒤에도 로컬에만 남는다 — 어느 쪽이든 **지워도 서버에 흔적이 없어야** F38 이 확장된다: 같은 표본에서 한 행을 `deleteSwiftData` 로 지운 뒤 연결해 서버 · 대응 · 이벤트를 본다 **✅ 2026-09-22(F52 · F54)** |
| G2 | ③ 제품의 SwiftData 삭제 경로 | G1 표본(대응 없는 행 2)에서 하나를 **`deleteSwiftData`** 로 지우고, 대응 **있는** 행 하나도 `deleteSwiftData` 로 지운다(F37 재현) → 되돌려 놓고 연결 → 서버 레코드 이름으로 확인 | 대응 없는 행: 흔적 없음. 대응 있는 행: 서버에서 사라짐. `ACHANGE` 의 삭제 변경(type 2)이 `NSPersistentContainer` 경로와 같은 모양인지 `read-store.sh` 로 견준다 **✅ 2026-09-22(F53)** |
| G3 | ② legacy 3종의 대응 | dut 표본에 `insert 1 entity=FavoriteVerse` · `insert 1 entity=BiblePageDrawing` → 되돌려 놓고 연결 → `read-store.sh` 의 「대응(엔티티 ID 별)」 | `ZENTITYID` 가 각각 그 저장소의 `Z_ENT`(V6: `BiblePageDrawing` 2 · `FavoriteVerse` 4)로 생기면 F44 로 적고 `LegacyRowLinkageReader.validatedEntities` 에 넣는다. 다르면 판독기의 엔티티 대응 가정을 다시 세운다 **✅ 2026-09-22(F51)** |
| G4 | ④ 서버 직접 확인 | G1 ~ G3 의 각 단계에서 `probe.sh` 출력의 레코드 이름을 `read-store.sh` 의 `ZCKRECORDNAME`(길이 · 유무만 찍힘 — 필요하면 사본에서 이름을 직접 읽는다)과 맞춘다 | B 기기 수신 목록 대신 **레코드 ID 기준**의 있음 · 없음 **✅ 2026-09-22(F50)** |
| G5 | ⑤ 계정 변경 갈래의 나머지 | G1 표본(대응 없는 행 포함)에서 dut 계정을 바꿔 연결(앱을 끈 채 → 켠 채 → 오프라인 순) | 대응 없는 행이 이전 · 새 계정 어느 서버에도 가지 않는지, 로컬이 비워지는 순서(F25 의 추정) **✅ 2026-09-22 — 앱을 끈 채 · 켠 채 전환(F56 · F57). 오프라인 전환은 시뮬레이터에서 만들 수 없다(ACC-1 2차)** |

**진행(2026-09-22):** 재부팅 뒤 무효였던 자격 증명(F48)을 사용자가 dut · B 에서 다시 넣었고, `sep-wait-credentials.sh` 가 유효해진 것을 본 뒤 `sep-gate-rounds.sh` 가 preflight → r0 → r1 → r2 → r3 → b-check → gate-hold → gate-connect 를 돌았다(11:35 ~ 11:46). 이어서 보강 g1b · g6(11:47 ~ 11:51). 기록은 §5-1 「C14 관문 시험 G1 ~ G6」. G5 는 사용자가 dut 계정을 바꾼 뒤(앱은 끈 채) g5a1 · g5a2 · g5b 로 돌았다(13:00 ~ 13:05, g5b 는 앱을 켠 채 사용자가 다시 바꿈).

## 4. 결과에 따른 설계 선택

| 관측 | 결정 |
|---|---|
| A에서 크래시 또는 잘못된 수정 재현 | 같은 가변 행을 공유하는 방식의 위험 근거. 구버전 차단 성공으로 해석하지 않음 |
| A에서 문제 미재현 | 해당 조건의 관측만 기록. 동시 수정과 중간 상태까지 안전하다고 일반화하지 않음 |
| B 전체 통과 | 같은 컨테이너 내 별도 버전 모델을 채택하고 **2.0.0 에서 C** 를 구현·검증한다. **D 는 2.1** 에서 진행 |
| B에서 OLD가 새 엔티티 때문에 크래시·동기화 중단 | 같은 컨테이너 전략을 보류. 원인 규명 후 별도 저장소·CloudKit 컨테이너로 분리하는 대안을 시험 |
| B에서 구버전 삭제가 NEW 원본에 영향 | 구버전의 삭제 범위 밖으로 분리하는 대안 필요. 자동 원본 복구만으로 무조건 통과시키지 않음 |
| C에서 저장 완료로 보고한 데이터 유실 | 저장 구조 수정 전 출시 불가 |
| D에서 기존 필사 교체·중복·암호화 무결성 실패 | 불러오기 출시 불가. 수정·재검증 또는 명시적 범위 조정 |
| 기기·계정·서명 부족 또는 시간 내 미수신 | 판정 보류. 통과나 데이터 충돌 실패로 임의 분류하지 않음 |

### 4-1. 관측 성공과 안전성 통과를 구분한다

"재현했다" 와 "안전하다" 는 다르다. 아래를 같은 칸에 넣지 않는다.

| 관측 | 올바른 판정 |
|---|---|
| DOWN-L2 에서 조용한 초기화를 재현했다 | **재현 성공 · 데이터 보존 실패.** 절차가 동작한 것이지 제품이 안전한 것이 아니다 |
| 실기기에 271행이 있고 세 장이 정상으로 보인다 | **현재 상태 확인.** 업데이트 전후 무유실의 증명이 아니다 |
| CloudKit 동기화 이벤트가 성공으로 끝났다 | **전송 단계의 근거일 뿐.** 필기 내용·좌표 보존은 따로 확인한다 |
| 양쪽 최종 행 수가 같다 | **부족하다.** 레코드 ID·내용·부모 관계까지 비교해야 한다 |
| 정해진 시간 안에 동기화되지 않았다 | 원인(네트워크·계정·환경·지연)을 구분하지 못하면 **판정 보류** |
| 구버전이 크래시했다 / 동기화가 멈췄다 | 쓰기 차단 성공이 **아니다.** §1 의 판정 원칙 그대로다 |

별도 컨테이너 대안은 자동 채택하지 않는다. 기존 데이터 수신 경로, 두 저장소 운영, 늦게 도착한 legacy 변경, 권한·운영 스키마, 사용자 안내를 설계해 사용자와 확정한다. 1.3.0에 없는 강제 업데이트 기능을 새 앱에 추가하는 것으로 이 시험을 대체하지 않는다.

## 5. 기록 양식

각 케이스는 다음 형식으로 기록한다. 개인 필사·계정 ID·암호는 첨부하지 않는다.

```text
케이스 ID / 수행일:
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff:
기기 A·B OS / 빌드 도구 / 환경 별칭:
초기 표본·행/버전 수 / 원본 해시:
오프라인·재연결 순서 / 실제 조작:
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
전후 원본·메타데이터·계보 비교 / 화면 확인:
크래시·오류 / 로그·스크린샷 경로:
관찰 시간 / 종료 코드 / 미수행 단계:
판정: 통과 / 실패 / 판정 보류 / 미수행
제한과 다음 조치:
```

## 5-1. 수행 기록 (2026-09-16 · 17)

### PRE-0 — OLD 빌드 재현 (§2-1 선행)

```text
케이스 ID / 수행일: PRE-0 / 2026-09-16
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: OLD 49f2dc27 (1.3.0 · 스키마 V3) / 변경 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: — / Xcode 26.3 (17C529) · tuist 4.39.0(.mise.toml 고정) / —
초기 표본·행/버전 수 / 원본 해시: —
오프라인·재연결 순서 / 실제 조작: worktree 로 49f2dc27 checkout → tuist install → generate → xcodebuild build -scheme CarveApp
로컬 저장 성공 / export·import 결과 / 실제 수신 확인: —
전후 원본·메타데이터·계보 비교 / 화면 확인: —
크래시·오류 / 로그·스크린샷 경로: 경고 다수(deprecation · non-Sendable 캡처) — 전부 그 시점부터 있던 선재 경고. 오류 0
관찰 시간 / 종료 코드 / 미수행 단계: — / BUILD SUCCEEDED / —
판정: 통과
제한과 다음 조치: 빌드만 확인했다. 현재 SDK 로 재빌드한 것이므로 실제 출시 바이너리와 동일하지 않다(§2-1 의 제한 그대로).
```

### MIG-L0 — 로컬 마이그레이션 왕복 (단계 L)

```text
케이스 ID / 수행일: MIG-L0 / 2026-09-16
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: OLD 49f2dc27 / CURRENT 1c84a63a(develop)
  테스트 변경: OLD 의 drawingPolicy `.pencilOnly` → `.anyInput` **2줄**
  (CanvasView.swift:29 · CombinedCanvasView.swift:478). 입력 수단만 연 것이고 저장 경로는 무변경.
기기 A·B OS / 빌드 도구 / 환경 별칭: 시뮬레이터 Carve-Migration-Test · iPad mini (A17 Pro) · iOS 26.2
  / Xcode 26.3 · tuist 4.39.0(OLD) · 4.208.0(CURRENT) / iCloud 미로그인
초기 표본·행/버전 수 / 원본 해시: 창세기 1장 절 1·절 3 각 1행(사용자가 직접 필사)
  절1 ZLINEDATA 4237 B · sha256(hex) 0d125f6a340c68cd
  절3 ZLINEDATA 4058 B · sha256(hex) 664061ec06a3aa49
오프라인·재연결 순서 / 실제 조작: OLD 설치 → 필사 → 앱 종료 → **삭제하지 않고** CURRENT 덮어 설치 → 실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인: 저장 확인(V3 store 조회). CloudKit 미사용
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · ZLINEDATA sha256 **전후 완전 일치**(두 행 모두). 재인코딩 없음
  · ZDRAWINGVERSION 1 유지 · ZID 유지 · ZROWUUID 미발급(NULL) · ZLAYOUTMETADATADATA NULL
  · 스키마 전이 확인: ZROWUUID·ZLAYOUTMETADATADATA 컬럼 추가, ZFAVORITEVERSE 테이블 생성 (V3 → V4 → V5)
  · 화면: 두 필기가 각자 자기 절의 필사 영역에 표시됨 (docs/migration-v3-to-v5-2026-09-16.png)
크래시·오류 / 로그·스크린샷 경로: 크래시 없음 / docs/migration-v3-to-v5-2026-09-16.png
관찰 시간 / 종료 코드 / 미수행 단계: 즉시 / — / CloudKit 관련 전부
판정: 통과
제한과 다음 조치: 표본이 두 절뿐이고 실사용 규모가 아니다. 시뮬레이터라 실기기 렌더링·회전은 보지 않았다.
  다음은 MIG-L1(실기기, 기존 데이터)과 단계 A.
```

### MIG-L1 — 실기기 실사용 store 관측 (단계 L)

```text
케이스 ID / 수행일: MIG-L1 / 2026-09-16
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: 해당 없음(기기에 이미 설치된 2.0.0 을 관측만)
기기 A·B OS / 빌드 도구 / 환경 별칭: iPad mini (A17 Pro) 실기기 / devicectl 로 앱 컨테이너 읽기 / prod 컨테이너
초기 표본·행/버전 수 / 원본 해시: 실사용 데이터 271행 · 40장 · 87절. 잉크 합계 약 3.9 MB
  (개인 필사 기록이므로 어느 본문인지는 적지 않는다 — LegacyDrawingFixture 와 같은 방침)
오프라인·재연결 순서 / 실제 조작: **없음.** 기기를 조작하지 않고 store 파일만 복사해 읽었다
  (Library/Application Support/Carve.sqlite + -wal + -shm)
로컬 저장 성공 / export·import 결과 / 실제 수신 확인: 해당 없음
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 스키마 V5 확인 — ZROWUUID · ZLAYOUTMETADATADATA 컬럼과 ZFAVORITEVERSE 테이블 존재
  · 좌표 형식 분포: drawingVersion 1 = **256행**, 3 = **15행**
  · rowUUID 보유 15행 · layoutMetadataData 보유 15행 — **둘 다 v3 행과 정확히 1:1**, legacy 256행은 0
  · isPresent: v1 중 true 2 / false 254, v3 중 true 12 / false 3
  · 절당 행 수: 1행 55절 · 2행 3절 · 3행 1절 · 6행 2절 · **7행 24절** · 11행 1절 · 16행 1절
  · 잉크 크기: 최소 38 B · 평균 15.3 KB · 최대 111 KB · 빈 행 2
  · ZBIBLEPAGEDRAWING **0행** (F2 재확인), ZFAVORITEVERSE 1행
  · **화면 확인(사용자 육안, 2026-09-16)** — TestFlight 의 Release 빌드를 덮어 설치한 뒤
    legacy 가 가장 많은 장(56행)·히스토리가 깊은 절을 가진 장(29행, 한 절 16행)·
    v3 로 승격된 장(15행) 세 곳을 열어 **필사가 정상으로 보이는 것을 확인**했다.
    픽셀 대조가 아니라 육안 확인이며, 저장된 좌표와 화면 좌표를 수치로 대조하지는 않았다.
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: — / — / CloudKit 전부
판정: 통과(현재 상태 확인) — **업데이트 전후 무유실의 증명은 아니다** (§4-1). 업데이트 직전 상태를
  따로 떠 두지 않았으므로 "무엇이 있었고 무엇이 남았는지" 를 대조할 기준이 없다
제한과 다음 조치: store 메타데이터만 집계했고 잉크 내용은 열지 않았다. 화면은 육안 확인이므로
  "좌표가 정확하다" 가 아니라 "사용자가 보기에 어긋난 곳이 없다" 까지가 근거다. 표본은 세 장이고
  나머지 37장은 보지 않았다. CloudKit 왕복(단계 A)은 그대로 남아 있다.
```

**이 관측이 답한 것.** D8 시점 225행이던 실사용 데이터가 271행으로 늘어난 채 V5 에 올라가 있고, 그중 **256행이 여전히 legacy(v1)** 다. 마이그레이션이 좌표 형식을 건드리지 않는다는 §10-2 정책과, rowUUID 를 소급 발급하지 않는다는 §8-7 비파괴 원칙이 **실사용 데이터에서 그대로 지켜졌다.** v3 로 올라간 15행은 2.0.0 에서 실제로 편집한 절이며 rowUUID·metadata 를 빠짐없이 갖췄다.

### DOWN-L2 — V5 store 에 OLD 덮어 설치 (역방향)

```text
케이스 ID / 수행일: DOWN-L2 / 2026-09-16
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: OLD 49f2dc27 (MIG-L0 과 같은 테스트 빌드, drawingPolicy 2줄)
기기 A·B OS / 빌드 도구 / 환경 별칭: 시뮬레이터 Carve-Migration-Test · iPad mini (A17 Pro) · iOS 26.2 / iCloud 미로그인
초기 표본·행/버전 수 / 원본 해시: MIG-L0 이 남긴 V5 store — BibleDrawing 2행 · 잉크 8,295 B
오프라인·재연결 순서 / 실제 조작: 2.0.0 종료 → **앱을 지우지 않고** OLD 덮어 설치 → 실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인: 해당 없음(CloudKit 미연결)
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · **앱이 정상 실행됐다.** 크래시 없음. 창세기 1장이 평소처럼 열렸다
  · **필사는 전부 사라진 것처럼 보인다** — 화면에 획이 하나도 없다
  · store 를 열어 보니 `ZBIBLEDRAWING` 테이블이 **없고** `ZDRAWINGVO` 만 있다 = **V1 스키마**
  · 즉 같은 파일이 V1 스키마로 갈아치워졌고 기존 필사 2행은 store 에서 사라졌다
크래시·오류 / 로그·스크린샷 경로:
  CoreData NSCocoaErrorDomain **134504** "Cannot use staged migration with an unknown model version."
  → OLD 의 `SwiftDataContextProvider+Dependency.liveValue` 가 이 오류를 `.loadIssueModelContainer` 로 잡아
    `Schema([DrawingVO.self])` + `MigrationPlanV1Only` 로 **같은 URL 에 컨테이너를 다시 만든다.**
    폴백이 성공하므로 `fatalError` 에 도달하지 않는다.
관찰 시간 / 종료 코드 / 미수행 단계: 즉시 / — / CloudKit 연결 상태에서의 거동(계정 없음)
판정: **재현 성공 · 데이터 보존 실패** (§4-1). 절차가 의도대로 동작했다는 뜻이지 제품이 안전하다는 뜻이 아니다
제한과 다음 조치: iCloud 미로그인 상태였다. **V1 스키마가 된 store 가 CloudKit 에 붙으면 무슨 일이
  일어나는지는 확인하지 못했다** — 서버에는 `CD_BibleDrawing` 이 있는데 클라이언트는 `CD_DrawingVO` 를
  기대하는 상태다. 단계 A 에서 반드시 관측한다.
```

### DEV-ICLOUD-1 — 실제 계정 · dev 컨테이너 한 대 관측 (계획 케이스 아님)

```text
케이스 ID / 수행일: DEV-ICLOUD-1 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: CURRENT 4854e609(develop, Debug)
  / 기기 전용 임시 UI 테스트 1개로 조작 · 캡처(확인 뒤 삭제, 커밋 안 함)
기기 A·B OS / 빌드 도구 / 환경 별칭: iPad mini (A17 Pro) · iPadOS 27.2 · USB / Xcode 26.3 · tuist 4.208.0
  / 실사용 iCloud 계정 · iCloud.Carve.SwiftData.iCloud.dev · Carve.dev.sqlite (§2-1 사용자 결정: dev 는 지워도 된다)
초기 표본·행/버전 수 / 원본 해시: dev 저장소의 기존 개발 데이터 — 삭제 전 행 수는 기록하지 않았다.
  위젯 App Group 파일 2개는 빌드 구성으로 갈리지 않아 시험 전 백업 → 시험 뒤 복원, sha1 일치
오프라인·재연결 순서 / 실제 조작: 실행 → 설정 → iCloud → 「모든 필사 데이터 삭제」 → 「모두 지우기」 → 확인 → 완료
  → 앱 종료 → 재실행. 첫 시도는 기기의 UI 자동화가 꺼져 러너가 시작하지 못했다(사용자가 켬).
  손가락 필기는 실행 인자로 켜지지 않아 넣지 못했다
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · 시작 화면 4.3s "데이터 동기화 중..." → 4.7s "데이터 동기화 완료" — import 성공 이벤트로 결론. 재실행 때도 2.5s 에 완료
  · 설정 → iCloud "iCloud 계정에 연결돼 있어요" · "마지막으로 받음 · 10초 전" · "마지막으로 올림 · 10초 전"
  · 삭제 직후 "동기화하는 중이에요" → 약 10초 뒤 "마지막으로 올림 · 지금" — 삭제가 export 됐다
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 결과 팝업 "모든 필사 데이터를 지웠어요." — 위젯 비우기까지 끝났다
  · 재실행(실제 import) 뒤 기기의 dev 저장소를 복사해 셈: BibleDrawing 0 · FavoriteVerse 0 · BiblePageDrawing 0.
    되살아난 행이 없다. 사본은 확인 뒤 지웠다
  · 운영 Carve.sqlite 수정 시각 9/16 그대로 — 열지 않았다
크래시·오류 / 로그·스크린샷 경로: 없음. 캡처는 xcresult 첨부로 판독한 뒤 지웠다(저장소 밖)
관찰 시간 / 종료 코드 / 미수행 단계: 약 2.5분 / TEST SUCCEEDED / 필기 입력 · 저장 중 삭제 경쟁 · 삭제 실패 · 다른 기기 반영
판정: 통과 — 관측한 범위(한 기기 · 성공 경로)에 한한다
제한과 다음 조치: 경쟁 · 실패 경로와 두 번째 클라이언트는 보지 못했다. 앱 Log.debug 와 CoreData CloudKit 디버그 로그는
  devicectl --console 로 나오지 않아(OS_ACTIVITY_DT_MODE 를 줘도) 이벤트 종류는 화면 문구로만 판정했다.
  설정 사이드바의 iCloud 행 값이 계정 상태와 무관하게 "켬" 으로 고정된 것을 발견했다(미수정).
```

### 관측 도구 — 서버 레코드 조회 · 저장소 비교 (2026-09-17)

샌드박스 계정의 private DB 는 CloudKit 콘솔에서 볼 수 없어(F9) 아래 방법으로 서버와 저장소를 읽었다. **앱 코드 · 프로젝트 파일은 바꾸지 않았다.**

| 도구 | 방법 | 쓰기 |
|---|---|---|
| 서버 레코드 조회 | 읽기 전용 CloudKit 조회 dylib 를 `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` 로 시뮬레이터 앱에 주입한다. 앱의 엔타이틀먼트로 dev 컨테이너 private DB 의 `com.apple.coredata.cloudkit.zone` 전체를 `CKFetchRecordZoneChangesOperation` 으로 읽어, 레코드마다 키 목록 · 값(바이트는 크기와 sha256 앞 16자리) · 변경 태그를 출력한다. 앱은 평소처럼 함께 실행된다 | 없음 |
| 저장소 비교 | 앱 데이터 컨테이너의 `Carve.dev.sqlite`(+wal · shm · 외부 데이터)를 복사해 **복사본만** 연다. `ANSCKRECORDMETADATA` 로 행과 CKRecordName 을 이어 두 스냅숏을 레코드 이름 기준으로 대조한다. 외부 저장 속성은 0x01 접두를 떼고 해시하며, 그 값이 서버 `CD_lineData` 해시와 일치했다 | 없음 |
| 잉크 해석 | `PKDrawing(data:)` 로 획마다 점 수 · 첫 점 · 경계 · 획 변환을 출력한다 | 없음 |
| 실행 로그 | `simctl launch --console-pty` + `-com.apple.CoreData.CloudKitDebug 1`. 이벤트는 `xcrun simctl spawn <UDID> log show --predicate 'subsystem == "com.apple.coredata"'` 로 읽는 편이 확실했다 | — |

도구는 **저장소에 넣지 않고** 개인 폴더에 둔다(2026-09-17 사용자 결정). 위 표의 방법으로 다시 만들 수 있다.

⚠️ 처음 만든 서버 조회는 결과를 받은 뒤 콘솔 연결을 끊으면서 **앱도 종료시켰다**(CK-A2 ~ CK-A4b 1회차의 조회). 판정에 쓴 데이터에는 영향이 없다. 그 뒤로는 결과를 앱 임시 파일로 받게 고쳐 앱이 계속 실행된다.

### CK-A0 — 기본 전송 (단계 A)

```text
케이스 ID / 수행일: CK-A0 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: OLD 49f2dc27 Debug (MIG-L0 과 같은 drawingPolicy 2줄) / — / —
기기 A·B OS / 빌드 도구 / 환경 별칭: 시뮬레이터 A = Carve-CK-A-old · B = Carve-CK-B-upgrade, 둘 다 iPad mini (A17 Pro) · iOS 26.2
  / Xcode 26.3 (17C529) / 샌드박스 계정 · iCloud.Carve.SwiftData.iCloud.dev(Development 추정) · Carve.dev.sqlite
초기 표본·행/버전 수 / 원본 해시: 첫 실행 가져오기 뒤 필사 0행
  L1 — A 에서 창세기 1장 1절 A1(938 B · e9559063…) · 3절 A3(1352 B · 7cc98d9a…), B 에서 2절 B2(1631 B · 0e886e9e…)
  모두 v1 · isPresent 0 · rowUUID 필드 없음(V3). 필기는 사용자가 마우스로 했다
오프라인·재연결 순서 / 실제 조작: A 실행 → A 필기 → B 첫 실행(수신) → B 필기 → 켜 둔 A 를 2분 관찰 → A 재실행(수신)
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · A: 계정 · zone · 데이터베이스 구독 설정 성공, 두 레코드 업로드 완료(13:26:13~19), 업로드 대기 0
  · B: 첫 실행 3초 안에 가져오기 완료, 필사 2행. B 는 아무것도 다시 올리지 않았다
  · B2: B 가 2절 레코드만 올렸다. **켜 둔 A 는 2분간 가져오지 않았고**(F8) 재실행 3초 안에 가져왔다
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 레코드 이름 기준으로 A · B 저장소의 모든 필드가 같다(잉크 크기 · 해시 · drawingVersion · isPresent · 날짜)
  · 서버: CD_BibleDrawing 3건, 키 11개(CD_rowUUID · CD_layoutMetadataData 없음), CD_lineData 해시가 양쪽 저장소와 같다
  · 화면: 두 시뮬레이터에서 A1 · B2 · A3 가 같은 자리에 보인다
크래시·오류 / 로그·스크린샷 경로: 없음 / 세션 임시 폴더(보관 안 함)
관찰 시간 / 종료 코드 / 미수행 단계: 약 7분 / — / 오프라인 만들기
판정: 통과 — 양방향 전송. 시뮬레이터를 단계 A 에 쓴다
제한과 다음 조치: 1회 관측 · 같은 모델 · 같은 계정. OLD 는 현재 SDK 로 재빌드한 것이다(§2-1)
```

### CK-A1 — B 만 CURRENT 로 업데이트 (단계 A)

```text
케이스 ID / 수행일: CK-A1 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD, B = OLD → CURRENT 2c124cb3(develop) Debug / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음
초기 표본·행/버전 수 / 원본 해시: CK-A0 끝 상태 — 3행(1 · 2 · 3절), 전부 v1
오프라인·재연결 순서 / 실제 조작: B 의 1.3.0 종료 → 스냅숏 → **앱을 지우지 않고** CURRENT 덮어 설치 → 실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · 가져오기 성공, **업로드 0건**. 내보내기 요청 중복 취소(134417)만 보였다 — 오류가 아니다
  · 서버: 세 레코드의 변경 태그 · 키 · 해시가 그대로다
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 저장소 V3 → V5 (ZROWUUID · ZLAYOUTMETADATADATA 열, ZFAVORITEVERSE 테이블)
  · 세 행의 잉크 해시 · drawingVersion 1 · isPresent · 날짜 · CKRecordName 매핑이 그대로다. rowUUID · layoutMetadata 는 NULL(소급 발급 없음)
  · 화면: 2.0.0 레이아웃에서 A1 · B2 · A3 가 각 절 필사 칸에 보인다(육안). 첫 실행에 사용법 안내(1/4)와 광고 검증기 팝업이 떴다
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 약 2분 / — / —
판정: 통과
제한과 다음 조치: 표본 3행. CK-A2 준비로 B 의 손가락 필기(allowFingerDrawing)를 컨테이너 plist 로 켰다 — 필사 데이터와 무관
```

### CK-A2 — CURRENT 가 편집한 행을 OLD 가 받음 (단계 A)

```text
케이스 ID / 수행일: CK-A2 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD, B = CURRENT 2c124cb3 / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음
초기 표본·행/버전 수 / 원본 해시: CK-A1 끝 상태(3행 v1)
오프라인·재연결 순서 / 실제 조작: B(CURRENT)에서 사용자가 1절 A1 옆에 N1(1.3.0 행 편집) · 4절에 N4(새 행)
  → B 업로드 확인 → 서버 조회 → A(OLD) 재실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · B 업로드: 1절 · 4절 두 레코드만
  · 서버 1절: **같은 레코드**가 v3 로 바뀌었다. CD_layoutMetadataData 208 B 추가, **CD_rowUUID 없음**, 잉크 2050 B
  · 서버 4절: 새 레코드. v3 · isPresent 1 · CD_rowUUID · CD_layoutMetadataData 212 B, 잉크 1576 B
  · A: 크래시 없이 가져오기 성공, 다시 올린 레코드 없음
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · A 저장소(V3): 두 행의 잉크 해시 · drawingVersion 3 · isPresent · 날짜가 서버와 같다. 모르는 두 필드는 열이 없어 저장되지 않았다
  · 잉크 해석: 2.0.0 은 A1 획의 점을 그대로 두고 획 변환 ty −38 을 붙여 v3 로 옮겼다(F10)
  · **A 화면: 1절 필기가 약 38pt(한 줄쯤) 위로 올라가 위쪽이 잘렸다. 4절 N4 는 아래쪽이 잘렸다.** v1 인 2 · 3절은 제자리
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 약 6분 / — / —
판정: 크래시 · 동기화 오류 없음, 데이터 보존. **좌표 오표시 재현(R28 보기 증상)** — §4-1 에 따라 안전 통과가 아니다
제한과 다음 조치: 세로 · 같은 모델의 한 레이아웃. 38pt 는 이 레이아웃의 값이다
```

### CK-A3 — OLD 가 편집한 v3 행을 CURRENT 가 받음 · U4 (단계 A)

```text
케이스 ID / 수행일: CK-A3 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD, B = CURRENT 2c124cb3 / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음
초기 표본·행/버전 수 / 원본 해시: CK-A2 끝 상태 — 1절 v3(layout 있음 · rowUUID 없음) · 4절 v3(둘 다 있음)
오프라인·재연결 순서 / 실제 조작: A(OLD)에서 사용자가 1절 N1 을 지우개로 지우고 4절 N4 옆에 X4 추가
  → A 업로드 확인 → **B 가 받기 전에** 서버 조회 → B(CURRENT) 재실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · A 업로드: 1절 · 4절 두 레코드만(변경 태그 b~f). 조회를 위해 A 를 다시 띄운 뒤에는 올린 것이 없다
  · 서버 1절: 잉크 1633 B, **CD_layoutMetadataData 208 B 해시 그대로**, drawingVersion 3
  · 서버 4절: 잉크 2934 B, **CD_rowUUID 그대로 · CD_layoutMetadataData 212 B 해시 그대로**, drawingVersion 3
  · B: 가져오기 성공, 업로드 0건
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · B 저장소: 두 행은 잉크만 바뀌었고 rowUUID · layoutMetadata 는 로컬에도 그대로다
  · 잉크 해석: **1.3.0 은 남은 획을 건드리지 않았다** — A1 · N4 획의 점 · 획 변환이 편집 전과 같다.
    지운 N1 획만 빠졌고, 새 X4 획은 **변환 (0, 0) 의 1.3.0 절 로컬 좌표**로 더해졌다
  · B 화면: A1 은 제자리. X4 는 N4 옆에 나란히 보인다 — 1.3.0 에서 위로 올라가 보이던 N4 에 맞춰 썼기 때문이다
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 약 5분 / — / 본문 줄에 맞춰 쓴 새 획의 2.0.0 표시
판정: **U4 — 관측 범위에서 보존.** R28 — 라벨 3 유지를 확인했고, 1.3.0 이 더한 획은 2.0.0 에서 1.3.0 화면 기준보다
  약 38pt 아래에 놓인다(수치로 추정, 본문 줄 기준 비교는 미시험)
제한과 다음 조치: 쓰기 경로는 지우개 · 획 추가 두 가지. 행 삭제 · 동시 편집(CK-A4) · Production 은 보지 않았다
```

### CK-A4b — 서로 모르는 같은 절 편집, 네트워크 유지 (단계 A)

```text
케이스 ID / 수행일: CK-A4b / 2026-09-17 (1회차 A 먼저 · 2회차 B 먼저)
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD, B = CURRENT 2c124cb3 / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음. 네트워크는 끊지 않았다
초기 표본·행/버전 수 / 원본 해시: 두 앱을 다시 띄워 같은 상태를 확인하고 켜 둔 채 시작
  1회차 부모 = 양쪽 3절 v1 A3(1352 B · 7cc98d9a…), 2회차 부모 = 양쪽 2절 v1 B2(1631 B · 0e886e9e…)
오프라인·재연결 순서 / 실제 조작: 사용자가 먼저 작성자 쪽에 쓰고 약 15초 뒤 다른 쪽에 씀. 두 번째 작성자는 저장까지 재실행하지 않음
  1회차: A 가 3절에 P3 → B 가 3절에 Q3
  2회차: B 가 2절에 Q2 → A 가 2절에 P2
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  1회차 · A 업로드 14:06:40 · 43(태그 g · h) → B 는 그사이 가져오기 0건 → B 업로드 14:07:20 · 26(i · j), 오류 없음
        · 서버(B 에서 조회): 태그 j · v3 · layout 208 B · 잉크 2966 B = **B 의 것**
        · A 재실행: 가져오기 1 · 업로드 0 → A 로컬도 서버와 같아짐(v3 · 2966 B)
  2회차 · B 업로드 14:13:44 · 45(k · l, v3) → A 는 그사이 가져오기 0건 → A 업로드 14:14:02(m), 오류 없음
        · 서버(A 에서 조회): 태그 m · **drawingVersion 1** · layout 212 B(B 가 붙인 것 그대로) · 잉크 2701 B = **A 의 것**
        · B 재실행: 가져오기 1 · 업로드 0 → B 로컬도 v1 · layout 212 B · 2701 B
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 잉크 해석 1회차: 최종 = A3 3획(변환 ty −38) + Q3 3획. **P3 2획은 어디에도 없다**
  · 잉크 해석 2회차: 최종 = B2 3획(변환 0) + P2 2획. **Q2 3획은 어디에도 없다**
  · 두 회차 모두 절당 행은 하나 그대로(중복 없음)
  · 화면: 1회차는 양쪽 A3 · Q3(1.3.0 은 위로 밀려 잘림), 2회차는 양쪽 B2 · P2 가 제자리
크래시·오류 / 로그·스크린샷 경로: 없음. CoreData 로그에 충돌 오류 · 처리 흔적이 없다 / —
관찰 시간 / 종료 코드 / 미수행 단계: 회차당 약 5분 / — / 오프라인 CK-A4 · 2.0.0 끼리
판정: **나중에 올린 쪽이 절 필기 전체를 덮어쓰고 먼저 쓴 필기가 사라진다 — 오류 · 안내 없음(F15).**
  2회차는 라벨이 1 로 돌아가고 낡은 layoutMetadata 가 남았다(F16)
제한과 다음 조치: 1.3.0 ↔ 2.0.0 조합에서 회차당 1회. CK-A4(오프라인)를 대체하지 않는다
```

### CK-A5 — R27: 빈 절에 두 기기가 따로 쓰기 (단계 A)

```text
케이스 ID / 수행일: CK-A5 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD, B = CURRENT 2c124cb3 / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음. 네트워크 유지
초기 표본·행/버전 수 / 원본 해시: 양쪽 5절 행 없음. 두 앱 켜 둔 채 시작
오프라인·재연결 순서 / 실제 조작: 사용자가 A 5절에 P5 → 약 15초 뒤 B 5절에 Q5. B 는 저장까지 재실행하지 않음
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · A: 새 레코드 2DD25847 업로드 14:21:30 · 31 — v1 · isPresent 0 · id …1.5.1789622486 · 잉크 1368 B
  · B: 그사이 가져오기 0건 → 새 레코드 C1B01EC4 업로드 14:21:47 · 48 — v3 · isPresent 1 · rowUUID · layout 216 B
    · id …1.5.1789622504 · 잉크 1989 B
  · 서버: 두 레코드가 모두 있다
  · A 재실행(조회) · B 재실행: 각각 가져오기 1 · 업로드 0 → 양쪽 저장소 모두 5절 2행
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 두 행은 id · 레코드 이름이 서로 다르고, 병합 · 정리 · 삭제는 일어나지 않았다
  · **화면: A · B 모두 5절에 Q5 만 보인다.** A 에서는 방금 쓴 P5 가 사라진 것처럼 보인다(1.3.0 은 Q5 를 위로 밀어 그림)
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 약 5분 / — / 반대 순서(B 먼저) · 이전 필사 보기에서 P5 가 보이는지
판정: **R27 재현 — 절당 행 중복, 1.3.0 필기가 두 기기에서 가려짐(F17).** 데이터 자체는 남아 있다
제한과 다음 조치: 한 순서 1회. Q5 가 isPresent 1 이고 updateDate 도 늦어 어느 대표 규칙으로 골랐는지 가리지 못했다
```

### CK-A4c — 2.0.0 끼리 서로 모르는 같은 절 편집 (단계 A)

```text
케이스 ID / 수행일: CK-A4c / 2026-09-17 (1회차 B 먼저 · 2회차 C 먼저)
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: B · C = CURRENT 2c124cb3 Debug / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: B = Carve-CK-B-upgrade, C = Carve-CK-C-current(새로 만듦) — 둘 다 iPad mini (A17 Pro) · iOS 26.2 · 같은 샌드박스 계정
  C 는 첫 실행에서 필사 6행을 받아 B 와 모든 필드가 같았다. C 도 손가락 필기를 컨테이너 plist 로 켰다. 네트워크 유지
초기 표본·행/버전 수 / 원본 해시: 1회차 부모 = 4절 v3 · rowUUID 있음(N4 X4, 7획) / 2회차 부모 = 3절 v3 · rowUUID 없음(A3 Q3, 6획)
오프라인·재연결 순서 / 실제 조작:
  1회차: B 가 4절에 R4 → C 가 4절에 S4. 사용자가 처음에 C 에 R4 · S4 를 모두 썼다가 되돌리기로 지운 뒤 진행했다
         — C 의 실수 · 되돌리기 업로드(14:38:54~14:39:40)는 B 의 쓰기보다 앞선다
  2회차: C 가 3절에 S3 → B 가 3절에 R3
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  1회차 · B 업로드 14:39:51(태그 z) → C 업로드 14:40:01 · 02(10 · 11). 그사이 양쪽 가져오기 0건, 오류 없음
        · 서버: 태그 11 · 잉크 4171 B = C 의 것. B 재실행: 가져오기 1 · 업로드 0 → B 도 C 의 것
  2회차 · C 업로드 14:45:04 · 05(12 · 13) → B 업로드 14:45:19 · 23(14 · 15). 그사이 양쪽 가져오기 0건, 오류 없음
        · 서버: 태그 15 · 잉크 4430 B = B 의 것. C 재실행: 가져오기 1 · 업로드 0 → C 도 B 의 것
전후 원본·메타데이터·계보 비교 / 화면 확인:
  · 잉크 해석 1회차: 최종 10획 = 부모 7획 + S4 3획. **B 의 R4 4획은 없다.** C 의 실수 획도 남지 않았다
  · 잉크 해석 2회차: 최종 9획 = 부모 6획 + R3 3획. **C 의 S3 2획은 없다**
  · 화면: 두 회차 모두 두 기기에서 사라진 필기가 보이지 않는다
  · 두 기기가 저장한 layoutMetadata 는 바이트 해시가 달랐지만 JSON 키 순서만 다르고 값은 같았다(F18)
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 회차당 약 5분 / — / 오프라인
판정: **1.3.0 이 섞이지 않아도 나중에 올린 쪽이 절 필기 전체를 덮어쓰고 먼저 쓴 필기가 사라진다(F15)**
제한과 다음 조치: 회차당 1회 · 네트워크 유지. 1.3.0 끼리도 같은지(기존 출시본에도 있던 동작인지)는 미시험
```

### FAV-P0 — 모르는 레코드 타입 예비 호환성 (CK-B1 · B7 예비)

```text
케이스 ID / 수행일: FAV-P0 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD 49f2dc27, B = CURRENT 2c124cb3 / 없음
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음. 서버 조회는 이 시험에 쓰지 않은 C 에서 했다
초기 표본·행/버전 수 / 원본 해시: 양쪽 필사 6행, 즐겨찾기 0. 서버에는 CD_BibleDrawing 6건뿐
오프라인·재연결 순서 / 실제 조작: B 에서 1절 즐겨찾기 추가 → A 재실행 → A 에서 2절 편집(F2) · 6절 새 필기(F6) → B 재실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  · B: CD_FavoriteVerse 레코드 1건 업로드(15:16:17). 서버에 필사 6 + 즐겨찾기 1
  · A 재실행: CoreData 로그 "Skipping unknown updated record … recordType=CD_FavoriteVerse" → 가져오기 성공 · 크래시 없음
    · 남은 가져오기/내보내기 작업 0 · 필사 6행 그대로 · A 의 레코드 메타데이터에 즐겨찾기는 없음
  · A 편집: 2절 레코드 갱신(태그 17 · 18) · 6절 새 레코드(19 · 1a) 업로드, 오류 없음
  · 서버: 즐겨찾기 레코드의 태그(16)와 내용 해시가 그대로. 2절 레코드의 CD_layoutMetadataData 도 남았다
  · B 재실행: 가져오기 1 · 업로드 0 → 2절 · 6절이 A 와 같고, 즐겨찾기 1건이 그대로
전후 원본·메타데이터·계보 비교 / 화면 확인: A 화면 정상. 2절 · 6절 잉크 해시 A = 서버 = B
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 약 10분 / — / 1.3.0 전체 삭제 · 건너뛴 레코드를 업데이트 뒤 받는지
판정: **예비 통과 — 1.3.0 은 모르는 레코드 타입을 건너뛰었고, 기존 필사 왕복과 그 레코드의 서버 보존에 영향이 없었다(1회).**
  실제 새 엔티티 검증을 대신하지 않는다
제한과 다음 조치: 즐겨찾기는 관계가 없는 단순 엔티티다. 가져오기가 성공으로 끝나 A 의 변경 토큰이 그 레코드 뒤로
  넘어갔을 것으로 보이므로(추정), 같은 기기를 2.0.0 으로 올렸을 때 건너뛴 레코드를 받는지가 새 엔티티 설계의 필수 확인 항목이다
```

### ENT-P1 — 후보 엔티티의 구버전 호환성 (CK-B1 · B3 · B7 축소판)

```text
케이스 ID / 수행일: ENT-P1 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: A = OLD 49f2dc27 → (3부) 스파이크, B · C = 스파이크
  스파이크 = 2c124cb3 + 스키마 V6(후보 엔티티 VerseDrawingVersion 추가, lightweight) + Debug 전용 시드 훅(-CKSpikeVersionVerses).
  별도 worktree(.claude/worktrees/spike-version-entity, 분리 HEAD)에서 빌드했고 커밋 · 병합하지 않았다. 필드는 정책 §12-5 의 후보
기기 A·B OS / 빌드 도구 / 환경 별칭: CK-A0 과 같음 + C(Carve-CK-C-current). 서버 조회는 C 에서
초기 표본·행/버전 수 / 원본 해시: 필사 7행(1~6절, 5절 2행) · 즐겨찾기 1(FAV-P0). 표본은 모두 폐기 가능한 시험 데이터
오프라인·재연결 순서 / 실제 조작:
  1부 · C → B 순으로 스파이크 덮어 설치(V5 → V6) → B 를 시드 훅으로 실행해 1~6절 현재 필사를 복사한 버전 6건 생성
      → A(1.3.0) 재실행 → 사용자가 A 에서 2절 G2 · 7절 G7 → B 재실행
  2부 · 사용자가 A(1.3.0) 설정 → iCloud → 「모든 필사 데이터 삭제」 → B 재실행
  3부 · A 를 스파이크로 덮어 설치(V3 → V6) → 첫 실행
로컬 저장 성공 / export·import 결과 / 실제 수신 확인:
  1부 · C · B 마이그레이션 정상(필사 7행 · 즐겨찾기 그대로, 새 테이블 생성). B 가 버전 6건을 한 번에 업로드, 서버 잉크 해시가 각 절 현재 필사와 같음
      · A: "Skipping unknown updated record … CD_VerseDrawingVersion" 6건 → 가져오기 성공 · 크래시 없음 · 필사 7행 그대로 · 남은 작업 0
      · A 편집: CD_BibleDrawing 레코드만 업로드, 오류 없음. 서버의 버전 6건 · 즐겨찾기 변경 태그 그대로
      · B 재실행: 가져오기 1 · 업로드 0, A 의 편집 반영, 버전 6건 내용 동일
  2부 · A 의 삭제 내보내기는 CD_BibleDrawing 8건의 ID 만 담았다. 서버: 그 8건만 삭제되고 버전 6건 · 즐겨찾기 1건은 태그까지 그대로
      · B 재실행: 필사 0행 · 버전 6건(내용 동일) · 즐겨찾기 1건, 업로드 0
  3부 · A 마이그레이션 V3 → V6 정상(크래시 · 134504 없음). 첫 실행 가져오기로 **1.3.0 일 때 건너뛴 버전 6건과 즐겨찾기 1건을 모두 받았다**
      — versionID · 절 · 종류 · 잉크 크기 · 해시 · 메타데이터 크기와 즐겨찾기 내용이 B 와 같다. 업로드 0
전후 원본·메타데이터·계보 비교 / 화면 확인: 저장소 · 서버 조회로 비교(화면 확인은 하지 않음)
크래시·오류 / 로그·스크린샷 경로: 없음 / —
관찰 시간 / 종료 코드 / 미수행 단계: 약 20분 / — / 관계 있는 엔티티 · 큰 blob(CKAsset) · 두 기기 동시 수용 · 실기기
판정: **통과(관측 범위) — 1.3.0 은 새 엔티티 레코드를 건너뛰고, 기존 필사 왕복 · 전체 삭제가 새 레코드를 건드리지 않았으며,
  건너뛴 기기를 새 스키마로 올리면 그 레코드를 받았다.** 각 1회
제한과 다음 조치: 3부에서 다시 받게 된 원리(변경 토큰 초기화 등)는 로그로 확인하지 못했다. A 는 더 이상 1.3.0 이 아니다 —
  1.3.0 이 필요한 남은 시험은 새 시뮬레이터에 OLD 를 깔아야 한다. 시드 훅은 실제 수용 규칙(C3 · C5)이 아니다
```

### MIG-F1 — 저장소 준비 실패 · V1 폴백 상태의 편집 진입 (추가 확인 항목)

```text
케이스 ID / 수행일: MIG-F1 / 2026-09-17
OLD·CURRENT·NEW 커밋 / 테스트 변경 diff: 수정 전 = develop 2c124cb3(Debug) / 수정 후 = fix/mig-f1-store-load-failure 작업 트리(커밋 전)
  앱 코드의 테스트용 변경 없음. 시험 저장소는 단위 테스트 하네스로 만들었다(저장소 밖, 확인 뒤 삭제):
  ① V6 — V5 의 BibleDrawing 에 optional 필드 하나를 더한 앱이 모르는 스키마 ② 1.0.x — 1.0.7 의 버전 없는 DrawingVO(isWritten)
  ③ 손상 — 0x5A 8,192 B
기기 A·B OS / 빌드 도구 / 환경 별칭: 전용 임시 시뮬레이터 Carve-MIGF1-tmp · iPad mini (A17 Pro) · iOS 26.2(확인 뒤 삭제)
  / Xcode 26.3 · tuist 4.208.0 / iCloud 미로그인 · Carve.dev.sqlite
초기 표본·행/버전 수 / 원본 해시: 창세기 1장 1절 1행(RealLegacyLineData 580 B)
  ① 77,824 B · sha256(hex) b4c5041d0de1893b ② 69,632 B · d7133e26edba7af2 ③ 1ae62b3110141bf4
오프라인·재연결 순서 / 실제 조작: 앱 설치 → 첫 실행 전에 Library/Application Support 에 저장소를 넣음 → 실행 → 시점별 캡처(simctl io).
  수정 후 ② 에서만 알림의 「확인」 을 한 번 눌렀다. 필기 입력은 하지 않았다
로컬 저장 성공 / export·import 결과 / 실제 수신 확인: 해당 없음(계정 없음)
전후 원본·메타데이터·계보 비교 / 화면 확인:
  [수정 전 ①] 134504 → V1 폴백 성공("Persistent History has to be truncated … BibleDrawing, BiblePageDrawing, FavoriteVerse")
    → 창세기 1장 편집 화면에 들어갔고 1절 필기가 없다. 저장소는 ZBIBLEDRAWING 이 없어지고 ZDRAWINGVO 0행(sha256 aeb517acc3c2ac1e)
  [수정 전 ②] 134504 → V1 폴백 → 2.5초 「iCloud 계정을 확인해 주세요.」 → 4초 편집 화면, 1절 필기 안 보임. 재실행 알림은 뜨지 않았다
    (저장소는 V1 모양 ZDRAWINGVO 1행 580 B). 재실행하면 V1 → V5 로 옮겨져 필기가 보인다 = 첫 실행이 저장 불가 상태로 들어갔다
  [수정 후 ①] 1 · 3 · 6 · 25초 모두 시작 화면 「필사 저장소를 열 수 없어 시작하지 않았어요. / 더 새 버전의 앱에서 쓰던 저장소로 보여요. …」.
    25초 뒤에도 프로세스는 살아 있고 들어가지 않았다. 저장소 sha256 전후 같음(b4c5041d…) · WAL 0 B 그대로 · 행과 V6 필드 값 유지
  [수정 후 ②] 1초 시작 화면 → 3 · 6 · 12초 알림 「앱을 다시 실행해 주세요 / 이 기기의 필사를 새 형식으로 옮기려면 앱을 다시 실행해야 해요.」
    (계정 없음이라 iCloud 문구 없음) → 「확인」 → 프로세스 종료 → 저장소 ZDRAWINGVO 1행 580 B
    → 재실행 3 · 8초 편집 화면, 1절 필기 표시 · ZBIBLEDRAWING 1행 580 B(id …1700000000)
  [수정 후 ③] 4초 시작 화면 「필사 저장소를 읽지 못해 시작하지 않았어요. …」, 파일 sha256 같음
  [단위 테스트] DomainTest LocalStoreLoadFailureTesting 9 · LaunchRouteTesting 6 추가, CloudObservationOrderTesting 1 기대 변경
    (마이그레이션 한도 초과 stillWaiting → migrationEndedWithoutImport). 수정 전 결함은 이전 폴백을 흉내 낸 재현 테스트로 남겼다
크래시·오류 / 로그·스크린샷 경로: 크래시 없음. 캡처 · 저장소 사본은 세션 임시 폴더에서 판독한 뒤 지웠다(저장소 밖)
관찰 시간 / 종료 코드 / 미수행 단계: 실행당 약 5~25초 / 단위 테스트 전체(Carve-Workspace, CarveAppUITests 제외) 615 통과 · 실패 0 — ** TEST SUCCEEDED **
  / 실기기 · iCloud 계정 있는 상태(import 성공 · 실패 · 시간 초과 결론의 화면) · 실제 마이그레이션 실패(디스크 부족 등)의 화면 · 저장 표시(필기 없음)
판정: 수정 전 실패(① ② 모두 정상 저장이 불가능한 채 편집 화면 진입) → 수정 후 통과(시뮬레이터 · 단위 테스트 범위)
제한과 다음 조치: 수정 후 ② 의 「앱을 다시 실행해 주세요」 는 계정 없음 문구만 화면으로 봤다. 계정이 있을 때의 import 성공(기존 「데이터 마이그레이션이 완료」) ·
  실패 · 시간 초과 문구는 단위 테스트의 상태 판정까지만 확인했다. 기기 잠금 전 백그라운드 실행처럼 파일을 잠시 읽지 못하는 경우 그 실행은
  막힌 채 남아 앱을 다시 열어야 한다(추정 — 재현하지 않았다). 이전 빌드(1.3.0 · V4 개발 빌드)의 동작은 바뀌지 않는다(F7 ③).
```

**MIG-F1 리뷰 반영 — 인계 (2026-09-17, 진행 중).** 위 기록은 **1차 수정** 기준이다. 같은 날 외부 리뷰가 수정 방향과 "기존 V5 정의를 두고 새 버전(V6)으로 올리기" 에 동의하면서 아래를 짚었다. 브랜치 `fix/mig-f1-store-load-failure` 의 커밋이 이 시점 상태이고, 다른 세션에서 이어간다.

| 지적 | 상태 |
|---|---|
| 엔티티 이름 `{DrawingVO}` 만으로 1.0.x 로 판정했다 — 필요조건을 충분조건으로 썼다 | ✅ 확인된 1.0.x 모양 두 가지(1.0.0~1.0.3 · 1.0.4~1.0.7, `UnversionedDrawingStore`)와 **해시가 맞을 때만** V1 폴백한다. 반례(이름만 같고 필드가 다른 `DrawingVO` 저장소 → `unknownVersion` 으로 막힘 · 바이트 불변)와 두 모양의 이관을 테스트로 고정했다. ✅ 1.0.0 의 `let` 선언도 `var` 모양과 **엔티티 해시가 같다**(2026-09-18 실측, 기본값 유무도 해시를 바꾸지 않는다) — 한 모양으로 1.0.0 ~ 1.0.3 을 받는다. 다만 해시는 오늘의 SwiftData 가 계산한 값이고, 2024년 1.0.0 이 만든 실제 저장소와 대조하지는 못했다 |
| "파일을 건드리기 전에 판별" · "지우거나 바꾸지 않았어요" 는 구현보다 강하다 — 앱 스키마로 여는 첫 시도는 이미 한 뒤다 | ✅ 코드 주석 · 문서를 "V1 폴백 전에" 로 좁혔고, 화면 안내를 보장 범위로 바꿨다 — 「필사를 지키려고 시작을 멈췄어요」 + 경우별 이유 + 「앱을 지우지 마세요. 같은 안내가 계속되면 <문의 주소> 로 알려 주세요」. `unknownVersion` 은 업데이트를 "열릴 수 있어요" 로만 제시한다(버전 없이 고친 스키마도 포함하므로). 시뮬레이터에서 문구 표시를 확인했다 |
| 진입 대기 효과와 진입 직전 재검사가 검증되지 않았다 — 대체 컨테이너는 저장을 거절하지 않는다 | ✅ 진입 대기 효과를 취소할 수 있게 하고 막힘 · 재실행 요구에서 끊는다. 코디네이터가 `.syncCompleted` 에서 `launchRoute` 를 다시 확인한다. 상태 쪽 불변(진입 결론은 늦게 온 이벤트 · 대기로 막힘 · 재실행 요구가 되지 않고, 그 반대도 아니다)을 `LaunchRouteTesting` 으로 고정했다. ⬜ App 모듈에는 테스트 타깃이 없어 효과 취소 · 코디네이터 확인 자체는 빌드와 시뮬레이터 실행으로만 확인했다 |
| "바뀐 코드는 실패 때만 돈다" 는 부정확하다 — 정상 경로도 로더와 진입 판정을 거친다 | ✅ 수정 빌드로 정상 V5 회귀를 확인했다(2026-09-18, 전용 임시 시뮬레이터 · iCloud 미로그인): 기존 V5 저장소(1절 1행)를 열어 2절에 손가락 필기 두 획 → 종료 뒤 저장소에 2절 행(v3 · 잉크 711 B · metadata 227 B) 생성, 1절 행 그대로 → 재실행에 두 획이 그대로 보인다. ⬜ 동기화 회귀는 샌드박스 계정 기기가 필요해 하지 않았다 |
| (대화에서 제안한) B · C 에 수정 V5 빌드를 설치하는 순서 | ❌ 폐기 — ENT-P1 로 A · B · C 는 이미 **V6 스파이크 저장소**다. V5 빌드는 수정본이면 막히고, **수정 전 develop 빌드(`2c124cb3`)면 V1 폴백으로 로컬 저장소를 지운다.** 이 세 기기에 V5 빌드를 설치하지 않는다 |
| V5 재정의 + 테스터 앱 삭제 · 재설치 | ❌ 택하지 않는다(리뷰 권고) — 업로드 완료와 복원 가능성이 증명되지 않았다. 기존 V5 정의를 두고 새 버전으로 올린다 |


출시 전에 MIG-F1 로 더 볼 것(리뷰): 실제 1.0.x · 동기화 이력이 있는 저장소 **사본**에서 판별 · 이관 · 필사 보존 / iCloud 로그인 상태에서 마이그레이션 성공 · 실패 · 시간 초과와 늦은 이벤트에도 진입 차단 / 보호 데이터 접근 실패 뒤 잠금 해제 · 재실행 복구와 실제 열기 실패에서 원본 보존 / 정상 V5 업데이트 뒤 새 필사 저장 · 재실행 조회, 최종 후보 모델의 V3 · V5 → V6 이관.

### RAW-E1 — 원시 사본과 V6 마이그레이션의 실제 앱 경로 (2026-09-18)

```text
케이스 ID / 수행일: RAW-E1 / 2026-09-18
커밋: develop bbae71ef + 작업 트리(원시 사본 · 스키마 V6 · 삭제 판정 상태 저장소, 미커밋)
기기 / 빌드 / 환경: 전용 임시 시뮬레이터 Carve-RAW-tmp(iPad Pro 11-inch M5, iOS 26.2 — 앱이 iPad 전용이라 iPhone 은 설치 거부)
  / Debug / iCloud 미로그인 · Carve.dev.sqlite
초기 표본: Carve-Migration-Test 의 V5 dev 저장소 사본 — 필사 행 1, 즐겨찾기 테이블 있음, 외부 저장 0,
  sqlite 77,824 B(sha256 f30f4e5554e93dd5…) · 미반영 WAL 1,149,512 B(5a6fefd8d55b5992…)
실제 조작: 설치 → 첫 실행 전에 저장소 파일을 컨테이너에 넣음 → 실행 → 파일 · 화면 확인 → 기기 삭제
결과:
  ① Preservation/Carve.dev.sqlite/raw/<id>/ 에 sqlite · -wal · -shm · manifest.json 이 생겼다. 사본의 sqlite · -wal
     해시가 넣은 원본과 같다 — 마이그레이션 전 원본이다. 사본을 복제해 열면 V5 테이블만 있고 필사 행 1(같은 rowUUID)
  ② 본 저장소는 V6 로 올라갔다 — ZVERSEDRAWINGVERSION · ZDRAWINGERASEEPOCH 테이블, ZFAVORITEVERSE.ZKNOWNERASEEPOCHS
     열이 생겼고 필사 행 1 이 그대로다
  ③ 시작 화면에서 막히지 않고 창세기 1장 필사 화면에 들어가 1절의 기존 필기를 보였다
판정: 통과(관측 범위, 1회). 외부 저장 파일이 있는 저장소 · 1.3.0(V3) 저장소의 실제 앱 경로는 단위 시험으로만 확인했다
  (RawStoreSnapshotTesting · DrawingSchemaV4MigrationTesting). 공간 부족 막힘 화면은 실기기에서 아직 보지 않았다
```

### ACC-1 1차 — 앱을 끈 채 A→B · 켠 채 B→A · 미전송 편집을 둔 A→B→A (2026-09-18)

```text
케이스 ID / 수행일: ACC-1 1차(시나리오 1 ~ 3) / 2026-09-18
커밋: feat/verse-drawing-versions 00a714cf(②-1) Debug 빌드 — 저장은 아직 BibleDrawing 에 한다(② 의 초안 전용 저장 전)
기기 / 환경: 전용 시뮬레이터 두 대(iPad, iOS 26.2) — Carve-ACC-dut(A ↔ B 전환), Carve-ACC-B(B 고정) · dev 컨테이너 · Carve.dev.sqlite
  / 샌드박스 계정 A(기존) · B(새로 만듦). 계정 식별 원문은 남기지 않고 해시로만 대조했다
초기 표본: 같은 절(창세기 1:1, NKRV)에 A 는 지그재그(행 C12C3B32), B 는 고리(행 04C0C05F) — 둘 다 업로드 대기 0 확인.
  A 서버에는 이전 시험의 버전 6 · 즐겨찾기 1 도 있다
관측: 2초 간격 관측기(저장소 행 · 업로드 대기 · 미러링 식별 해시 · 앱의 마지막 확인 범위, 바뀔 때 화면), CoreData 디버그 로그,
  서버 조회(probe.sh). 자료는 저장소 밖 세션 임시 폴더라 남기지 않는다

시나리오 1 — 앱을 끈 채 A→B
  조작: 앱 종료 → 사용자가 설정에서 A 로그아웃 · B 로그인 → 앱 실행
  ① 실행 전 저장소는 그대로였다(A 행 · 식별 A · 앱 범위 A)
  ② 설정 시작(13:21:53.93) 0.43초 뒤 사용자 레코드 조회에서 식별 변경을 알아채고(ResetSyncReason 3), 다섯 엔티티의 행과
     CloudKit 메타데이터를 지웠다(54.364 ~ .368)
  ③ 1초: 행 0 · 식별 B · 앱 범위 B, 시작 화면 / 3초: 가져오기 1건 대기, 시작 화면 / 6초: B 의 고리 행, 1:1 에 고리
  ④ A 의 지그재그는 화면에 한 번도 나오지 않았다. B 서버에는 고리 행 하나뿐이다(A 표식 0건)

시나리오 2 — 앱을 켠 채 B→A
  조작: 창세기 1장을 연 채 홈 → 사용자가 설정에서 B 로그아웃 · A 로그인 → 앱으로 복귀
  ① 시간 순서(13:26): 전경 복귀 46.85 → 미러링의 계정 조회 47.234 → 앱이 A 확인(범위 파일 기록) 47.239
     → 미러링이 B 행 삭제 47.254 ~ .257 → 설정 성공 48.238 → A 행 가져오기 49.109
  ② 저장소 최종: A 의 지그재그 · 즐겨찾기 · 버전 6, 식별 A, 앱 범위 A, 업로드 대기 0. A 서버에 B 고리 행 없음(0건)
  ③ 화면: 복귀 전 1:1 에 B 의 고리 → 복귀 뒤 1:1 이 비었다. A 의 지그재그와 즐겨찾기 별표가 저장소에 들어온 뒤에도
     13:30:27(3분 38초 뒤)까지 빈 채였다
  ④ 빈 1:1 에 손가락으로 체크를 그었다: 새 행 CC15BD7C(present 1)가 A 서버로 올라갔고(13:35:41 성공), 지그재그 행
     (present 1)도 저장소 · 서버에 그대로다. 재실행하면 1:1 에 체크만 보이고 지그재그는 가려졌다(대표 규칙: present 중 최신)

시나리오 3 — 미전송 편집을 둔 채 앱을 끄고 A→B, 다시 A
  준비: A 상태에서 1:2 에 Z 를 그었다 — 저장 0.7초 뒤 A 서버로 올라갔다(13:40:23). 그래서 행이 늘어나는 즉시 앱을 끝내는
     감시기를 두고 1:3 에 W 를 그었다 — 행을 본 뒤 0.15초에 종료(13:41:36.90). W 행(78632BD2)은 CloudKit 레코드 매핑이
     없었다(= 전송 전)
  ① 사용자가 설정에서 A → B. 실행 전 저장소는 그대로(행 4 · W 미전송 · 식별 A · 앱 범위 A)
  ② 실행(13:46:33) 2초 뒤 식별 변경을 알아채고 W 를 포함한 다섯 엔티티의 행을 지웠다(35.074 ~ .083). 그 전에 전송은 없었다.
     1초: 행 0 · 식별 B · 앱 범위 B / 6초: B 의 고리. B 서버에는 고리 행 하나뿐이다(A 쪽 표식 0건)
  ③ 앱을 끄고 사용자가 B → A. 실행(13:58:31) 1초: 행 0 · 식별 A · 앱 범위 A / 3초: 지그재그 · 체크 · Z · 즐겨찾기 · 버전 6.
     W 는 로컬과 A 서버 어디에도 없다(서버 조회 10건, W · B 고리 0건). 화면은 1:1 체크(지그재그 가림) · 별표 · 1:2 Z, 1:3 빈 칸

시나리오 4 — 로그아웃 상태에서 쓴 필기와 다음 로그인(A 로그아웃 → 필기 → B 로그인)
  ① 앱을 끄고 사용자가 A 로그아웃. 실행 전 저장소는 A 상태 그대로(행 3 · 식별 A)
  ② 실행(14:02:45) 직후 계정 없음을 보고 "AccountLogout" 사유로 다섯 엔티티의 행과 메타데이터를 지웠다(.597 ~ .603).
     계정 식별 항목도 없어졌다. 이어서 설정이 134400(계정 없음)으로 멈췄다. 앱의 마지막 확인 범위 파일은 A 로 남았다(힌트)
  ③ 빈 화면의 1:4 에 삼각형을 그었다 — 로컬 행(A4398D80), CloudKit 레코드 매핑 없음
  ④ 앱을 끄고 사용자가 B 로그인. 실행(14:05:02) — 초기화 · 삭제 없이(관련 로그 0줄) 식별 B 로 설정했고, 3초에 삼각형에 레코드
     매핑이 생겨 14:05:06 B 서버로 올라갔다. B 서버: 고리 + 삼각형

판정: 계정 간 유출 없음(양쪽 서버 조회, 전환마다 1회). 현재 빌드에서 세 가지 실패를 재현했다 — 실행 중 전환의
  "낡은 화면 → 기존 필기 가림"(시나리오 2), 전환 때 **미전송 편집 유실**(시나리오 3, 원래 계정으로 돌아와도 되살아나지 않음),
  **로그아웃 상태 필기의 자동 귀속**(시나리오 4, 다음에 로그인한 계정으로 올라감 — 정책 위반).
  후보 A(미러링 식별)는 관측 순서만 기록하고 채택 판단은 보류한다 — 원자성 · 단계 사이 종료를 시험하지 않았다
미수행: 네트워크를 끊은 전환, 앱을 켠 채 로그아웃, 단계 사이 종료, 무표식 legacy · 빈 저장소
```

### ACC-1 2차 — ②-2 보완 빌드로 다시 (진행 중, 2026-09-21)

```text
케이스 ID / 수행일: ACC-1 2차(1차-4 · 주입 경로 · 기존 필기 수정의 F29) / 2026-09-21
커밋: feat/verse-drawing-versions bea3e5df(②-2, 10차 리뷰 보완) Debug 빌드 — dev 컨테이너
기기 / 환경: 1차와 같은 전용 시뮬레이터 두 대 — Carve-ACC-dut(전환 대상) · Carve-ACC-B(B 고정 관측)
  / 앱 데이터는 1차 상태를 그대로 두고 덮어 설치했다. 시작 표본은 지우기 전에 보관했다(저장소 밖 작업 폴더)
관측: 2초 간격 관측기 · 저장소 스냅숏 · 서버 조회(probe.sh) · **초안 폴더 요약**(acc1/drafts.py — 묶음 · 세션 · revision ·
  저장 표식 · 계정 근거 · 소유(주입 표식) · 기준 · 내용을 해시 앞자리로). 계정 식별 원문은 남기지 않았다

시나리오 1차-4 재시험 — 로그아웃 상태 필기 → B 로그인 (주입 없음)
  ① 두 기기 모두 로그아웃 상태에서 시작(앱의 마지막 확인 범위는 B). 1:2 에 획 하나
     → 저장소 행 그대로(2행 · 업로드 대기 0), **초안 파일 1개**(확인 전 묶음 · 저장 표식 없음 · 소유 없음), 화면은 "이 기기에 저장됨"
  ② 앱을 끄고 사용자가 B 로그인 → 실행 50초 관측: 행 2 그대로 · export/import 0 · 앱 범위 B
  ③ B 서버 조회: 레코드 2건(1차의 것)뿐 — 로그아웃 때 쓴 획은 서버에 없다. **F30 재현 안 됨**
  ④ 다만 그 초안은 확인 전 묶음(acct-unverified)에 있어 **B 로 확인된 뒤에는 화면에 보이지 않는다**(파일은 남는다)

주입 경로(DEBUG 소유 주입 · 실행 인자) — 결과는 주입 없는 시험과 따로 적는다
  ⑤ 실행하자 경고 로그와 화면 배지("소유 주입(DEBUG) · 소유 증명 아님")가 떴다
  ⑥ 빈 절 1:3 에 필기 → 초안(보내는 중) → 저장소 행 → 초안 표식 **들어감** → 서버 업로드까지 확인(레코드 3건)
  ⑦ **보이기만 하는 초안을 이은 절(1:4)** 에 필기 → 주입 세션인데도 저장소에 쓰지 않고 원 초안의 출처를 이었다(표식 없음 · 소유 없음)
  ⑧ 사용자가 실수로 그은 획을 되돌리기(Undo)로 지운 경우 — 초안은 지워지지 않고 "내용 없음" 의 새 revision 으로 남았다(1:5 rev 3)

기존 필기 수정의 F29 (주입)
  ⑨ 1:3 을 다시 고치고 **저장 0.15초 뒤 앱 강제 종료**(acc1/kill-on-edit.py) → 로컬 행은 새 잉크, 초안 rev 3 표식 들어감,
     **B 서버는 옛 잉크 그대로 — 전송 전이었다**
  ⑩ 앱을 끈 채 B → A 전환 후 실행: B 행이 모두 사라지고 A 의 행 · 즐겨찾기 · 버전이 들어왔다. **초안 4개는 그대로 남았고**,
     A 세션 화면에는 B 의 초안이 보이지 않는다(계정 간 유출 없음)
  ⑪ A → B 복귀 뒤 확인: 저장소의 1:3 행이 **서버의 옛 잉크로 돌아왔다**(전송 전 수정은 사라졌다). 초안 4개는 그대로 남았고,
     1:4 의 보이기만 하는 초안은 화면에 겹쳐 보였다. 그러나 **1:3 의 전송 전 마지막 내용은 화면에 보이지 않았다** —
     초안은 "넣었다"(`storeState`)만 알고 **무엇을 넣었는지** 몰라, 돌아온 행이 내가 앞서 넣은 내용인지 남의 변경인지 가리지 못한다
  ⑫ 고침(사용자 결정 2026-09-21): ① 표식을 남길 때 **넣은 내용의 지문**(`sentFingerprints`, 최근 5개)도 남긴다 — 돌아온 행이 그 가운데
     하나면 그 뒤 revision 을 유일한 사본으로 이어 본다 ② 확인 전(`acct-unverified`) 묶음의 초안도 **그때 참고하던 계정이 지금 계정과 같으면**
     함께 읽어 **보이기만** 한다(묶음 · 출처 · 저장소는 그대로)
  ⑬ 고친 빌드로 다시 설치해 확인: 로그아웃 때 쓴 1:2 획이 B 세션 화면에 **다시 보였고**, 이어 그은 획은 확인 전 묶음에 그 근거로 남았으며
     저장소에는 1:2 행이 생기지 않았다. 주입 세션의 새 필기(1:5)는 저장소로 가고 초안에 **넣은 내용의 지문**이 남았다
  ⑭ 고친 빌드로 ⑨ ~ ⑪ 을 다시: 1:5 를 고치고 저장 0.15초 뒤 종료(로컬 새 잉크 · 서버 옛 잉크 · 초안 rev 3 에 **넣은 내용 지문 2개**)
     → B → A(행 삭제, 초안 5개 유지) → A → B. 행은 서버의 옛 잉크로 돌아왔고, **전송 전 마지막 획이 화면에 이어 보였다**(고침 ①).
     이어 그으니 새 세션이 그 초안을 이어받아(원 초안 대신) 저장소에 썼다 — 겹쳐 보인 것만으로는 저장소에 쓰지 않는다
  판정(이번 실행 조건 — F30 은 주입 없이 ①~③, F29 는 주입으로 ⑨~⑭): ②-2 에서 1차의 두 실패 **F29(전송 전 편집 유실) ·
    F30(로그아웃 필기의 자동 귀속)의 방어를 관측했다.** 초안은 계정 전환 · 로그아웃을 건너 남고, 보이기만 하는 초안은 귀속을 올리지 않았다.
    F29 경로(유효 세션의 저장소 쓰기)는 소유 근거가 없어 주입으로만 재현된다 — 소유 판정의 근거가 아니다. 남은 제한: 보이지 않는 초안의
    개수 안내 · 복구 진입점이 없다(④). 후보 A(미러링 식별)는 이번에도 채택 판단에 쓰지 않았다
인계 · 단계 사이 종료 (2026-09-21, ④ 읽기 전용 단계까지 올린 빌드 `1609171a`)
  ⑮ **인계(④) — 주입 없음.** 획을 긋자마자 홈: 마지막 획이 **새 세션의 초안**(1:3 rev 1 · 보존만 · 표식 없음 · 소유 없음)으로 남았고
     저장소 행은 그대로였다. **되돌리기 직후 홈**: 같은 초안의 rev 2 로 남았다(되돌린 뒤의 화면 그대로 — 초안을 지우지 않는다).
     "인계 재요청" 로그는 없었다 — 뷰가 제때 답했다는 뜻이다. **긴 획 중 전환 · 인계 뒤 늦은 보고는 기기에서 만들지 못했다**
     (계획대로 단위 시험 `ChapterCanvasHandoffPresenceTesting` · `ChapterCanvasClosedSessionTesting` 으로 대신한다).
     사이드바를 연 채 전환(캔버스 없음)은 계정 조작이 필요해 남았다
  ⑯ **단계 사이 종료(⑤) — 주입.** 초안 파일이 바뀌는 즉시 종료(`acc1/kill-on-draft.py`, 폴링 50ms · 8ms 두 번). 두 번 모두
     **초안 · 저장소 · 표식이 이미 끝난 뒤**였다 — 초안 → 저장소 → "들어감" 사슬이 밖에서 보기에 10ms 안에 끝난다.
     재실행 뒤 초안은 그대로였고 저장소 행은 4개 그대로였다(중복 · 유실 없음). 화면에도 두 획이 남았다.
     **"보내는 중" 중간 상태는 기기에서 잡지 못했다** — 단위 시험(`ChapterCanvasDraftOrderTesting`)으로만 고정돼 있다.
     **전체 삭제 경계는 하지 않았다** — 시험 데이터를 지우는 조작이라 사후 정리와 함께 사용자 확인을 받고 한다
  ⑰ 그 사이 서버 대조: 1:1 · 1:5 의 새 잉크가 B 서버로 올라갔다(probe 2회 — 첫 조회에서는 1:5 가 아직 옛 잉크였고, 조회의 재실행이
     내보내기를 밀어 두 번째에 올라갔다). 초안 8개 · 저장소 4행 · 서버 4레코드로 세 자리가 맞았다
앱을 켠 채 로그아웃 · A 로그인 · 오프라인 (2026-09-21, 사용자가 계정을 조작하고 에이전트가 관측)
  ⑱ **앱을 켠 채 로그아웃.** 13:32 에 저장소 행 4개와 미러링 식별이 **한꺼번에** 사라졌다(관측기 2초 간격). **초안 8개는 그대로.**
     돌아온 화면은 빈 장이었다 — 지금 근거(로그인 안 함)로는 B 묶음을 읽지 않으므로 **맞는 동작**이다(계정 간 유출 없음).
     그 상태에서 빈 절에 그은 획은 **이 기기 전용 묶음**(`localOnly` · 표식 없음 · 소유 없음)의 초안에만 남고 **저장소 행은 0 그대로**였다
     — F30 막음. 절 메뉴에서 「지우기」 · 「이전 필사 내용 보기」 가 빠져 있었다(저장소에 쓰지 않는 세션)
  ⑲ **⑥ 무계정 · 소유 미확인의 즐겨찾기 · 위젯 — 사유를 보이고 막는다(통과).** 로그아웃 상태의 「즐겨찾기에 추가」 는
     「즐겨찾기에 추가하지 않았어요 · iCloud 에 로그인하지 않았어요」 를, 보이기만 하는 초안을 이은 절은 「이 절의 필기는 다른 계정 ·
     확인 전에 쓴 것이에요」 를 띄웠고 `FavoriteVerse` 행은 늘지 않았다. 로그는 `환경을 읽었다: noAccount → 막았다 → 안내` 순이다.
     **처음에는 "안내가 없다" 고 잘못 적었다** — 안내는 5초만 떠 있는데 조작(MCP)과 캡처(simctl) 사이가 10초여서 놓쳤다.
     **교훈: 사라지는 안내는 캡처 반복을 먼저 띄워 놓고 조작한다**(초당 1장, 시각을 파일 이름에 남긴다)
  ⑳ **1차-2 앱을 켠 채 B → A(로그아웃 뒤 로그인).** 13:43:21 에 식별 · 앱 범위가 A 로 바뀌고 곧 A 의 행 3 · 즐겨찾기 1 · 버전 6 이 들어왔다.
     **F26 재현** — 행이 들어온 뒤에도 열린 장은 빈 채였다(③ 까지 남는 제한). **F27 은 막혔다** — 그 낡은(빈) 화면의 1:1 에 그은 획은
     **A 묶음 초안(기준 "빈 절")** 에만 남고 저장소 3행은 그대로였으며, 재실행하니 A 의 필기가 제대로 뜨고 **내 초안은 기준이 달라져 감춰졌다.**
     그 절의 롱탭 메뉴에 ④ 의 「남은 필기 1」 이 떴다
  ㉑ **오프라인.** 계획은 "네트워크를 끊은 채 전환" 이었으나 **오프라인에서는 iCloud 로그아웃 자체가 막힌다**(사용자 확인) — 그래서
     로그아웃(온라인) → 네트워크 끊기 → 필기 → 재연결 순으로 바꿔 수행했다. 오프라인에서 그은 획은 **이 기기 전용 묶음 초안**으로만 남고
     저장소는 0 그대로였다. **F25 추정(오프라인 전환에서 옛 행이 남는다)은 이 방법으로 확인할 수 없다** — 전환 자체가 온라인을 요구한다.
     다른 방법(미러링만 끊기)을 찾거나 추정으로 남긴다
  ㉒ **사이드바를 연 채 전환 — 캔버스 없음(④ 의 마지막 조각).** 1:3 에 획을 하나 긋고 곧바로 즐겨찾기 목록으로 나가(캔버스가 화면에서 사라진 상태)
     사용자가 B 로 로그인했다. 14:16:52 에 장을 다시 읽고(`kept=3 · settled=1`), 14:16:53 에 식별 · 앱 범위가 B 로, 14:16:58 에 B 의 행 4개가 들어왔다.
     **「인계 재요청」 로그가 없다** — 캔버스가 없으니 응답을 기다리지 않고 닫았다(설계대로). 전환 직전의 획은 **이 기기 전용 묶음 초안으로 그대로**
     남았고(세션 `d6adaf` rev 1) B 묶음으로 새지 않았다. **초안 13개 전부 보존.** 돌아온 B 세션은 B 의 저장소 내용과 확인 전 묶음(힌트 B)의 초안을
     보이고 이 기기 전용 초안은 보이지 않았다. ④ 화면도 네 묶음을 갈랐다 — 지금 계정 7개(안 보이는 것 3) · 확인 전 1개(0) · 다른 계정 1개(1) ·
     로그인하지 않은 동안 4개(4)
  ㉓ **전체 삭제 경계(⑤ 의 남은 조각) — 사용자 승인 뒤 수행.** 설정 → iCloud → 「모든 필사 데이터 삭제」 → 「모두 지우기」.
     - **보존 영역이 통째로 지워졌다** — 초안 13개(네 묶음 전부)와 폴더가 사라지고 `Preservation/<저장소>/` 가 비었다
     - **삭제 세대 0 → 1**(`local-erase-generation.json` 이 생겼다). 그 뒤 그은 획은 **세대 1** 의 초안으로 남는다 —
       세대 0 을 든 늦은 쓰기는 거절된다(기기에서 경쟁을 만들지 못해 단위 시험으로 고정)
     - 저장소 0행 · 즐겨찾기 0, **서버도 0 레코드**(tombstone 확인). **마지막 확인 범위(계정 기록)는 남았다** — 설계대로다
     - 관측기가 14:25:50 에 행 4 → 0 을 잡았고, 그때 **미러링 식별은 그대로였다**(`id=e93024`). 로그아웃 · 계정 전환은 식별까지 지우는데
       (⑱ · ⑳) **전체 삭제는 행만 지운다** — 기기는 그대로 그 계정에 묶여 있어 그 뒤의 쓰기는 같은 계정으로 간다
     - ④ 화면은 「이 기기에 남은 필기가 없어요」 로 바뀌었다
     - **찾은 것(고침):** 확인 문구가 **남은 필기를 말하지 않았다.** 게다가 "지울 것이 있는가" 판정이 저장소 · 즐겨찾기 · 위젯만 보아,
       **저장소가 비고 초안만 남은 상태에서는 「지울 필사 데이터가 없어요」 로 닫혔다**(계정 전환 뒤 실제로 그런 상태가 된다).
       판정에 남은 필기를 더하고 문구에 수까지 적게 고쳤다(시험 `CloudSettingsEraseCopyTesting`). 세지 못하면 **없다고 단정하지 않는다**
  수행 범위(2026-09-21 후속 리뷰 P1-7 로 문구 교정 — 예전 줄 "미수행: 없음 — 계획된 시나리오를 모두 수행했다" 는 근거보다 강했다):
    계획된 조작을 **가능한 범위에서** 수행했다. **단계 사이 실제 종료(⑯ — "보내는 중" 중간 상태)와 긴 획 중 전환(⑮)은 기기에서
    재현하지 못했고** 단위 시험으로 일부 검증했다(`ChapterCanvasDraftOrderTesting` · `ChapterCanvasHandoffPresenceTesting` ·
    `ChapterCanvasClosedSessionTesting` · 재실행 복구 `LocalPreservationWriterTesting.sendingDraftSurvivesRelaunchAsUncertain`).
    F25 는 이 방법(네트워크를 끊은 채 전환)으로 확인할 수 없었다 — 오프라인에서는 로그아웃 자체가 막힌다(㉑)
  판정 범위: F29 · F30 · F27 은 **"이번 실행 조건에서 방어를 관측했다"** 로 한정한다. 주입 · 비주입을 나눠 적는다
    - F30(로그아웃 필기의 자동 귀속) — 주입 없음(①~③): 로그아웃 때 쓴 획이 로그인 뒤 저장소 · 서버로 가지 않았다.
      ⑱(켠 채 로그아웃)도 같은 결과였으나 그 실행의 주입 여부는 기록하지 않았다
    - F29(전송 전 편집 유실) — 주입(⑨~⑭): 유효 세션의 저장소 쓰기 경로는 소유 근거가 없어 주입으로만 재현된다
    - F27(낡은 화면이 기존 필기를 가림) — ⑳ 한 번: 그 실행의 주입 여부는 기록하지 않았다
```

### P0-3 기기 확인 — 늦게 도착한 필사의 반영 · 시작 화면 선택형 대기 (2026-09-21)

```text
케이스 ID / 수행일: P0-3 기기 확인(정책 §3-2 기기 확인 계획 ①~⑤) / 2026-09-21
커밋: feat/verse-drawing-versions 712bdaac(코드는 a2b11942 와 같다) Debug 빌드 — 코드 변경 없음(진단 로그도 넣지 않았다)
기기 / 환경: ACC-1 과 같은 전용 시뮬레이터 두 대(iPad Pro 11 M5 · iOS 26.2) — Carve-ACC-dut(받는 쪽 · 재설치 대상) · Carve-ACC-B(다른 기기)
  / 샌드박스 계정 B · dev 컨테이너. 두 기기의 시작 전 앱 데이터는 저장소 밖 작업 폴더에 백업했다
조작 · 관측: 탭 · 획 · 롱탭은 axe(XcodeBuildMCP 에 들어 있는 시뮬레이터 CLI). 앱 콘솔 로그 · CoreData 로그(log show) · 캡처(0.2~1초 간격) ·
  저장소 스냅숏(ckstore) · 초안 요약(acc1/drafts.py) · 서버 조회(probe.sh — 표본 확인 때만). 계정 식별 원문은 남기지 않았다
사용자 결정(이 수행): ② · ③ 은 단위 시험(ChapterCanvasArrivalTesting)을 기본 근거로 둔다. 가져오기를 늦추는 도구(dylib)는 쓰지 않는다.
  기기에서는 "먼저 시작하기 → 필기 → import" 순서를 보조로 시도하고, 만들지 못하면 재현 조건 미충족으로 적는다.
  단위 시험 통과와 기기 미확인을 나눠 적고, 미재현만으로 기능 축소 · 문구 변경은 하지 않는다

표본: ACC-B 를 주입(-ACC1InjectStoreOwnership)으로 띄워 창세기 1:1 · 1:2 · 1:3 에 획 → 저장소 3행 · 업로드 대기 0,
  서버 B 레코드 3건(잉크 해시가 저장소와 같다. 그 밖에 전체 삭제의 tombstone 4건). 앱이 처음 여는 장(창세기 1장)이다

① 초기 복원 화면 — 새로 깔아 아무것도 누르지 않음(Run 1)
  실행 17:16:16.58 → 대기 방식 initialRestore 17.58 → 미러링 설정 17.99 → import 성공 18.82(실행 2.2초 뒤, 3행)
  → 「데이터 동기화 완료」 → 1.5초 뒤 진입, 1:1~1:3 표시. 설치 결과 initialRestoreOutcome = importSucceeded
  - 대기 화면의 첫 프레임(17.90): 「iCloud에 저장된 필사를 확인하고 있어요. 먼저 시작해도 기존 필사는 도착하는 대로 화면에 반영하거나
    알려 드려요.」 와 **「먼저 시작하기」 가 처음부터** 있다 — 기기 확인
  - import 가 성공하면 들어간다 — 기기 확인
  - 20초 · 60초 안내, 그동안 자동으로 들어가지 않음 — **기기 미확인(재현 조건 미충족: import 가 2.2초에 끝난다)**. 단위 시험
    LaunchWaitRuleTesting 이 고정한다. 확인된 오류 상태에서 들어가지 않는 것은 ⑤ 에서 5분 넘게 봤다
  - 다시 실행하면 대기 방식 normal 로 곧바로 들어간다(④ 의 재실행 로그) — 기기 확인

② · ③ 보조 시도 — 초기 import 와 겹치는 순서(Run 2~6, 매번 새로 설치)
  「먼저 시작하기」 를 누르는 방법을 바꿔 다섯 번: 라벨이 뜨기를 기다려 탭(Run 2) · 앱 로그의 대기 방식을 보고 좌표 탭(Run 3 · 4) ·
  HID 세션을 미리 연 axe batch 로 정한 시각에 탭(Run 5 · 6). 다섯 번 모두 **import 가 끝나기 전에 눌렀다**
  (설치 결과 startedFirst, 탭 → import 완료 0.3~0.8초)
  그러나 **도착 반영 로그(「도착 반영 — 편집하지 않은 장에 …」)는 한 번도 나오지 않았고**, 장은 처음부터 1:1~1:3 을 보였다.
  장 조회는 로그를 남기지 않아 첫 조회가 import 앞이었는지 가리지 못한다 — 장 레이아웃 완성이 import 완료 0.04~0.42초 뒤였고
  Run 6 에서만 0.2초 앞섰다. import 가 약 2초라 필기를 끼울 틈은 더 없다
  → **초기 import 경로의 ② · ③ 은 기기 미확인(재현 조건 미충족)**. 단위 시험 ChapterCanvasArrivalTesting(19)이 고정한다

② 복귀 import 경로 — 편집하지 않은 장(Run 6 의 먼저 시작한 세션, 1:1~1:3 표시)
  ACC-B 가 1:4 에 X(저장소 · 업로드 확인) → ACC-dut 홈 → 복귀(17:28:37) → import 성공 · 바뀜 있음 39.819
  → 39.878 「도착 반영 — 편집하지 않은 장에 다른 필사가 도착했다. 다시 읽어 반영한다」. 캡처 39.584 는 빈 1:4, 39.924 는 X — **기기 확인**

③ 복귀 import 경로 — 먼저 시작해 편집한 장(같은 세션, 주입 없음)
  ACC-dut 이 1:3(기존 행 위) · 1:5(빈 절)에 획 → 초안 2개(저장 표식 없음) · 저장소 4행 그대로
  → ACC-B 가 1:3 을 고침(같은 행, 새 잉크 업로드) → ACC-dut 홈 → 복귀 → import 17:33:13.346
  → 13.412 「도착 반영 — 편집한 장에 다른 필사가 도착했다. 바꾸지 않고 알린다」. 화면은 내 필기 그대로에 「다른 필사가 도착했어요 · 확인하기」
  → 확인하기 → 44.289 「확인하기: 지금 필기를 보존했다. 이 세션을 닫고 새로 읽은 내용으로 다시 연다」 · 「보이지 않고 남긴 초안 kept=1」
  → 1:3 은 ACC-B 의 필기, 1:5 의 내 획은 그대로. 「이 기기에서 쓴 필기 1개는 도착한 필사와 기준이 달라 자동으로 표시하지 않아요 ·
    남은 필기 보기 · 닫기」 → 남은 필기 보기 → 설정 「남은 필기」: 초안 2개 · 5kB · 자동으로 표시되지 않는 것 1개,
    항목 「창세기 1:3 · 다른 내용이 들어옴」 → 초안 파일 2개 그대로(1:3 기준 = 옛 행, 1:5 기준 = 빈 절)
  — **기기 확인**(초기 import 가 아니라 복귀 import 로 만든 "먼저 시작 → 필기 → import" 순서)

④ 내가 저장소에 저장을 마친 절의 원격 수정 · 삭제 — 받는 쪽도 주입(ACC-dut 재실행, 대기 방식 normal)
  수정: ACC-dut 이 1:4 에 획(초안 stored · 소유 주입, 같은 행 새 잉크 업로드) → ACC-B 재실행으로 받아 1:4 를 고침(업로드)
  → ACC-dut 홈 → 복귀 → import 17:36:53.682 → 53.741 「편집한 장에 다른 필사가 도착했다. 바꾸지 않고 알린다」,
    화면은 내 1:4 그대로 — **기기 확인**(R2-1). 확인하기 → 1:4 는 ACC-B 의 필기, 방금까지 보이던 내 1:4 초안은
    기준이 달라 「필기 1개 … 남은 필기」(kept=2 — 1:3 · 1:4)
  삭제: 새 세션에서 1:4 를 다시 저장(업로드) → ACC-B 재실행 · 절 롱탭 「지우기」 → 확인(그 행의 잉크를 비우고 옛 내용은 기록 행
    present=0 으로, 둘 다 업로드) → ACC-dut 홈 → 복귀 → import 17:39:27.152 → 27.212 「편집한 장에 … 알린다」 — **기기 확인**
  계획 때 걱정한 "F8 로 켜 둔 앱이 import 하지 않아 확인 불가" 는 해당하지 않았다 — 홈 → 복귀가 import 를 부른다(F31)

⑤ 확인된 오류 뒤 import 성공 — 사용자가 ACC-dut 을 iCloud 로그아웃 → 새로 설치 → 실행(17:41:15)
  16.24 「iCloud 계정을 쓸 수 없다」 → 화면 「iCloud 계정을 확인해 주세요. 지금은 이 기기에만 저장돼요. · 시작하기」, 누르지 않고 5분 넘게 그대로
  → 사용자가 설정에서 계정 B 로그인(Carve 는 뒤에 둠) → 46:39.06 미러링이 계정 없음 → 사용 가능을 받음 → 40.42 설정 → 41.92 import 성공
  → 41.97 「초기 대기 — 오류로 멈춘 뒤 import 가 성공했다. 받은 것으로 결론을 바꾼다」 → 44.49 진입(5행 조회)
  → 앞으로 가져오니 필사 화면에 B 의 지금 내용. 설치 결과 importSucceeded — **기기 확인**(R2-3).
  로그인하는 동안의 캡처는 계정 정보가 찍혀 판독 뒤 지웠다

그 밖의 관측
  - ACC-B 에서 주입 세션인데 1:5 의 새 획이 저장소로 가지 않았다. 시작 전 백업에 앞선 세션의 1:5 초안(한 점짜리 획 · 소유 없음)이
    있었고, 그 초안을 이어 보이는 절이라 새 세션 초안이 그 획을 품고 출처(소유 없음)를 이었다(원 파일은 이어받으며 지움). 설계대로다
    (ACC-1 2차 ⑦ 과 같은 동작). 표본은 1:3 으로 바꿨다
  - 절 롱탭 메뉴는 axe touch(누른 채 1.3초)로 열렸다

판정: 기기로 본 것 — ① 대기 화면과 처음부터 「먼저 시작하기」 · import 성공 뒤 진입 · 다시 실행하면 곧바로 진입,
  ② · ③ (복귀 import 경로), ④ 수정 · 삭제(주입), ⑤. 결함은 찾지 못했다
  기기 미확인(재현 조건 미충족 — 단위 시험으로만 고정): ① 의 20초 · 60초 안내(LaunchWaitRuleTesting), 초기 import 와 겹친 ② · ③
  (ChapterCanvasArrivalTesting). 이 미재현으로 범위 · 문구를 바꾸지 않았다(사용자 결정)
미수행: 실기기(재설치하면 운영 저장소까지 지워져 쓰지 않았다) · 실사용 규모(271행) · 느린 네트워크의 초기 import
```

### SEP-0 — 공개 API 타당성 (2026-09-21)

**환경:** Carve-ACC-dut(iPad Pro 11-inch M5 · iOS 26.5 · 새로 만든 시뮬레이터)에 Debug 빌드(`73c20f73`) 설치, 샌드박스 계정 B 로그인(사용자 조작).
판독은 dut 를 건드리지 않고 **별도 시뮬레이터**(9611DACC)에서 `DomainTest` 로 돌렸다. 하네스는 `Domain/Domain/Tests/StoreRecordMetadataProbeTesting.swift`.

**표본:** 로그인 뒤 앱을 한 번 띄워 **서버 B 의 행 5개를 받은** `Carve.dev.sqlite` 한 벌(본 파일 · `-wal` · `-shm` · 보존 영역)을 그대로 복사했다. 필기는 만들지 않았다.

**절차:** 사본을 다시 임시 자리에 복사 → 앱 스키마로 만든 `NSManagedObjectModel` 로 `NSPersistentCloudKitContainer` 를 만들고
`cloudKitContainerOptions = nil` · `NSReadOnlyPersistentStoreOption` · `shouldMigrateStoreAutomatically = false` 로 연다 → 엔티티마다 행을 세고
`recordID(for:)` 를 부른다 → 판독 전후 파일 지문을 견준다.

**결과**

| 본 것 | 값 |
|---|---|
| 읽기 전용으로 열림 | 예 (마이그레이션 없이 열렸다) |
| `BibleDrawing` 행 | 5 |
| `recordID(for:)` 가 값을 준 행 | **0** |
| 같은 저장소의 `ANSCKRECORDMETADATA` | **5행** — `ZCKRECORDNAME` 있음 · `ZNEEDSUPLOAD` 0 |
| 판독 전후 파일 지문 | 본 파일 · `-wal` 그대로, **`-shm` 만 바뀜** |
| 로그인 전후 `ANSCKMETADATAENTRY` 키 | 4개(버전 · 해시) → **7개**(계정 식별 3개가 더해짐) |

**판정:** **공개 API 는 C14 의 판정에 쓸 수 없다**(F34). 미러링을 켜야만 대응을 돌려주는데, 게이트는 미러링을 켜기 **전**에 판정해야 한다.
그대로 썼다면 모든 행이 「대응 없음」이 되어 **저장소 전체를 분리**했을 것이다. → 사설 판독기(`ANSCKRECORDMETADATA`)를 쓰고,
**검증한 OS · 모델 범위 밖은 「알 수 없음」 → 연결 보류**로 둔다(C14 ②). 판정은 **사본에서** 한다(F35).

**아직 아닌 것:** 미러링이 깨어나지 않았는지는 이 시험만으로 다 보지 못했다(네트워크 · 이벤트는 앱 실행에서 본다).
대응 **없는** 행 표본, V3 실저장소, 삭제 전파(SEP-1 · SEP-2)는 다음이다.

**도구로 배운 것:** 시험 프로세스에는 `xcodebuild` 의 `TEST_RUNNER_…` 환경 변수가 닿지 않았고, 시뮬레이터 안의 `/tmp` 는 **기기의 tmp** 다.
반면 **시험 번들 옆의 호스트 경로는 보인다** — 표본은 `Build/Products/Debug-iphonesimulator/sep0/` 에 놓고 하네스가 스스로 찾게 했다.

### SEP-2 — 대응 없는 행의 업로드와 삭제 전파 (2026-09-21)

**환경:** SEP-0 과 같다(dut · Debug `73c20f73` · 샌드박스 계정 B). 손질은 여분 시뮬레이터에서 `LegacyRowSeparationProbeTesting` 으로, 연결은 dut 에서.
관측 도구가 없어 서버 상태는 먼저 dut 저장소의 `ANSCKEVENT`(0 setup · 1 import · 2 export) · `ANSCKRECORDMETADATA` 로 읽고, 그 뒤 **같은 계정으로 붙인 B 기기가 받는 행**으로 확인했다.

**손질 방법:** 저장소 사본을 `cloudKitContainerOptions = nil` · `NSPersistentHistoryTrackingKey = true` 로 열어 Core Data 로 넣고 지운다 — 1.3.0 이 쓰던
조건(미러링 없음 · 이력 있음)과 같다. 손질한 사본을 dut 의 앱 컨테이너에 되돌려 놓고 앱을 띄운다. **밖에서 바꿔 넣은 저장소는 setup 이 오래 걸린다**
(1라운드 3분 21초 · 2라운드 1분 15초) — 45초 관측은 판정 근거가 못 된다.

| 라운드 | 손질 | 연결 뒤 | 판정 |
|---|---|---|---|
| 1 | 대응 없는 행 2개 삽입(pk 6 · 7, 이력 +1) | export 뒤 대응 5 → 7, 두 행에 CKRecord 이름 | **올라간다**(F36) |
| 2 | pk 6(대응 있음) 삭제 · pk 8 · 9 삽입 · pk 8(대응 없음) 삭제 — 이력 2 → 5 | pk 6 의 고아 대응 사라짐 · 레코드 재수신 없음 · pk 9 대응 생김 · pk 8 흔적 없음 · 이벤트 전부 성공 | **대응 있는 행의 삭제는 전파된다(F37) · 대응 없는 행의 연결 전 삭제는 무해하다(F38)** |

**결론:** C14 의 판정 전제가 **관측됐다.** (가) 행 단위 판정으로 대응 없는 행만 빼면 서버에 아무 영향이 없고, (나) 저장소 단위로 전부 지우면 서버 행까지 지운다.
**서버 확인(22:07, B 기기):** B 가 받은 행은 7개 — 원래 다섯 · `SEP2-ADCD3285` · `SEP2-2CAEA3DF`. **`SEP2-D7684E25`(연결 없이 지운 대응 있는 행)와 `SEP2-84BCE6F6`(연결 전에 지운 대응 없는 행)은 없었다.** 로컬 신호와 서버가 일치한다.
**계정 변경 갈래(22:30, 사용자 조작):** 같은 손질(그린 1:5 를 연결 없이 삭제, 고아 대응 남음) 뒤 dut 계정을 B → A 로 바꿔 연결했다. 미러링이 3초 만에 **로컬 행 · 대응 · 고아 대응을 모두 지우고** A 의 행만 받았으며, **B 서버의 1:5 는 그대로 살아 있었다**(F41). 삭제 전파는 **같은 계정으로 재연결할 때만** 일어난다.
**남은 것(2026-09-22 정정 · 갱신):** 앞 세션이 "없음" 이라 적은 것은 과장이었다. ① 삽입 이력이 없거나 잘린 무대응 행 ② legacy 3종의 대응 ③ 제품의 SwiftData 삭제 경로 ④ 레코드 ID 로 서버 직접 확인은 **같은 날 이 맥에서 관측했다**(§5-1 「C14 관문 시험 G1 ~ G6」, F50 ~ F55). ⑤ 계정 변경 갈래도 같은 날 봤다 — 대응 없는 행 · 앱을 켠 채 전환 · F25 순서(F56 · F57). 오프라인 전환은 시뮬레이터에서 만들 수 없어 남았고, `.none` 열기의 이력 추적 끄기는 필요 없는 것으로 판단했다(F53 · F54).

### SEP-1 — V3 실저장소의 판독과 마이그레이션 (2026-09-21)

**OLD 빌드:** `49f2dc27`(1.3.0 · V3)을 worktree 로 떼어 tuist 4.39.0 · **Xcode 26.3** 으로 빌드했다(코드 수정 없음). Debug 는 CURRENT 와 같은 dev 컨테이너 · `Carve.dev.sqlite` 를 쓴다.

**표본**

| 표본 | 만든 법 | 상태 |
|---|---|---|
| ① 무계정 `v3-noaccount` | 로그인한 적 없는 새 시뮬레이터에 OLD 를 띄워 빈 V3 저장소를 만들고(메타키 4 · 대응 0 · 이력 0), 하네스로 V3 행 3개를 넣었다(`schema: v3`, 이력 켠 채) | V3 · 식별 키 없음 · 대응 0 · 행 3 · 이력 1 |
| ④ 혼합 `v3-mixed` | 계정이 붙어 있던 시뮬레이터에 OLD 를 띄우자 **1.3.0 의 미러링이 서버 행 7개를 받았다**(SEP-2 의 `SEP2-…` 두 행 포함). 거기에 하네스로 V3 행 3개를 더했다 | V3 · 식별 키 있음 · 대응 7 · 행 10 · 이력 2 |

③(미전송만)은 ④ 의 부분집합이라 따로 만들지 않았다. **② `v3-old-drawn`** 은 사용자가 dut 의 OLD 화면에서 1:5 · 1:6 에 그린 것이다 — 좌표 형식 1, 927 · 1192 바이트, OLD 가 몇 초 안에 올려 대응이 생겼다(그래서 「OLD 가 그렸지만 미전송」 상태는 이 방법으로 잡히지 않는다 — 그 조합은 ④ 의 하네스 행으로 봤다). ① · ④ 의 필기 내용은 합성이지만 판정 · 마이그레이션에는 관계없다.

**판정 · 마이그레이션 (`report` → `migrate` → `report`)**

| 표본 | 판정(세 값) | 마이그레이션 뒤 |
|---|---|---|
| ① | 식별 키 없음 · **검증된 대응 없음 3** | 현재 스키마 표 생김 · 기본 키 그대로 3 · 대응 집합 그대로 · 이력 1 → 2 |
| ④ | 식별 키 있음 · **대응 있음 7 · 검증된 대응 없음 3** | 현재 스키마 표 생김 · 기본 키 그대로 10 · 대응 집합 그대로 · 이력 2 → 3 |
| ② | 식별 키 있음 · **대응 있음 12**(사용자가 그린 2행 포함) | 현재 스키마 표 생김 · 기본 키 그대로 12 · 대응 집합 그대로 · 이력 5 → 6 |

**결론:** 검토가 짚은 「실제 1.3.0 은 V3 라 V5→V6 시험은 경로가 다르다」에 답했다 — V3 → V4 → V5 → V6 를 지나도 (엔티티, 기본 키) 대응이 흔들리지 않는다(F39).
C14 의 열기 순서(원시 사본 → CloudKit 없이 마이그레이션 → 사본에서 판정)가 실제 저장소로 성립한다.
**결정 2 의 실제 경로(22:18):** ① 을 로그인된 dut 에 넣고 CURRENT 앱을 띄우자 원시 사본 → V3→V6 → 연결 → **세 행이 계정 B 로 올라갔다**(F40). 업데이트 첫 실행의 자동 귀속이 관측됐다.
**남은 것(2026-09-22 정정):** 계정 변경 갈래(SEP-2 에서 부분 수행), **엔티티 3종 구분(미관측)**, OLD 가 직접 쓴 무계정 · 미전송 행 표본(①③ 은 하네스 행이었다).

### SEP-1 보강 — 판독기 실장 · 음성 시험 (2026-09-22)

**환경:** 이 맥(macOS 26.3 · Xcode 26.3 17C529 · iPad mini (A17 Pro) iOS 26.2 시뮬레이터). 앞 세션(2026-09-21)은 **다른 맥(macOS 27 beta)** 에서 돌았고,
그 세션의 실험 자료(scratchpad 의 표본 17벌 · 스크립트 · 로그)는 이 맥에 없다 — 휘발성 경로였고 그 맥에 남아 있는지는 확인하지 못했다(아래 「막힌 것」).

**한 것:** C14 ② 의 사설 판독기 `LegacyRowLinkageReader` 를 Domain 에 실장했다 — 세 값(대응 있음 · 검증된 대응 없음 · 알 수 없음), 판정은 사본에서(F35),
검증 범위(OS 주 버전 · 스키마 주 버전 · 엔티티)를 값으로 들고 범위 밖은 읽기 전에 「알 수 없음」. 실제 파일로 음성 시험을 붙였다(`LegacyRowLinkageReaderTesting`, 24종):

| 표본 손질 | 판정 |
|---|---|
| 정상 — 전부 대응 · 일부 대응 · 무계정(식별 키 없음 · 대응 0) · 빈 저장소 · 고아 대응(F37) · 미전송(`ZNEEDSUPLOAD`) · V3 마이그레이션 전 | 기대대로(전부 대응 → 모두 대응 있음 · 나머지는 행별로) · 원본 파일 한 벌은 바이트 그대로 |
| 검증 밖 OS(18) · 파일 없음 · 검증 밖 스키마 · **손상**(뒤 절반 덮어씀) | 알 수 없음 |
| `ANSCKRECORDMETADATA` 없음 · **열 이름 다름**(`ZCKRECORDNAME` 개명) · `ANSCKMETADATAENTRY` 없음 · 엔티티 등록과 표 불일치(세 가지) | 알 수 없음 |
| 행의 `Z_ENT` 가 등록값과 다름 · 대응이 모르는 엔티티 ID · 같은 (엔티티, 기본 키) 대응 둘 · **일부 행만 모호**(레코드 이름 없는 항목 하나) | 알 수 없음 |
| **교차 확인 불일치**(식별 키 없이 대응 있음) · 검증 밖 엔티티에 행 또는 대응(`BiblePageDrawing` · `FavoriteVerse`) | 알 수 없음 |
| 「알 수 없음」 결과 | 행 목록을 주지 않는다(부분 결과로 분리하지 못하게) |

**게이트(`LegacySeparationGate`)와 보류:** `LocalStoreLoader` 가 연결 직전에 ② CloudKit 없이 열어 마이그레이션 → ③ 사본 판정 → ④ 대응 없는 행의 **분리본 · 작업 기록**(보존 영역 `separation/`, 다시 읽어 지문 확인) → ⑦ 「모두 대응 있음」 만 `.private`. 그 밖은 `.none` 으로 열고 `connectionHeld` 상태로 들어간다 — 쓰기 차단 사유 `SyncedWriteBlock.connectionHeld`(소유 근거와 독립, 가장 먼저 봄) · 설정의 전체 삭제 두 진입점 차단(D6) · 시작 화면 통과. 1.0.x 저장소는 V1 로 옮기되 연결하지 않고 재실행을 요구한다. **저장소에서 행을 지우는 단계는 연결하지 않았다.** 시험: `LegacySeparationGateTesting` · `LegacySeparationHoldTesting` · `CloudSettingsHoldTesting`.

**남은 것:** 관문 미확인 항목 ① ~ ⑤(SEP-2 「남은 것」 — G1 ~ G5 절차는 §3-3). 실저장소 사본 판독은 F42 · F43.

### C14 게이트 기기 시험 · SEP-6 (2026-09-22)

**환경:** 이 맥(macOS 26.3 · Xcode 26.3). 시험용 시뮬레이터 둘을 새로 만들었다 — `Carve-SEP-noacct`(865D8028… · iPad Pro 11 M4 · iOS 26.2 · **계정 없음**) · `Carve-SEP-ios18`(C3D165F9… · iPad mini A17 Pro · **iOS 18.6** · 계정 없음). 게이트 빌드는 이 브랜치의 Debug. 표본 · 로그 · 앱 사본은 `tools/cloudkit-observe/work/sep/`.

**① 1.3.0 무계정 → 2.0.0 업데이트 경로(실제 앱):** 무계정 기기에 OLD 1.3.0(`49f2dc27`)을 깔아 띄우자 V3 저장소가 생겼다(미러링 표 18개 · 메타데이터 키 4 · 계정 식별 없음 · setup 실패 134400). 하네스로 V3 행 3개(`SEP-NA-BD-0~2`)를 넣고 되돌려 놓은 뒤 게이트 빌드를 **그 위에 설치**해 띄웠다.

| 실행 | 게이트 | 결과 |
|---|---|---|
| 1 | 원시 사본(V3 그대로) → CloudKit 없이 V3 → V6 (437ms) → 「검증된 대응 없음 3」 → 분리본 · 작업 기록(48ms) → **보류** | 앱 프로세스 CloudKit 로그 0줄 · 새 미러링 이벤트 0 · 저장소 V6 · 행 3 그대로 · 필사 화면 진입 |
| 2 | 같은 판정 → **같은 작업 기록**(`a914075f…`) · 원시 사본 하나 그대로(26ms) | 멱등 |
| 3 | `BiblePageDrawing` 행 하나를 더함 → 「알 수 없음」(`unvalidatedEntity`) → 보류 · **새 기록 없음** | 검증 밖 엔티티 보류 |

판독기 v2(검증 엔티티 legacy 3종, F51) 뒤 같은 기기를 다시 띄우자 실행 3 의 저장소를 **「검증된 대응 없음 4」**(`BibleDrawing` 3 + `BiblePageDrawing` 1)로 판정해 새 작업 기록(v2)에 보존하고 보류했다 — 먼저 만든 v1 기록(3행)도 그대로 남는다(2.0.0 은 보존 영역을 자동으로 정리하지 않는다).

설정의 iCloud 화면: "지금은 iCloud 연결이 보류돼 이 기기에만 저장돼요 · 계정과 연결되지 않은 옛 필사 3개 · 사본은 이 기기에 보관 · 다시 실행하면 다시 확인". 목록 항목은 「보류」. **보류 중 시도한 쓰기는 모두 막혔다** — 「모든 필사 데이터 삭제」 → "지금은 iCloud 연결이 보류되어 전체 삭제를 할 수 없어요…"(행 · 보존 파일 그대로), 절 메뉴 「즐겨찾기에 추가」 → "즐겨찾기에 추가하지 않았어요. 지금은 iCloud 연결이 보류되어 이 기기에만 저장돼요"(즐겨찾기 0), 「위젯에 추가」 → "위젯에 담지 않았어요…"(즐겨찾기 0 · 위젯 파일 0). 분리본은 외부 저장 접두(0x01)를 뗀 필기 값 그대로였다.

**② iOS 18.6(검증 밖 OS, 실제 앱):** 새 설치는 **연결**했다(legacy 행 없음 · 미러링 표 없음 → 판독기가 해석할 것이 없다. 계정이 없어 setup 은 134400). dut 기준 표본(대응 있는 5행 · 계정 식별 있음)을 넣고 띄우자 **보류**(`unvalidatedEnvironment(osMajor: 18)`) — CloudKit 0줄 · 행 5 · 대응 5 · 식별 키 그대로 · 분리본 없음. 설정 목록 「보류」 · 상세 "어느 계정의 것인지 확인하지 못했어요". 같은 기기에서 Domain 시험 430개 통과(실행 중인 OS 를 따르는 시험 4개가 검증 밖 갈래를 밟았다).

**③ SEP-6(성능, 시뮬레이터 · 행마다 필기 2,000바이트):** `LegacySeparationPerformanceProbeTesting`(`sep6/plan.json` 이 있을 때만).

| 경로 | 행 | 고치기 전 | 고친 뒤 | 재실행 | 메모리 증가 |
|---|---|---|---|---|---|
| 모두 대응 있음(매 실행) | 1,000 | 59ms | 30ms | 29ms | 0.8MB |
| 모두 대응 있음 | 5,000 | 744ms | 159ms | 120ms | 0.8MB |
| 모두 대응 있음 | 31,102 | **24,410ms** | 990ms | 1,172ms | 11.8MB |
| 모두 대응 없음(분리본 작성) | 1,000 | **11,621ms** | 283ms | 165ms | 6.9MB |
| 모두 대응 없음 | 5,000 | **60,426ms** | 1,200ms | 774ms | 15.6MB |

**이 시험들이 찾아 고친 결함 넷(모두 단위 시험으로 고정):**
1. **새 설치가 영영 연결되지 않았다** — 게이트가 CloudKit 없이 저장소를 먼저 만들어 미러링 표가 없고, 판독기가 「표 없음 → 알 수 없음」 으로 보류했다. → 미러링 표가 하나도 없고 legacy 행도 없으면 연결, 행이 있으면 보류(`mirroringNotAttached`).
2. **검증 밖 OS(iOS 17 · 18)는 새 설치까지 보류됐다** — OS 를 가장 먼저 봤다. → legacy 행을 먼저 세고, 행이 있을 때만 OS · 미러링 표(존재 · 모양) · 대응을 검증한다. 같은 이유로 미러링 표 **모양** 검사도 행이 있을 때로 옮겼다 — 미래 OS 가 표를 바꿔도 행 없는 저장소는 연결한다.
3. **판정이 행 수의 제곱이었다**(대응마다 행 목록 선형 탐색) → 기본 키 색인.
4. **분리본을 행마다 새 연결로 읽고 행마다 장치까지 내려 썼다** → 연결 하나 · 500행 묶음 파일 · 묶음마다 한 번.

게이트는 앱 시작 경로(`ModelContainer.liveValue`)에서 동기로 돈다 — 고치기 전 숫자로는 큰 저장소에서 시작이 수십 초 멈췄을 것이다.

**하지 못한 것(이 기록 시점):** 같은 계정 재연결이 필요한 G1 ~ G4 · 로그인된 기기에서의 게이트 보류 · 게이트 뒤 연결 — 자격 증명이 무효라 멈췄다(F48). → 사용자가 다시 로그인한 뒤 같은 날 모두 수행했다(아래 「C14 관문 시험 G1 ~ G6」).

### C14 관문 시험 G1 ~ G6 — 같은 계정 재연결 · 서버 직접 확인 (2026-09-22)

**환경:** `Carve-ACC-dut`(4419ABC7…) · `Carve-ACC-B`(FD20B387…), 같은 샌드박스 계정(사용자가 재로그인) · dev 컨테이너. 연결은 게이트 없는 Debug(`712bdaac`, P0-3 빌드), 게이트 확인은 이 브랜치의 게이트 빌드. 손질은 `LegacyRowSeparationProbeTesting`(하네스) — 넣기는 이력 추적을 켠 `NSPersistentContainer`, 지우기는 **제품과 같은 SwiftData**(`ModelConfiguration(cloudKitDatabase: .none)` + 마이그레이션 플랜 + `ModelContext.delete`). 서버는 `probe.sh`(레코드 이름 · 유형 · 행 ID · 삭제 흔적)로 읽고 `probe-compare.py` 로 저장소와 맞췄다. 실행은 `work/sep/scripts/sep-gate-rounds.sh`, 기록은 `work/sep/logs/*`.

| 단계 | 손질 | 연결 뒤(서버는 레코드 이름으로) | 관문 |
|---|---|---|---|
| r0 | 없음 | 서버 `CD_BibleDrawing` 12 · 삭제 흔적 5. **앞 세션(다른 맥)의 SEP-2 · SEP-1 행이 그대로 있었다** — F37 의 `EDBC4D34…` 는 삭제 흔적, F38 의 `SEP2-84BCE6F6` 은 레코드도 흔적도 없음, `SEP2-ADCD3285` · `SEP2-2CAEA3DF` 는 레코드, 사용자가 그린 1:5 · 1:6 은 레코드 | ④(F50) |
| r1 | `FavoriteVerse` · `BiblePageDrawing` · `BibleDrawing` 한 행씩(대응 없음 · 이력 있음) | 46초 안에 셋 다 올라감 — 대응 `ZENTITYID` 2(PD) · 4(FV) · 1(BD), 서버 레코드 유형과 행 ID 가 그 행과 같음 | ②(F51) |
| r2 | `BibleDrawing` 두 행 + **이력 표 비움** | 첫 export 가 **134301(history token expired)** → 미러링이 메타데이터를 비우고 다시 동기화 → 두 행 모두 올라감. 기존 15행은 **같은 레코드 이름** · 서버 중복 없음 · 로컬 기본 키는 새로 매겨짐 | ①(F52) |
| r3 | SwiftData 로 지움 — 대응 있는 BD · FV · PD · r2 의 한 행, 넣자마자 지운 대응 없는 행 | 준비본에 삭제 이력(변경 종류 2)과 고아 대응 4 → 연결 뒤 네 행의 레코드가 **서버 삭제 흔적**(세 엔티티 모두), 넣자마자 지운 행은 **레코드도 흔적도 없음** | ③(F53) |
| b-check | 없음(같은 계정 B 기기가 받음) | B 의 13행이 r3 서버 레코드와 모두 맞음 · 지운 행 없음 | ④ |
| gate-hold | **게이트 빌드**, 1.3.0 무계정 V3 표본(대응 없는 3행)을 로그인된 dut 에 첫 실행처럼 | 보류(`unlinkedRowsAwaitSeparation(3)`) · 앱 CloudKit 로그 0줄 · 분리 작업 기록(무계정 기기와 같은 ID) · **서버에 그 행 없음**(조회 정상, 레코드 13) | F55 |
| F56 | **앱을 끈 채 계정을 바꾼 뒤 연결하면, 이전 계정 저장소의 대응 없는 행은 어느 계정 서버로도 가지 않고 로컬에서 사라진다. SwiftData 로 지운 대응 있는 행의 삭제도 이전 계정으로 새지 않는다** — 순서는 setup 134405(계정 변경) → 메타데이터를 비우는 계정 변경 초기화 → 새 계정 setup · import · export 였다(F25 의 "행 삭제 → 새 식별 → 새 행") | 2026-09-22 g5a1 · 두 계정 서버 조회 | F41 을 제품 삭제 경로와 대응 없는 행까지 넓힌다. 분리 도중 계정이 바뀌어도 서버로 새는 것은 없다. 대신 게이트가 없으면 그 행은 **보존되지 않고 사라진다** — 연결 전 보존(④)이 필요하다 |
| F57 | **게이트 빌드는 계정이 바뀐 기기에서도(앱을 끈 채 · 켠 채) 대응 없는 행이 있으면 보류하고, 미러링이 붙지 않아 저장소를 건드리지 않는다** — 행 · 대응 · 계정 식별 · 이벤트 수가 준비본과 같았다 | 2026-09-22 g5a2 · g5b | 보류 중에는 계정 전환이 저장소에 닿지 않는다. 연결한 뒤의 계정 전환은 C14 범위 밖이다(저장소 소유 근거 · 계정 범위의 몫) |
| gate-connect | **게이트 빌드**, 모두 대응 있는 `BibleDrawing` 저장소 | 연결 — CloudKit 없이 열기 27ms · 판정 16ms 뒤 `.private` 로 setup · import · export 성공, 서버의 r1 ~ r3 변경을 받음 | F55 |
| g1b | 대응 없는 두 행 + 이력 비움 + 그중 하나를 SwiftData 로 지움 | 134301 초기화를 지나 남긴 행만 올라감 · **지운 행은 서버에 레코드도 흔적도 없음** | ①(F54) |
| g6 | **분리 흉내:** 1.3.0 무계정 V3 표본의 대응 없는 3행을 연결 전에 SwiftData 로 모두 지움 → 로그인된 dut 에서 첫 연결(게이트 없는 빌드) | setup · import · export 성공 · **서버 레코드 14 · 삭제 흔적 9 그대로 · 그 행의 흔적 없음** · 저장소에는 계정의 행만 | F54 |
| g5a1 | **앱을 끈 채 계정을 바꾼 dut**, 이전 계정 저장소에 대응 없는 두 행 + 대응 있는 행 하나를 SwiftData 로 지움(게이트 없는 빌드) | setup **134405(계정 변경)** → 계정 변경 초기화(메타데이터 비움) → setup · import · export. 대응 없는 두 행은 **로컬에서 사라지고 새 계정 · 이전 계정 서버 어디에도 없음**. 지운 행의 레코드는 **이전 계정 서버에 그대로**(삭제 흔적 없음) | ⑤(F56) |
| g5a2 | 같은 준비본을 **게이트 빌드**로 | 보류(`unlinkedRowsAwaitSeparation(2)`) · CloudKit 0줄 · 저장소 신호(행 · 대응 · 식별 · 이벤트) 준비본과 같음 | ⑤(F57) |
| g5b | 게이트 빌드가 보류 중일 때 **앱을 켠 채** 사용자가 계정을 바꿈 | 앱은 살아 있었고 CloudKit 0줄 · 저장소 신호 그대로 · 편집 환경은 늦게 온 계정 조회 결과를 버림 | ⑤(F57) |

**결론:** C14 판정의 전제("대응 없는 행을 연결 전에 지우면 서버에 흔적이 없다")가 제품 경로 · 이력이 잘린 경우 · 1.3.0 무계정 저장소의 첫 연결에서 성립하고, 대응 있는 행의 삭제는 세 엔티티 모두 서버로 전파된다(저장소 단위 분리가 파괴 경로라는 F37 을 다시 확인). **관문 ① ~ ⑤ 를 시뮬레이터에서 만들 수 있는 범위에서 모두 채웠다.** 남은 것은 오프라인 계정 전환(시뮬레이터에서 만들 수 없음)이다. 게이트 없이 계정이 바뀌면 대응 없는 행은 보존되지 않고 사라진다(g5a1) — 연결 전에 보존하는 게이트의 근거가 하나 더 생겼다.

**함께 본 것:** 이력이 잘리면 게이트가 없는 빌드는 연결 때 미러링을 초기화한다(134301) — 초기화 뒤 로컬 기본 키가 새로 매겨지므로, 분리 작업 기록의 (엔티티, 기본 키) 식별은 **연결 전의 한 실행 안에서만** 뜻이 있다(게이트는 판정 · 보존 · 삭제를 연결 전에 끝낸다).

### 이 수행에서 새로 확인한 사실

| # | 사실 | 근거 | 영향 |
|---|---|---|---|
| F1 | **OLD 가 만든 새 행은 `isPresent` 가 꺼져 있다** — MIG-L0 의 두 행 모두 `ZISPRESENT = 0`. 다만 실사용 데이터에는 **`isPresent = 1` 인 legacy 행이 2개 섞여 있다**(MIG-L1), 즉 "모든 legacy 가 false" 는 아니다. 더 오래된 버전이 켠 것으로 보이며 출처는 확인하지 않았다 | MIG-L0 의 V3 store 조회 + MIG-L1 교차 집계 | 실사용 271행 중 `isPresent = true` 는 **14행뿐**이다. 나머지 257행에서는 `DrawingRepresentativeRule` 이 `isPresent` 분기가 아니라 `updateDate` → 행 키 분기를 탄다. 히스토리가 7행 이상인 절이 24개나 되므로 **이 분기가 실사용의 주 경로다.** `LegacyStoreMigrationTesting` 의 시드를 실측에 맞춰 고쳤다 |
| F2 | **`ZBIBLEPAGEDRAWING` 이 0행이다** — OLD 가 저장할 때마다 `upsertPageDrawing` 을 호출하는데도 한 행도 남지 않았다 | MIG-L0 | D8 실기기 관측(0행)과 일치하므로 기기 한정 현상이 아니다. 단계 A 의 동기화 오류 판정을 오염시킬 수 있어 §3 단계 A 에 주의를 적었다 |
| F3 | **OLD 는 절 로컬 좌표로 저장한다** — `translationX: -rect.minX, y: -rect.minY` | `CombinedCanvasFeature` 저장 경로(코드 확인) | 1.3.0 → 2.0.0 의 좌표 규약이 일치한다. 절대좌표 위험은 1.2.0 이하에서 쓰고 이후 편집되지 않은 행에만 남는다 |
| F4 | **실사용 데이터에 히스토리 행이 깊게 쌓여 있다** — 절당 7행이 24절, 11행·16행짜리 절도 각 1개 | MIG-L1 | 대표 선택 규칙이 예외가 아니라 상시 경로다. 잉크 최대 111 KB · 평균 15.3 KB 이므로 한 절을 합성할 때 읽는 양도 작지 않다 |
| F5 | **같은 번들 ID 의 개발 빌드 ↔ TestFlight 빌드를 오가도 앱 데이터가 유지된다** — Debug 빌드가 깔려 있던 기기에 TestFlight 의 Release 빌드를 덮어 설치했고 `Carve.sqlite` 가 그대로 남았다 | MIG-L1 의 화면 확인 절차 | 단계 A 의 **시간 분할 방식(한 기기에 OLD·NEW 를 번갈아 설치)이 성립할 조건 하나를 확인**한 것이다. 다만 관측은 1회이고 서명 조합도 하나뿐이라 일반화하지 않는다. OLD(개발 서명) ↔ NEW 교체는 따로 확인해야 한다 |
| F6 | **prod store 의 CloudKit 레코드 매핑이 완전하다** — `ANSCKRECORDMETADATA` 272개가 전부 `CKRecordName` 을 갖고 있고, 이는 필사 271 + 즐겨찾기 1 과 일치한다 | MIG-L1 | 로컬 행이 빠짐없이 CKRecord 에 대응돼 있다는 신호다. **업로드 완료의 증명은 아니다** — 서버 조회로 확인해야 하며 단계 A 의 관측 대상이다 |
| F7 | **V5 store 에 OLD 를 덮으면 크래시가 아니라 "조용한 초기화" 다** — `134504` 로 열기에 실패한 뒤 V1 폴백이 **성공**해서 같은 파일이 `DrawingVO` 스키마로 갈아치워진다. 앱은 평소처럼 열리고 필사만 사라진다 | DOWN-L2 | ① 단계 A 의 시간 분할에서 OLD 를 깔 때마다 NEW 의 로컬 데이터가 **파괴된다.** "로컬 저장소 격리" 는 선택이 아니라 강제다. ② 로드맵 §4 가 기록한 **V4 빌드의 `fatalError` 와 다른 결과**다. 폴백 성공 여부가 갈린 것이므로 빌드 조합마다 다시 봐야 한다. ③ 실사용에서도 2.0.0 → 1.3.0 되돌리기가 같은 결과를 낸다 |
| F8 | **실행 중인 앱은 다른 기기의 변경을 재실행 전까지 가져오지 않았다** — 켜 둔 A 는 B 의 레코드를 2분간 가져오지 않았고 재실행 3초 안에 가져왔다. 2.0.0(B · C)도 CK-A4b · CK-A4c · CK-A5 에서 상대의 업로드 뒤 자기 저장까지 가져오지 않았다. 두 앱 모두 푸시 권한(`aps-environment`)이 없다(`Carve.entitlements` · 시뮬레이터 빌드 엔타이틀먼트) | CK-A0 · CK-A4b · CK-A4c · CK-A5 | **푸시 권한 부재가 원인이라는 것은 추정이다** — 권한을 넣은 빌드로 같은 실험을 해야 확정된다(2026-09-17 리뷰 지적). 배포 서명 빌드도 같은지는 미확인. 이 성질 덕분에 온라인 상태에서도 "서로 모르는 편집" 을 만들 수 있었다(CK-A4b · A4c · A5). → **F31(2026-09-21): 홈 → 복귀하면 import 한다** — 이 관측은 앱이 앞에 머무는 동안에 한한다 |
| F9 | **샌드박스 계정으로 시뮬레이터 CloudKit 왕복이 된다. CloudKit 콘솔은 그 계정의 private DB 를 보여 주지 않는다** | CK-A0 · 사용자의 콘솔 시도 | 서버 필드는 조회 도구로 읽는다(관측 도구 표) |
| F10 | **2.0.0 은 1.3.0 행(v1)을 편집하면 같은 레코드를 v3 로 올리고 `rowUUID` 는 발급하지 않는다** — 남은 획의 점은 그대로 두고 획 변환(`ty −38`)을 붙이며 `layoutMetadataData` 를 더한다. 새 절은 새 레코드에 `rowUUID` · `layoutMetadataData` 가 모두 있다 | CK-A2 서버 조회 · 잉크 해석 | **rowUUID 없는 v3 행이 생긴다** — MIG-L1 의 "v3 ↔ rowUUID 1:1" 은 일반 규칙이 아니다. 설계 §8-7 의 legacy 행 원칙(business `id` 로 식별, UUID 소급 발급 철회)과는 일치한다 |
| F11 | **U4 — 1.3.0 이 편집해 올려도 서버의 모르는 필드가 남는다** — 지우개 · 획 추가 뒤 `CD_rowUUID` · `CD_layoutMetadataData` 해시가 그대로였다 | CK-A3 서버 조회 | [호환성 결정](./data-compatibility-decision.md) D6 을 관측 범위에서 갱신했다(§5-2). 행 삭제 · 동시 편집 · Production 은 미관측 |
| F12 | **R28 — 1.3.0 은 v3 행을 레이아웃 보정 없이 그리고, 편집하면 새 획만 자기 좌표로 더한다** — 1.3.0 화면에서 1절은 약 38pt 위로 올라가 위쪽이, 4절은 아래쪽이 잘렸다. 편집 뒤 남은 획의 점 · 변환은 그대로이고, 새 획은 변환 (0, 0) 의 절 로컬 좌표이며, `drawingVersion` 은 3 으로 남는다 | CK-A2 · A3 화면 · 잉크 해석 | 2.0.0 에서 1.3.0 이 더한 획만 1.3.0 화면 기준보다 약 38pt 아래에 놓인다(수치로 추정). **한 행 안에 좌표계가 다른 획이 섞이므로** 복구를 검토할 때 행 단위 판정으로는 부족하다(추정). 38pt 는 이 기기 · 세로 · 기본 본문 설정의 값이다 |
| F13 | ~~1.3.0 의 id 접미사와 `creationDate` 는 필기 시각이 아니라 장을 불러온 시각이다~~ → **정정 (CK-A5):** id 접미사는 `creationDate` 에서 나온다(`49f2dc27` 의 `DrawingSchemaV3` id 계산). CK-A0 에서는 필기 약 1.5분 전 값(A 의 1절 · 3절이 같은 `…1789619079`, 앱 첫 실행 직후)이었지만 CK-A5 에서는 저장 2초 전 값이었다 — 언제 정해지는지는 경로를 확인하지 않았다 | CK-A0 · CK-A5 저장소 · 서버 조회 · 코드 | R27 의 "같은 초" 충돌 조건은 이 시각에 달려 있다. CK-A5 에서 두 기기가 따로 쓴 같은 절은 id 가 달라 **두 행**이 됐다(F17) |
| F14 | **1.3.0 의 저장은 서버에 `CD_BiblePageDrawing` 레코드를 만들지 않았다** — zone 전체 조회에 `CD_BibleDrawing` 만 있었다 | CK-A0~A5 서버 조회 | §3 단계 A 의 BiblePageDrawing 경고는 이번 관측 범위에서 해당이 없었다 |
| F15 | **서로 모르는 편집은 나중에 올린 쪽이 절 필기 전체를 덮어쓴다 — 충돌 오류도 사용자 안내도 없다** — CK-A4b 두 회차 모두 나중 업로드가 오류 없이 성공했고, 먼저 쓴 필기(P3 · Q2)가 서버와 두 기기에서 사라졌다. 획 단위 병합 · 행 중복은 없었다 | CK-A4b 로그 · 서버 조회 · 잉크 해석 | 정책 §4-2 · §5 가 막으려던 유실의 실측 근거다. 켜 둔 앱이 재실행 전까지 가져오지 않아(F8) 두 기기가 서로 모르고 편집하기 쉽다. 1.3.0 ↔ 2.0.0 조합에 이어 **2.0.0 끼리도 두 순서 모두 같았다(CK-A4c).** 1.3.0 끼리는 미시험 |
| F18 | **같은 절의 `layoutMetadataData` 는 기기마다 바이트가 달라질 수 있다** — B · C 가 같은 4절 · 3절을 저장한 메타데이터의 해시가 달랐지만 JSON 키 순서만 다르고 값은 같았다 | CK-A4c 저장소 | 메타데이터가 바뀌었는지는 해시가 아니라 값을 풀어 비교한다. 앞선 해시 비교(CK-A3 · CK-A4b)는 같은 바이트가 그대로 남았는지 본 것이라 영향이 없다 |
| F19 | **1.3.0 은 모르는 레코드 타입을 건너뛴다** — `CD_FavoriteVerse` 를 받자 "Skipping unknown updated record" 로그를 남기고 가져오기를 성공으로 끝냈다. 이후 기존 필사 편집 · 업로드와 그 레코드의 서버 보존에 영향이 없었다 | FAV-P0 | 새 엔티티 분리의 전제 하나를 예비로 확인했다(1회, 관계 없는 엔티티). ~~그 기기를 2.0.0 으로 올렸을 때 건너뛴 레코드를 다시 받는지는 미확인~~ → **ENT-P1 에서 받는 것을 확인했다(F21)** |
| F20 | **1.3.0 의 「모든 필사 데이터 삭제」는 `CD_BibleDrawing` 레코드만 지운다** — 삭제 내보내기에 필사 8건의 ID 만 담겼고, 서버와 2.0.0 기기의 버전 레코드 · 즐겨찾기는 태그 · 내용까지 남았다 | ENT-P1 2부 · `49f2dc27` `iCloudSettingReducer.swift:83` | 새 엔티티는 구버전의 전체 삭제 범위 밖이다(1회). 반대로 2.0.0 의 전체 삭제는 새 엔티티를 직접 지워야 한다(정책 §12-5 C11) |
| F21 | **레코드를 건너뛴 1.3.0 기기를 새 스키마로 올리면 건너뛴 레코드를 받는다** — V3 → V6 마이그레이션 뒤 첫 가져오기에서 버전 6건 · 즐겨찾기 1건이 B 와 같은 내용으로 들어왔다 | ENT-P1 3부 | 업데이트한 기기에서 다른 기기의 버전이 빠지는 문제는 관측되지 않았다. 원리는 로그로 확인하지 못했으므로, 실제 구현 빌드와 실기기 업데이트에서 다시 확인한다 |
| F16 | **1.3.0 은 편집한 레코드를 올릴 때 바꾸지 않은 `drawingVersion` 까지 자기 값으로 다시 쓴다** — B 가 v3 로 올린 2절을 A 가 모른 채 덮자 서버 `drawingVersion` 이 3 → 1 이 됐다. 모르는 `layoutMetadataData` 는 남아 "v1 + 낡은 메타데이터" 행이 됐다. 이번 화면은 양쪽 모두 제자리였다 | CK-A4b 2회차 서버 조회 | F11(U4)과 같은 원리 — 아는 필드는 덮고 모르는 필드는 남긴다. 2.0.0 이 이 행을 다시 편집할 때 낡은 메타데이터를 어떻게 다루는지는 미확인 |
| F17 | **R27 — 빈 절에 두 기기가 따로 쓰면 행이 둘이 되고, 두 기기 모두 2.0.0 의 행만 보여 준다** — A(1.3.0)의 P5 는 서버와 양쪽 저장소에 남았지만 두 화면 모두에서 보이지 않았다. 자동 병합 · 정리는 없었다 | CK-A5 | 1.3.0 사용자에게는 방금 쓴 필기가 사라진 것처럼 보인다. Q5 가 isPresent 1 이고 updateDate 도 늦어 어느 대표 규칙으로 골랐는지 가리지 못했다 — 반대 순서가 남았다 |
| F22 | **V1 전용 컨테이너(`Schema([DrawingVO])`)에서는 필사 조회가 비고, 저장은 오류 없이 끝나지만 다시 읽히지 않는다** — 크래시도 오류 안내도 없어 "저장됨" 처럼 보인다 | MIG-F1 단위 테스트(iOS 26.2 시뮬레이터) | 수정 전 V1 폴백 상태의 편집 진입은 **조용한 저장 소실**이었다. 조사 때 미확인이던 "크래시 · 오류 · 조용한 실패 중 무엇인가" 의 답이다. 화면의 저장 표시는 필기를 넣지 않아 보지 않았다 |
| F23 | **저장소 메타데이터의 모델 해시(`NSStoreModelVersionHashes`)에는 앱 엔티티만 담긴다** — persistent history(`CHANGE` 등)와 CloudKit 미러링(`NSCK…`) 엔티티는 빠진다 | MIG-F1 — 단위 테스트 저장소와, 수정 전 앱이 CloudKit 설정으로 연 시뮬레이터 저장소(`ANSCK…` 테이블 생성)의 `Z_METADATA` | 저장소를 **열지 않고** 알려진 스키마(V1~V5)와 대조할 수 있다. 계정이 로그인된 실사용 저장소는 대조하지 않았다 |
| F24 | **V1 폴백의 본래 경로는 동작한다** — 버전 없는 1.0.x 저장소(1.0.7 모델)는 `134504` → V1 폴백으로 행이 남고, 재실행하면 V1 → V5 로 옮겨져 필기가 보인다. 1.1.0 이전에는 저장소 스키마가 `Schema([DrawingVO.self])` 하나뿐이었다 | MIG-F1 단위 테스트 · 시뮬레이터 앱(수정 전 · 후) · 릴리스 커밋(1.0.0 · 1.0.2 ~ 1.0.7)과 컨테이너 생성 파일 이력의 코드 확인 | 폴백을 없애지 않고 **엔티티가 `DrawingVO` 하나뿐이고 V1 과 해시가 다른 저장소**로 좁혔다. 1.0.x 설치가 실제로 남아 있는지는 모른다 |
| F25 | **미러링은 계정이 바뀐 것을 알면 새 계정의 행을 가져오기 전에 동기화 행과 CloudKit 메타데이터를 모두 지운다** — 설정 단계의 사용자 레코드 조회에서 식별이 바뀐 것을 보고(`ResetSyncReason 3`) 다섯 엔티티의 행과 `NSCK…` 메타데이터를 지웠다. 앱을 끈 채 바꾸면 실행 0.43초 뒤(시작 화면이 가림), 켠 채 바꾸면 복귀 0.4초 뒤였다. 식별 값이 든 `NSCKMetadataEntry` 는 삭제 목록에 없고, 시나리오 1 에서 1초 안에 새 계정으로 바뀌어 있었다 | ACC-1 1차 로그 · 관측기 | 후보 A 의 관측 순서는 "옛 행 + 옛 식별 → 행 삭제 → 새 식별 → 새 행" 이었다. **행 삭제와 식별 변경은 한 단계가 아니다** — 그 사이에 앱이 쓴 행은 옛 식별로 보이지만 새 계정으로 올라갈 수 있다(추정). 삭제에 사용자 레코드 조회가 필요하므로 오프라인 전환에서는 옛 행이 남아 보일 것으로 추정한다. 미전송 편집도 이때 지워질 것으로 보인다(둘 다 미시험). **다른 방법으로 따로 재현하지 않고, SEP-2(삭제 전파, §3-3)에 묶어서 본다**(사용자 결정 2026-09-21) — 연결 없이 연 저장소에서 행을 지우고 다시 연결할 때 미러링이 행 삭제 · 계정 식별을 어떤 순서로 다루는지 같은 자리에서 본다. 지금은 2.0.0 이 저장소에 쓰지 않아(②-2 · 결정 1) 그 틈에 올라갈 행이 없다 |
| F26 | **실행 중 계정이 바뀌면 열린 장이 빈 채로 남는다** — 앱은 A 를 확인한 즉시(47.239) 세션을 새로 열어 다시 읽었고, 그때 저장소는 B 행이 지워지는 중이거나 직후였다. 2초 뒤 A 의 필기 · 즐겨찾기가 들어왔지만 열린 장은 다시 읽지 않았다(3분 38초까지 확인). 열린 장은 장을 불러올 때와 편집 환경이 바뀔 때만 다시 읽는다 | ACC-1 시나리오 2 화면 · 관측기 · `ChapterCanvasFeature` | 사용자가 본 기준(부모)이 그 계정의 실제 데이터와 다르다. F8(켜 둔 앱은 가져오지 않음)과 달리 **저장소는 받았고 화면만 낡았다** |
| F27 | **낡은 화면에 쓰면 그 계정의 기존 필기가 가려진다** — 빈 1:1 에 쓴 체크가 새 행(present 1)으로 A 서버에 올라갔고, 재실행 뒤 대표 규칙(present 중 최신)이 체크를 골라 지그재그를 가렸다. 지그재그는 저장소 · 서버에 남아 있다 | ACC-1 시나리오 2 ④ 서버 조회 · 화면 | F17(R27)과 같은 "가려진 필기" 가 계정 전환으로도 생긴다. 귀속 근거가 없는 세션을 초안 전용으로 막으면(②) 이 쓰기가 원본에 닿지 않고, 버전(③)에서는 빈 기준을 부모로 한 새 버전이 기존 버전과 나란한 갈래로 남는다 |
| F28 | **두 전환 모두 계정 간 유출은 없었다 — 다만 앱의 A 확인과 미러링의 행 삭제가 15ms 차이였다** — 양쪽 서버에 상대 계정의 행이 없었다. 확인(47.239)이 삭제(47.254)보다 앞섰고, 세션을 새로 여는 다시 읽기는 확인 직후 시작된다 | 서버 조회 2회 · 범위 파일 수정 시각 · 로그 | 다시 읽기가 삭제보다 먼저 끝나면 A 세션이 B 의 고리를 보여 주고, 그 위에 쓴 필기가 B 의 획을 담아 A 서버로 올라갈 수 있다(추정, 미재현). 소유 근거는 **데이터와 같은 읽기 시점**에서 얻어야 하고, 쓸 때 "확인 계정 = 저장소 식별 = 세션 근거" 를 다시 봐야 한다 |
| F29 | **계정 전환은 전송 전의 필기를 지우고, 원래 계정으로 돌아와도 되살리지 않는다** — 저장 뒤 전송 전에 앱을 끝낸 W 행이, 앱을 끈 채 A→B 로 바꾸고 실행하자 2초 안에 다른 행과 함께 지워졌다. 지우기 전 전송은 없었고 B 서버에도 없다. 다시 A 로 돌아오자 전송된 세 행만 돌아왔고 W 는 로컬 · A 서버 어디에도 없다 | ACC-1 시나리오 3 로그 · 스냅숏 · 서버 조회 2회 | **로컬 저장 완료는 보존이 아니다.** 전송이 확인되기 전의 필기는 미러링 저장소 밖에 사본이 있어야 계정 전환을 견딘다. 저장 뒤 전송까지 0.7초(한가할 때) ~ 7초(앞선 요청 뒤)였고, 오프라인이면 더 길다. → **결정(9차 리뷰):** 전송 확인을 기다리지도(export 이벤트는 레코드 · revision 목록을 주지 않는다), 로컬 저장으로 지우지도 않는다 — ② 는 마지막 로컬 사본을 남기고 ③ 이 복구 사본 → 버전 로컬 커밋 → 초안 정리 순서로 정리한다(정책 §12-3). 확인은 2차(§3-2 ① · ②) |
| F30 | **로그아웃하면 미러링은 행과 계정 식별을 지우고, 그 뒤 로컬에 쓴 필기는 다음에 로그인한 계정으로 올린다** — A 로그아웃 뒤 실행에서 모든 행과 식별 항목이 지워졌다("AccountLogout"). 그 상태에서 쓴 삼각형은 로컬에만 있다가, B 로 로그인하자 초기화 없이 B 서버로 올라갔다 | ACC-1 시나리오 4 로그 · 서버 조회 | 정책의 "로그인 안 함 상태의 필기는 자동 귀속하지 않는다" 를 미러링이 스스로 어긴다 — **계정이 없을 때의 필기는 미러링 저장소에 넣으면 안 된다**(초안 · 로컬 보존에만). 로그아웃 때의 삭제는 전송 전 필기도 지울 것이다(F29 와 같은 경로, 추정). 식별 항목이 없는 저장소의 행은 다음 계정이 가져가므로, 1.3.0 에서 계정 없이 쓴 행도 처음 로그인한 계정으로 올라갈 것이다(추정, 미시험 — 정책 열린 질문의 사용자 결정 항목). → ②-2 보완에서 **캔버스의 로그인하지 않은 세션도 저장소에 쓰지 않게** 고쳤다 — 규칙상 이 기기 전용 문맥으로 유효해 저장소에 쓰고 있었다. 즐겨찾기 · 위젯 · N-Canvas 는 아직 쓴다(사용자 결정 대기) |
| F31 | **켜 둔 앱도 홈 → 복귀하면 import 한다** — 복귀 2~3초 뒤 import 요청이 끝났고(다른 기기의 변경이 있으면 `madeChanges: 1`), 이어 자동 import 가 한 번 더 예약됐다(`checkAndScheduleImportIfNecessary…`, Delay 0). 다섯 번 복귀해 다섯 번 모두 그랬다 | P0-3 기기 확인 ② · ③ · ④ · CoreData 로그 | F8(켜 둔 앱은 재실행 전까지 가져오지 않았다)은 **앱이 앞에 머무는 동안**의 관측이다. 복귀가 import 를 부르므로 늦은 도착의 반영(P0-3)을 푸시 없이 기기에서 볼 수 있었다. 앞에 머무는 동안의 원격 변경은 여전히 푸시가 있어야 받는다(F8) |
| F32 | **새로 깐 앱의 초기 import 는 서버 3행에서 실행 약 2.1~2.2초에 끝났다** — 대기 화면 · 「먼저 시작하기」 는 실행 1.0~1.3초에 뜬다(대기 방식 판정 뒤). 뜨자마자 눌러도 장 레이아웃 완성이 import 완료와 0.2초 안팎으로 겹쳤다 | P0-3 기기 확인 Run 1~6 | 작은 표본 · 빠른 네트워크에서는 "먼저 시작 → 필기 → 초기 import" 순서와 20초 · 60초 안내를 기기에서 만들 수 없다(재현 조건 미충족 — 단위 시험으로 고정). 실사용 규모(271행) · 느린 네트워크의 시간은 재지 않았다 |
| F33 | **계정이 붙으면 저장소 메타데이터에 계정 식별 키가 생긴다** — 로그인 전에는 `PFCloudKitMetadata…` 버전 · 해시 키 4개뿐이고, 로그인 뒤 앱을 띄우자 `NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey` · `…CheckedCKIdentityDefaultsKey` · `…LastHistoryTokenKey` 3개가 더해졌다(`ANSCKMETADATAENTRY`). 값은 읽지 않았다 | SEP-0 수행(§5-1) | F25 · F30 이 추정으로 쓰던 「저장소의 계정 식별 항목」의 **실제 키 이름**이다. C14 ② 의 교차 확인 신호가 여기 있다 |
| F34 | **행별 대응은 `ANSCKRECORDMETADATA` 에 있고, 공개 API 로는 읽히지 않는다** — 서버에서 내려온 `BibleDrawing` 5행은 그 표에 `ZENTITYID` · `ZENTITYPK` · `ZCKRECORDNAME`(있음) · `ZNEEDSUPLOAD`(0) 로 남아 있었다. 같은 저장소를 `cloudKitContainerOptions = nil` 로 연 뒤 `NSPersistentCloudKitContainer.recordID(for:)` 를 부르면 **5행 모두 nil** 이었다 | SEP-0 수행(§5-1) | **공개 API 를 판정에 쓰면 모든 행이 「대응 없음」이 되어 저장소 전체를 분리한다.** C14 의 판독기는 사설 테이블로 가고, 검증한 OS · 모델 범위 밖은 「알 수 없음」 으로 둔다. `ZNEEDSUPLOAD` 로 **대응은 있지만 미전송인 행**을 구분할 수 있다 |
| F35 | **읽기 전용으로 열어도 `-shm` 은 바뀐다** — `NSReadOnlyPersistentStoreOption` 으로 연 뒤 본 파일과 `-wal` 의 SHA-256 은 그대로였고 `-shm` 만 달라졌다. 앱 스키마로 **마이그레이션 없이**(`shouldMigrateStoreAutomatically = false`) 열려 행이 읽혔다 | SEP-0 수행(§5-1) | 판정은 **사본에서** 한다 — 내용은 바뀌지 않지만 원본 파일을 건드리지 않는 쪽을 규칙으로 둔다 |
| F36 | **대응 없는 행은 연결된 계정으로 올라간다** — 이력 추적을 켠 채 미러링 없이 넣은 `BibleDrawing` 2행(대응 없음 · 이력 +1건)을 dut 저장소에 되돌려 놓고 연결하자 setup(21:45:37 시작) → import(21:48:58) → **export(21:49:18)** 뒤 대응이 **5 → 7** 이 되고 두 행에 CKRecord 이름이 붙었다(SEP-2 1라운드). 밖에서 바꿔 넣은 저장소의 setup 은 3분 넘게 걸려 45초 관측으로는 판정할 수 없었다. **서버 확인(B 기기):** B 가 두 행 중 남긴 쪽(`SEP2-ADCD3285`)을 받았다 | SEP-2 수행(§5-1) · `ANSCKEVENT` · `ANSCKRECORDMETADATA` · B 기기 | **결정 2 의 전제 — F30 의 1.3.0 판 — 가 관측됐다.** 미러링은 자기가 모르던 행을 지금 계정으로 올린다. 한계: ① 이력 트랜잭션이 남아 있는 행으로만 봤다 ② 이미 계정 식별 키가 있던 저장소였다 ③ 2.0.0 스키마(V6) 저장소다 — 1.3.0 V3 무계정 저장소(식별 없음 · 오래된 이력)는 SEP-1 에서 따로 본다 |
| F37 | **연결 없이 지운 「대응 있는 행」의 삭제는 재연결 때 서버로 전파된다** — 이력 추적을 켠 채 `.none` 으로 열어 pk 6(1라운드에서 올라간 `SEP2-D7684E25`, 대응 있음)을 지우자 행은 사라지고 대응만 남았다(고아). 되돌려 놓고 연결하니 setup(21:54:25 ~ 21:55:40) → import → **export(21:56:07 ~ 08)** 뒤 **그 고아 대응이 사라졌고**, 그 레코드(`EDBC4D34…`)는 4분 안에 다시 내려오지 않았다. 다른 행 · 대응은 그대로였다. **서버 확인(B 기기, 22:07):** 같은 계정으로 붙인 B 가 받은 7행에 이 레코드가 없었다 | SEP-2 2라운드(§5-1) · `ANSCKEVENT` · `ANSCKRECORDMETADATA` · B 기기 | **저장소 단위로 분리(전부 삭제)하면 서버에 있던 행까지 지운다 — D1 (나) 는 데이터 파괴 경로다.** D1 (가)(대응 없는 행만 분리)의 근거. 삭제 전파의 통로는 **persistent history** 다 — `ATRANSACTION` 에 남은 삭제를 export 가 읽었다. **한계(2026-09-22 정정):** 지운 행은 하네스가 넣은 22바이트 합성 행이고 삽입 이력이 방금 생긴 것이다 · 삭제 경로는 `NSPersistentContainer` + 이력 추적 옵션(제품의 SwiftData 경로가 아니다) · 서버는 B 기기 수신 목록으로 봤다(레코드 ID 직접 조회 아님) · `BibleDrawing` 만 |
| F38 | **대응 없는 행을 연결 전에 지우면 서버에 흔적이 없다** — 같은 손질에서 넣고 곧 지운 pk 8(`SEP2-84BCE6F6`, 대응 없음)은 연결 뒤 행도 대응도 이벤트 오류도 없었다. 넣기만 한 pk 9 는 올라갔다(F36 재현). **서버 확인(B 기기):** B 가 받은 7행에 pk 8 은 없고 pk 9(`SEP2-2CAEA3DF`)는 있었다 | SEP-2 2라운드(§5-1) · B 기기 | **C14 게이트가 하는 일 — 대응 없는 행을 연결 전에 빼는 것 — 은 서버에 아무 영향을 주지 않는다.** 이력에 삭제가 남아 있어도 미러링이 모르는 레코드라 export 할 것이 없다. **한계(2026-09-22 정정):** F37 과 같은 합성 행 · 방금 생긴 삽입 이력 · `NSPersistentContainer` 삭제 경로 · B 기기 수신 목록 · `BibleDrawing` 만. **삽입 이력이 없거나 잘린 무대응 행과 제품의 SwiftData 삭제 경로는 미관측** — 관문 미확인 항목 ① · ③ |
| F39 | **V3 → V6 마이그레이션은 기본 키와 미러링 대응을 그대로 둔다** — 1.3.0(V3) 저장소 세 벌(무계정 3행 · 계정 있는 혼합 10행 = 대응 7 + 없음 3 · **사용자가 OLD 화면에서 그린 2행을 포함한 12행**)을 앱의 마이그레이션 플랜으로 **CloudKit 없이** 열자 `VerseDrawingVersion` 표가 생기고, `BibleDrawing` 의 (Z_PK, id) 가 전부 같은 자리에 남았으며(옮겨짐 · 사라짐 0), `ANSCKRECORDMETADATA` 의 (엔티티, Z_PK) 집합도 같았다. 마이그레이션 자체가 이력 1건을 남긴다 | SEP-1 수행(§5-1) | C14 게이트의 열기 순서(원시 사본 → `.none` 으로 열어 마이그레이션 → 판정)가 성립한다. 세 값 판정은 표본마다 기대대로였다 — 무계정: 식별 키 없음 · 검증된 대응 없음 3, 혼합: 대응 있음 7 · 검증된 대응 없음 3. **한계(2026-09-22 정정):** `BibleDrawing` 만 — 어느 표본에도 `BiblePageDrawing` · `FavoriteVerse` 행이 없어 **엔티티 3종의 대응 · 기본 키 유지는 미관측**(관문 미확인 항목 ②). 무계정 표본의 행은 하네스가 넣은 것이다 |
| F40 | **1.3.0 이 계정 없이 쓴 저장소를 2.0.0 이 열면 그 행이 처음 로그인된 계정으로 올라간다** — 무계정 V3 표본(행 3 · 식별 키 없음 · 대응 0, OLD 가 만든 저장소에는 setup 실패 이벤트 134400 이 남아 있었다)을 로그인된 dut 에 넣고 CURRENT 앱을 띄우자 원시 사본이 떴고(C3 ①), V3 → V6 로 옮겨졌으며(기본 키 1~3 그대로), setup(22:18:45) → import(22:19:00, 서버 7행) → **export(22:19:01)** 뒤 세 행 모두 대응을 얻었다 | SEP-1 수행(§5-1) · `ANSCKEVENT` · `ANSCKRECORDMETADATA` | **결정 2 가 막으려는 바로 그 일이 2.0.0 의 실제 시작 경로에서 일어난다** — 추정(F30 의 1.3.0 판)이 아니라 관측이다. C14 게이트가 없으면 업데이트 첫 실행에서 자동 귀속된다. 한계: 행의 필기 내용은 하네스가 넣은 것이다(저장소 · 스키마 · 이력 · 이벤트는 OLD 의 것). **경로 차이(2026-09-22 정정):** 무계정 기기에서 만든 V3 저장소를 **로그인된 기기의 컨테이너에 넣고** 보존 영역을 지워 첫 실행처럼 꾸민 것이다 — 그 기기에서 1.3.0 을 쓰다 2.0.0 으로 업데이트하고 로그인하는 실제 순서와 다르다 |
| F41 | **계정을 바꾼 뒤 연결하면 연결 없이 지운 행의 삭제가 이전 계정으로 가지 않는다** — 사용자가 OLD 화면에서 그린 1:5 를 `.none` 으로 지워 고아 대응을 남긴 저장소(행 11 · 대응 12 · 이력 6)에서 계정을 B → A 로 바꾸고 연결하자, setup 실패(134405) → setup → import → export 가 **3초 만에** 끝나며 **로컬 행 · 대응 · 고아 대응이 통째로 지워지고** A 의 행 3개만 남았다(식별 키도 A 로). 그 뒤 B 기기를 올리니 **1:5 가 927바이트로 살아 있었다**(B 의 행 12개) | SEP-2 계정 변경 갈래(§5-1) · `ANSCKEVENT` · B 기기 | **삭제 전파는 같은 계정으로 재연결할 때만이다**(F37 과 대비). C14 에 두 가지를 못 박는다 — ① 분리 도중 계정이 바뀌어도 이전 계정 서버로 삭제가 새지 않는다 ② **계정이 바뀌면 로컬 저장소가 3초 만에 비워지므로** 분리본 · 초안은 반드시 비동기화 보존 영역에 있어야 하고, 조건부 연결 동의는 계정에 묶여 무효가 되어야 한다. **한계(2026-09-22 정정):** B → A **한 방향** · **앱을 끈 채** 전환한 한 가지 타이밍 · 지운 것은 **대응 있는 행**뿐 — 대응 없는 행의 계정 변경 삭제 · 앱을 켠 채 전환 · 오프라인 전환 · `.none` 열기에서 이력 추적 끄기 · F25 의 순서는 미관측 |
| F42 | **`FavoriteVerse` 의 대응도 그 저장소의 `Z_ENT` 로 적힌다 — 스파이크 저장소 사본 1행에서만 봤다** — 이 맥의 `Carve-CK-A-old`(스파이크 빌드 `2c124cb3` 가 쓰던 저장소, 엔티티 등록 `BibleDrawing` 1 · `BiblePageDrawing` 2 · `FavoriteVerse` 3 · `VerseDrawingVersion` 4) 사본의 `ANSCKRECORDMETADATA` 에 `ZENTITYID` 3 이 1건(`FavoriteVerse` 1행 · 레코드 이름 있음 · 업로드 대기 0), 4 가 6건(`VerseDrawingVersion` 6행) 있었다. `BiblePageDrawing` 은 어느 저장소에도 행 · 대응이 없다 | 2026-09-22 저장소 사본 읽기(읽기 전용 SQLite, 값은 키 이름만) | 판독기의 「`ZENTITYID` = 그 저장소의 `Z_ENT`」 가정을 `BibleDrawing` 밖에서도 뒷받침하는 **첫 관측**이지만, 현재 V6 배치(`FavoriteVerse` 가 4)에서 미러링이 만든 대응은 아직 못 봤고 표본이 1행이다 — **검증 집합(`validatedEntities`)에 넣지 않았다.** V6 저장소에서 `FavoriteVerse` · `BiblePageDrawing` 행을 올려 대응이 생기는 것을 본 뒤 넣는다(관문 미확인 항목 ②) |
| F43 | **이 맥의 실제 미러링 저장소 두 벌은 판독기가 「모두 대응 있음」 으로 읽고, 검증 밖 모델은 읽기 전에 보류한다** — `Carve-ACC-dut`(4419ABC7…) · `Carve-ACC-B`(FD20B387…) 의 `Carve.dev.sqlite` 사본(각각 `BibleDrawing` 5행 · 대응 5 · 계정 식별 키 있음 · V6)은 대응 있음 5 · 검증된 대응 없음 0 · 고아 0. 스파이크 저장소(마이그레이션 플랜에 없는 모델) 와 `Carve-Migration-Test` 의 V5 저장소는 각각 `unvalidatedModel("unknown")` · `unvalidatedModel("known(5.0.0)")` 로 「알 수 없음」 | 2026-09-22 `LegacyRowLinkageProbeTesting`(`sep3/` 손) 보고 | 판독기의 정상 경로가 실제 저장소에서 성립하고, **정상 표본이 아닌 것은 실제로 보류된다.** 계정 변경 · 재설치 뒤의 저장소는 아직 안 봤다 |
| F44 | **1.3.0 은 계정이 없어도 저장소에 미러링 표를 만들고, 2.0.0 게이트가 CloudKit 없이 처음 만든 저장소에는 미러링 표가 없다** — 무계정 기기의 OLD 가 만든 V3 저장소에는 `ANSCK…` 표 18개 · 메타데이터 키 4 · setup 실패 이벤트(134400)가 있었다. 저장소가 없던 기기에서 게이트가 먼저 만든 저장소는 표가 없었다(「미러링 표 없음」) | 2026-09-22 무계정 · iOS 18.6 기기 | 「미러링 표 없음」 은 **붙은 적 없는 저장소**의 신호다. legacy 행이 없으면 연결, 있으면 관측한 적 없는 모양이라 보류한다(C14 ②) |
| F45 | **게이트는 1.3.0 무계정 저장소를 실제 업데이트 경로에서 보류하고 분리본 · 작업 기록을 남긴다** — 원시 사본 → V3 → V6 → 「검증된 대응 없음 3」 → 분리본 · 기록 → 보류, CloudKit 로그 0줄. 두 번째 실행은 같은 기록을 썼고, `BiblePageDrawing` 행을 더하자 기록 없이 보류했다. 보류 중 전체 삭제 · 즐겨찾기 · 위젯 추가가 막혔다 | §5-1 「C14 게이트 기기 시험」 ① | **계정이 없는 기기**의 관측이다. 로그인된 기기에서 같은 표본이 서버로 올라가지 않는지(F40 의 반대)는 자격 증명 회복 뒤 `gate-hold` 로 본다 |
| F46 | **검증 밖 OS(iOS 18.6)에서 새 설치는 연결하고, legacy 행이 있는 저장소는 보류한다** — 대응 있는 5행 저장소가 행 · 대응 · 계정 식별 그대로 남았다. 계정이 없는 기기라 연결했다면 F30 처럼 지워졌을 저장소다 | §5-1 ② | iOS 17 · 18 의 기존 사용자는 판독기를 그 OS 에서 검증하기 전까지 **동기화되지 않는다**. 출시 전에 iOS 18 에서 SEP-1 을 다시 해 검증 집합을 넓혀야 한다(계정이 붙은 iOS 18 기기 필요) |
| F47 | **매 실행 전체 검사의 비용은 행 수에 거의 선형이다(고친 뒤)** — 31,102행 모두 대응 1.0초 · 5,000행 모두 없음 1.2초 · 재실행 0.8초, 메모리 증가 16MB 이하(시뮬레이터) | §5-1 ③ | 시작 경로에서 동기로 돈다. 실기기는 더 느릴 수 있다 — 출시 전에 iPad 에서 같은 표를 잰다. 가장 큰 몫은 무결성 검사로 보인다(빠른 통과 · `quick_check` 은 「미루는 것」) |
| F48 | **이 맥을 재부팅하자 시뮬레이터의 샌드박스 계정 자격 증명이 무효가 됐다** — 부팅 2초 뒤부터 `hasValidCredentials=false`, 앱의 미러링 setup 은 134400("계정은 있지만 유효한 자격 증명이 없다")으로 끝났다. 저장소는 바뀌지 않았다(실패한 setup 이벤트 하나만 늘었다) | 2026-09-22 dut 로그(식별 값 제외) | 계정 시험 전에 자격 증명부터 본다 — `sep-gate-rounds.sh preflight`. 설정 앱에서 암호를 다시 넣는 것은 사용자 조작이다 |
| F49 | **CloudKit 없이 옮겨도 미러링 대응은 새 행을 잘못 가리키지 않는다(원본 V1 · V2 · V5)** — V5 → V6 는 `FavoriteVerse` 번호를 3 → 4 로 바꾸고(3 은 `DrawingEraseEpoch` 가 받는다) 대응의 `ZENTITYID` 도 4 로 옮겼다. V2 → V6 는 (엔티티, 기본 키) 대응과 행이 그대로였다. V1 → V6(행을 새로 만드는 사용자 정의 마이그레이션)은 옛 `DrawingVO` 행과 그 대응을 함께 지웠고, 새 행 3개는 「검증된 대응 없음」 이었다 | 2026-09-22 `LegacyEntityNumberingTesting`(대응은 SQL 로 심은 것 — 실제 미러링이 만든 메타데이터는 아니다) | 게이트는 옮긴 뒤의 사본을 판정한다. 원본 모델을 따로 판정에 넣지 않아도 된다 — 낡은 대응이 대응 있음으로 잘못 읽히는 경로가 관측되지 않았다. V1 원본의 행은 분리 대상이 되어 보류된다(연결하면 새 레코드로 올라갈 행이라 판정이 맞다). 실제 미러링 메타데이터로 V5 → V6 를 한 번 더 보는 것은 G3 에 묶는다 |
| F50 | **앞 세션(다른 맥)의 SEP-2 · SEP-1 은 이 맥의 dut · B 와 같은 샌드박스 계정 · dev 컨테이너를 썼고, 서버에서 그 결과를 레코드 이름으로 직접 확인했다** — F37 의 `EDBC4D34…` 는 삭제 흔적, F38 의 `SEP2-84BCE6F6` 은 레코드도 흔적도 없음, F36 · F38 의 `SEP2-ADCD3285` · `SEP2-2CAEA3DF` 는 레코드, F41 의 사용자 필기 1:5 · 1:6 은 레코드 | 2026-09-22 r0 서버 조회 | F36 ~ F38 · F41 의 서버 쪽 근거가 B 기기 수신 목록에서 **레코드 ID 기준**으로 바뀐다(관문 ④) |
| F51 | **V6 저장소에서 미러링이 만든 대응은 `BiblePageDrawing` · `FavoriteVerse` 도 그 엔티티의 `Z_ENT`(2 · 4)로 적힌다** — 대응 없는 한 행씩을 넣고 연결하자 46초 안에 올라갔고, 대응이 가리키는 서버 레코드의 유형(`CD_BiblePageDrawing` · `CD_FavoriteVerse`)과 행 ID 가 그 행과 같았다 | 2026-09-22 r1 · 서버 조회 | 관문 ②. 판독기 v2 가 검증 집합을 legacy 3종으로 넓혔다 — 넓히지 않으면 장 전체 필기 · 즐겨찾기가 있는 저장소는 모두 보류된다 |
| F52 | **이력 표가 비어 있으면 연결 때 export 가 134301(persistent history 토큰 만료)로 실패하고, 미러링이 메타데이터를 비운 뒤 다시 동기화한다 — 대응 없는 행은 삽입 이력이 없어도 올라간다** — 기존 행은 같은 레코드 이름을 유지했고 서버 중복은 없었으며, 로컬 기본 키는 새로 매겨졌다 | 2026-09-22 r2 · 미러링 로그 · 서버 조회 | 관문 ①. 이력은 판정의 축이 될 수 없다 — 대응으로 판정하는 D1 (가)가 맞다. 초기화 뒤 기본 키가 바뀌므로 분리 기록의 (엔티티, 기본 키)는 연결 전 한 실행 안에서만 쓴다 |
| F53 | **제품과 같은 SwiftData 경로(CloudKit 없이)로 지운 삭제는 이력에 남고, 대응 있는 행의 삭제는 같은 계정 재연결 때 서버 삭제 흔적이 된다 — 세 엔티티 모두** — 넣자마자 지운 대응 없는 행은 레코드도 흔적도 없었다 | 2026-09-22 r3 · 서버 조회 | 관문 ③. F37 · F38 이 하네스(`NSPersistentContainer`)만의 성질이 아니다 |
| F54 | **대응 없는 행을 연결 전에 지우면 서버에 흔적이 없다 — 이력이 잘린 행도, 1.3.0 무계정 저장소의 첫 연결에서도** — 1.3.0 무계정 V3 저장소의 대응 없는 3행을 모두 지우고 로그인된 기기에서 연결하자 서버는 레코드 14 · 삭제 흔적 9 그대로였고 저장소에는 그 계정의 행만 남았다 | 2026-09-22 g1b · g6 · 서버 조회 | **파괴적 분리가 서버에 영향을 주지 않는다는 직접 증거**(게이트의 삭제를 하네스로 흉내 냈다). 게이트의 삭제 단계는 아직 연결하지 않았다 |
| F55 | **게이트 빌드는 로그인된 기기에서 1.3.0 무계정 저장소를 보류하고 올리지 않으며, 모두 대응 있는 저장소는 CloudKit 없이 연 뒤 연결해 setup · import · export 가 정상이다** | 2026-09-22 gate-hold · gate-connect | F40 이 게이트 빌드에서는 일어나지 않는다. `.none` → `.private` 두 번 열기가 실제 미러링에서 문제없다 |
| F58 | **macOS 27.2 / Xcode 27.0의 Device Hub에서 1.3.0 필기는 화면에 보이지만 저장 행은 아직 없다** — 사용자는 `Carve-2.0.0-test-legacy`에서 Mac 포인터/트랙패드로 드래그했고, Device Hub 접근성 트리와 화면에는 현재 창세기 1장 1·2절 필기가 보인다. 선택된 시뮬레이터는 iPad Pro 11-inch M5 · iPadOS 26.5, 설치 앱은 1.3.0(1)이다. 다음 장으로 갔다가 돌아온 뒤에도 화면 필기는 남았지만, 입력 전후에 확보한 DB 사본과 live `Carve.dev.sqlite` 모두 무결성 `ok`, `ZBIBLEDRAWING` · `ZBIBLEPAGEDRAWING` 각각 0행이고 WAL은 입력 시각 이후 갱신되지 않았다. `allowFingerDrawing=false`와 OLD `CombinedCanvasView`의 기본 `.pencilOnly`는 확인됐다. 저장 호출은 `StableCanvasView`의 Pencil 접촉 종료 콜백에서만 발생한다(`49f2dc27:CombinedCanvasView.swift`); Device Hub 포인터 입력이 그 콜백을 발생시켰는지는 관측하지 못했으므로 원인을 단정하지 않는다. 앞선 F58 판정은 정정한다 | 2026-09-24 macOS `27.2 (26B5086k)` · Xcode `27.0 (27A266a)` · Device Hub 화면 · 시뮬레이터 `0A956010-5DAA-44BC-BA22-5BAE53FF6D82` · 컨테이너 `7BF1000E-9090-4317-8945-A5FC563D3422` · `devicehub-before-navigation.sqlite` · OLD 코드 `49f2dc27` | 화면에 표시된 필기와 디스크 저장 상태가 불일치한다. 이 원인을 먼저 확인할 때까지 해당 설치에 2.0.0을 덮어 설치하지 않는다. 사용자의 입력을 다시 요구하지 않는다 |
| F59 | **별도 iPadOS 18.6 표본의 1.3.0 → 2.0.0 오프라인 업데이트에서 1절 필기가 유지됐다** — 전용 `iPad (A16)` 시뮬레이터(`D6141A38-61ED-4030-852C-B3C470E4307D`)에 1.3.0(1)을 설치했다. `손가락 필사 허용`을 끈 상태의 첫 포인터 드래그는 저장되지 않았고, 앱 설정에서 켠 뒤 같은 필사 열에 드래그하자 `ZBIBLEDRAWING` 1행이 저장됐다(무결성 `ok`, 장 1·절 1, `ZDRAWINGVERSION=1`, `ZISPRESENT=0`, payload 298B; `ZBIBLEPAGEDRAWING` 0행). 이 DB의 사전 사본을 보존한 뒤 같은 bundle ID의 2.0.0(1)을 Device Hub로 설치했다. 로그인은 하지 않았다. 2.0.0 첫 실행 안내를 넘긴 뒤 창세기 1장의 필기가 화면·접근성 트리에 보였고, 창세기 2장으로 갔다가 1장으로 돌아와도 남았다. 업데이트 뒤 저장소는 무결성 `ok`, 필사 1행·장 전체 필기 0행이며 2.0 스키마의 `ZROWUUID` · `ZLAYOUTMETADATADATA` 열이 생겼다. 1.3.0 전후 `ZLINEDATA` payload 길이와 SHA-256(`07876e8b1910039124914f5c44b9619a90b8ad488a08500bdfa6abc07762c3d6`)은 같았다 | 2026-09-24 macOS `27.2 (26B5086k)` · Device Hub/Xcode `27.0 (27A266a)` · 설치 산출물은 Xcode `26.3 (17C529)` 빌드 · iPadOS `18.6` · 컨테이너 전 `0BF476A9-285F-46E3-ABD0-13AC647AA338`, 후 `EDE319D5-8D70-471E-9B27-280BAC97077B` · `/private/tmp/carve-2.0-live-proof-20260924/legacy-ios18.6-pointer-sample-before-2.0.sqlite` · `legacy-ios18.6-sample-after-2.0.sqlite` | 이 표본에서는 손가락 허용 상태의 Device Hub 포인터 필기가 디스크에 저장되고, 2.0.0의 오프라인 로컬 업데이트 뒤 payload와 화면 표시가 유지됐다. F58의 기존 iPadOS 26.5 설치에서 보인 무행 필기 원인은 별개로 미확인이다. 실제 iCloud 로그인·CloudKit 전송·계정 ownership proof, Xcode 27 빌드 검증으로 확대 해석하지 않는다 |

| F60 | **초기 F60 명령에서 앱 빌드가 XCFramework 서명 확인 단계에서 멈췄다고 기록됐다** — pinned Tuist 4.208.0 상태에서 `xcodebuild build -project App/CarveApp/CarveApp.xcodeproj -scheme CarveApp -destination 'generic/platform=iOS Simulator'`가 `ProcessXCFramework` 단계의 기존 Google/Firebase 계열 XCFramework 서명 검증 오류로 실패했다고 관측했다. 이 명령에서는 Swift 소스 컴파일 전이었다. 당시 CoreSimulatorService 조회도 실패했으나 기본 Xcode 27에서 `simctl` 목록 조회는 성공한다. Xcode 26.3 지정 sandbox runtime 조회는 실패했고, 권한을 높인 read-only 재조회는 성공했다 | 2026-09-24 `xcode-select=/Applications/Xcode.app/Contents/Developer` · Xcode `27.0 (27A266a)` · Tuist `4.208.0` · generic iOS Simulator destination | 이 초기 관측은 재현되지 않았다. Tuist workspace 갱신 후 다섯 `ProcessXCFramework` 작업과 앱·Domain 컴파일은 통과했다. 후속 iPadOS 26.2 전체 회귀는 통과했고 27.0 전체 회귀는 5건 실패했다(아래 § Xcode 27 기록). 서명·의존성·build setting을 바꾸어 우회하지 않았다. |

F1·F2 는 코드 검토만으로는 나오지 않았고 실제로 돌려 봐야 보였다.

### 막힌 것 (기록)

시뮬레이터 합성 터치(`touch_path`)로 OLD 캔버스에 필기하지 못했다. 컨테이너 plist 직접 수정 · 시트 토글 탭 · `simctl spawn defaults write` · `drawingPolicy` 를 `.anyInput` 으로 바꾼 재빌드까지 네 가지 자동 경로는 획을 만들지 못했다. 좌표 문제가 아님은 스크린샷 픽셀 분석으로 확인했다(밑줄 y·필사 영역 x 대조). **2026-09-24 별도 iOS 18.6 표본에서는 Device Hub 포인터 드래그가 앱의 `손가락 필사 허용`을 켠 뒤 실제 저장 행을 만들었다(F59).** 이는 기존 iPadOS 26.5 화면 필기의 원인을 설명하지 않으며 Apple Pencil 입력 의미를 대신하지 않는다. `touch_path` 자동 경로는 여전히 미해결이고, Pencil 전용 검증은 사람의 실제 Pencil 입력이 필요하다.

**CloudKit 콘솔 — 샌드박스 계정 private DB 접근 거부 (2026-09-17).** 사용자가 CK-A0 의 서버 레코드를 콘솔에서 보려 했으나 샌드박스 계정이라 권한이 없다고 거부됐다. 조회 도구(관측 도구 표)로 대체했다.

**앞 세션 자료는 다른 맥의 기록이다 (2026-09-22 정정).** 2026-09-21 의 SEP-0 ~ SEP-2 는 다른 맥(macOS 27 beta · 베타 시뮬레이터)에서 돌았다. 기록에 나오는 경로(`/Users/leetaek/Carve` · scratchpad 표본 · `~/Carve-old-49f2dc27`)와 시뮬레이터(DDE9B05A… · DB142B76… · F2623D91… · 9611DACC…)는 **그 맥의 것이라 이 맥에는 적용되지 않는다**(사용자 확인). 이 맥의 `Carve-ACC-dut`(4419ABC7…) · `Carve-ACC-B`(FD20B387…)는 이름만 같은 다른 기기다(F43). 이 맥의 표본 · 스크립트는 `tools/cloudkit-observe/work/sep/` 에 둔다.

**자격 증명 무효로 같은 계정 시험이 멈춤 → 해소 (2026-09-22).** 재부팅 뒤 dut · B 의 샌드박스 계정이 유효한 자격 증명을 잃었다(F48). 사용자가 암호를 다시 넣은 뒤 G1 ~ G6 을 모두 돌렸다. 감시가 "감시 시작 뒤" 로그만 보다가, 먼저 유효해진 B 를 놓친 일이 있었다 — `--since` 로 기준 시각을 당겨 해결했다.

**시험 병렬 실행의 흔들림 (2026-09-22).** DomainTest 전체(418)를 돌릴 때 `RawStoreSnapshotTesting.takesSnapshotWithoutTouchingTheStore` 가 한 번 실패했다(사본 바이트가 원본과 다름 — 앞서 닫힌 SwiftData 컨테이너의 늦은 체크포인트로 보인다). 같은 빌드로 다시 돌리자 통과했다. 판독기 · 게이트 시험이 컨테이너를 많이 만들어 병렬 부하가 늘었을 수 있다. 재현되면 그 시험의 사본 비교를 체크포인트 뒤로 옮긴다.

## 6. 다음 세션 인계와 완료 조건

1. 설계 문서와 이 계획, 그리고 §5-1 의 수행 기록을 읽고 현재 작업 트리·다른 작업 변경을 확인한다.
2. **OLD 재현은 확인됐다(PRE-0).** worktree `.claude/worktrees/old-1.3.0` 과 시뮬레이터 `Carve-Migration-Test` 를 그대로 남겨 뒀으므로 다시 세울 필요가 없다. ~~남은 준비는 테스트 계정과 두 번째 클라이언트다.~~ → 3 · 4 로 해결했다(2026-09-17). 부족하면 그 항목은 보류하고 독립적인 순수 규칙 테스트를 진행한다.
3. ✅ **전용 테스트 계정과 폐기 가능한 CloudKit 컨테이너 — 2026-09-17 샌드박스 계정 + dev 컨테이너(§2-1).** 서버 필드는 콘솔 대신 조회 도구로 읽는다(§5-1).
4. ✅ **클라이언트 두 개 — 2026-09-17 시뮬레이터 `Carve-CK-A-old`(`CB2FBB32…`, OLD) · `Carve-CK-B-upgrade`(`F6425E3F…`, CURRENT `2c124cb3`).** 둘 다 iPad mini (A17 Pro) · iOS 26.2 이고 샌드박스 계정에 로그인한 채로 남겨 뒀다. CK-A0 으로 양방향 전송을 확인했다. 오프라인 만들기는 아직 시도하지 않았다. 현재 표본은 창세기 1장 1~4절 4행(CK-A3 끝 상태)이고, B 는 손가락 필기가 켜져 있다.
5. ✅ CK-A1~A3 수행(§5-1). 다음 **CK-A4(충돌)** 는 방법부터 정한다. ① 계획대로 Mac 네트워크 전체를 끊으면 에이전트도 끊기므로, 오프라인 구간(양쪽 편집 · 앱 종료 · 복구)은 사람이 조작하고 에이전트는 복구 뒤 로컬 저장 대조와 재연결 순서 관측을 맡는다(§3 단계 A). ② ✅ F8(켜 둔 앱은 가져오지 않음)을 이용한 온라인 변형 **CK-A4b** 와 R27 **CK-A5** 를 2026-09-17 수행했다(§5-1, F15 · F17) — 둘 다 CK-A4 를 대체하지 않는다. 2.0.0 끼리는 **CK-A4c** 로 수행했다(시뮬레이터 `Carve-CK-C-current`, `08B34470…`, CURRENT `2c124cb3`, 샌드박스 계정 로그인 · 손가락 필기 켬). 남은 것: 오프라인 CK-A4(①), CK-A5 반대 순서. 1.3.0 끼리의 같은 시험은 같은 동작으로 보고 생략했다(2026-09-17 사용자 판단). 모르는 레코드 타입 예비 시험 **FAV-P0** 은 예비 통과(F19). 후보 엔티티 시험 **ENT-P1** 통과(F20 · F21). 다음은 정책 §12-5 의 C3 · C7 · C11 규칙 확정이다. **시뮬레이터 상태가 바뀌었다** — A · B · C 모두 스파이크 빌드(V6)이고 필사 0행 · 버전 6 · 즐겨찾기 1 이다. 1.3.0 이 필요한 시험은 새 시뮬레이터에 OLD 를 깐다. 스파이크 worktree(`.claude/worktrees/spike-version-entity`)는 커밋하지 않은 채 남겨 뒀다. 그 뒤 단계 B 순으로 저장소 분리 방식을 판정한다. **V1 폴백 이후의 CloudKit 거동은 별도 격리 실험으로 분리한다**(F7). **V1 폴백 이후의 CloudKit 거동은 별도 격리 실험으로 분리한다**(F7).
6. 선택한 구조로 초안·버전 저장을 구현하고 단계 C를 통과시킨다. **단계 C 중 계정이 필요 없는 케이스(SAVE-C5 · C6 · C8)와 MIG-F1 · UPD-W1 은 3~5 를 기다리지 않는다.** 구현 순서 ②-2(캔버스 초안)의 합격 시험은 **ACC-1 2차(§3-2)** 다 — DEBUG 소유 주입은 사용자 승인 뒤에 구현한다.
7. 관련 CLI 테스트와 두 클라이언트 실측 결과를 링크하고, 마지막에 전체 회귀와 출시 후보 검증을 수행한다.
8. 단계 D(백업 왕복)는 **2.1 에서** 백업 구현과 함께 수행한다.
9. 시작 화면 정책은 단계 A~C 결과를 반영해 구현·검증한다.

설계 완료는 이 계획의 확정을 뜻한다. **구현 완료·데이터 보전 검증·출시 승인은 별개**다. **§5-1 에 기록이 없는 케이스는 미수행이다.** 수행한 것은 그 형식으로 결과·제한과 함께 남긴다. 다른 세션의 구현을 이번 문서 작업에서 시작하지 않는다.

### iPadOS 17.5 최초 전체 회귀 (2026-09-24, migration 수정 전)

사용자가 iOS 17 runtime을 설치했다고 알려와 목록을 다시 확인했다. Xcode 26.3 (17C529 / Swift 6.2.4), Tuist 4.208.0, iPad mini (6th generation), iOS 17.5 build 21F79 (UDID `0347221E-08F5-48C9-9F8E-6D7995C25D9F`)로 CLI `xcodebuild test`를 실행했다. `.xcodeproj`가 gitignore 대상이라 `mise x -- tuist generate --no-open` 후 `Carve-Workspace` scheme을 사용했다. 당시 checkout의 미추적 미완성 `Domain/Domain/Sources/SwiftData/LegacyRowCorrespondence.swift`는 검증 명령에서 제외했다. iPhone simulator, Xcode MCP, Device Hub 조작, CloudKit 로그인·실기기 입력은 사용하지 않았다.

최종 전체 회귀는 병렬 테스트를 끈 상태로 수행해 **993 passed · 3 failed · 6 skipped · 4 expected failures (총 1006)**였다. 결과는 `/private/tmp/carve-2-0-0-autotest-20260924-full-final2-ios17.5.xcresult`, 로그는 `/private/tmp/carve-2-0-0-autotest-20260924-full-final2-ios17.5.log`다. 실패 3건은 다음과 같다.

| 실패한 케이스 | 결과 | 해석 |
|---|---|---|
| `DrawingDatabaseTesting/migrationV1toV2()` | `SwiftDataError.loadIssueModelContainer` | V1 versioned store에서 앱 최신 스키마로 staged migration을 열지 못함 |
| `LocalStoreLoadFailureTesting/unversionedStoreKeepsLegacyMigrationPath(_:)` | dynamic case `1.0.0~1.0.3`에서 재실행 시 앱 스키마 open 실패. `1.0.4~1.0.7`은 통과 | 구형 무버전 store의 날짜 필드가 없는 1.0.0 모양을 V1로 옮긴 뒤 최신 앱 스키마로 여는 경로가 실패 |
| `LegacyEntityNumberingTesting/v2ToV6KeepsCorrespondences()` | `SwiftDataError.loadIssueModelContainer` | V2 versioned store의 V6 앱 스키마 staged migration 경로가 실패 |

전체 회귀에서 6건 skip은 실기기 전용 UI 시험 5건과, iOS 18.6·26.2에서만 관측된 잘못된 V1 컨테이너의 no-op 저장 동작 시험 1건이다. 그 no-op 시험은 iOS 17에서 같은 호출이 SwiftData trap을 일으킨 이전 실행을 반영해 OS 조건부 skip으로 바꿨다. 네 건의 expected failure는 프로젝트에 선언된 기존 기대 실패다. 이 skip을 iOS 17 동작 확인으로 세지 않았다.

실패 분석과 수정 과정에서 실행한 추가 검증도 남긴다.

| 실행 | 결과 | xcresult |
|---|---|---|
| 소유 판독기·ownership proof·edit environment·snapshot·release 경로 집중 5 suite | **67/67 통과**, 실패·skip 0 | `/private/tmp/carve-2-0-0-autotest-20260924-focused-ios17.5.xcresult` |
| `CGPoint` anchor hash 충돌 보정과 관련 lasso·reconcile·history wiring·DB actor suite | **27/27 통과** | `/private/tmp/carve-2-0-0-autotest-20260924-focused-final-ios17.5.xcresult` |
| 최초 전체 실행(핵심 iOS 17 호환 수정 전) | 테스트 프로세스가 여러 SIGSEGV로 실패했고 47 failures를 보고했다. 일부 pass 수는 중도 종료 결과라 완결 회귀 수로 쓰지 않는다 | `/private/tmp/carve-2-0-0-autotest-20260924-full-ios17.5.xcresult` |
| CGPoint·SwiftData fixture 수정 뒤 전체 회귀 | 991 통과·6 실패·5 skip·4 expected failure | `/private/tmp/carve-2-0-0-autotest-20260924-full-ios17.5-rerun.xcresult` |
| SwiftData migration 재확인용 4 suite | 35 통과·3 실패. iOS 17.5에서 지원되지 않는 V1-only 호출 시험은 이 시도에서 trap | `/private/tmp/carve-2-0-0-autotest-20260924-swiftdata-retry5-ios17.5.xcresult` |
| conditional skip / 최신 스키마 fixture 적용 후 migration 집중 재검증 | 9 통과·2 실패·1 skip. dynamic migration case 중 `1.0.0~1.0.3` 실패, `1.0.4~1.0.7` 통과 | `/private/tmp/carve-2-0-0-autotest-20260924-migration-recheck2-ios17.5.xcresult` |
| 현재 스키마를 명시적 `Schema(versionedSchema: DrawingSchemaV6.self)`로 열어 migration 재검증 | 9 통과·2 실패·1 skip으로 실패가 그대로 재현됐다. 가설이 개선을 보이지 않아 이 schema 변경은 되돌렸다 | `/private/tmp/carve-2-0-0-autotest-20260924-versioned-schema-recheck-ios17.5.xcresult` |
| migration 집중 재검증 첫 compile | `@Test` trait 인자 순서 컴파일 오류, **테스트 0건 실행**. 순서를 고친 뒤 위 재검증 완료 | `/private/tmp/carve-2-0-0-autotest-20260924-migration-recheck-ios17.5.log` |
| actor insert 격리 및 migration suite 단독 실행 | `actorInsert` 통과, `migrationV1toV2` 실패. 이 결과를 반영해 최종 전체 회귀를 다시 실행 | `/private/tmp/carve-2-0-0-autotest-20260924-failures-isolated-ios17.5.xcresult` |
| 최종 전체 회귀 직전 단일 V2→V6 filter invocation | XCTest 선택 필터가 케이스를 선택하지 않아 **0건 실행**, 결과 `unknown`; 통과 증거로 세지 않음. 해당 케이스는 최종 전체 회귀에서 실패로 확인 | `/private/tmp/carve-2-0-0-autotest-20260924-v2-v6-isolated-ios17.5.xcresult` |
| test-only container 격리 변경 후 전체 회귀, 병렬 실행 끔 | **993 통과·3 실패·6 skip·4 expected failure** | `/private/tmp/carve-2-0-0-autotest-20260924-full-final2-ios17.5.xcresult` |

iOS 17에서 처음 드러난 `Set<CGPoint>` hash crash는 production `AnchorIndex` 키를 좌표 `x/y`로 해시하는 값 타입으로 바꾸고, lasso 테스트 fixture는 정렬·중복 제거 배열을 쓰도록 해 해결했다. `DrawingDatabaseTesting.actorInsert()`는 공유 dependency 컨테이너 대신 테스트 전용 in-memory `ModelContainer`와 actor를 만들어 단독 재검증 및 최종 전체 회귀에서 통과했다. SwiftData batch atomicity 시험에서 관측한 롤백 뒤 외부 저장 Data 잔류는 repository가 metadata와 replace row ID를 먼저 검증해 잘못된 batch를 실제 mutation 전에 거절하도록 보완했으며 관련 focused run에서 통과했다. `CarveDetailHistoryWiringTesting` fixture도 iOS 17에서 `BibleDrawing` 생성 전 모델 컨테이너를 등록하도록 보완했다.

마지막 검사에서 수정한 Swift 파일에 대한 `mise x -- swiftlint lint --quiet --config .swiftlint.yml …`는 종료 코드 0이었다. 출력된 7개 warning은 이번 수정 파일이 아닌 다른 기존 소스·테스트 파일에 있었다. `git diff --check`도 통과했다.

**그 시점의 판정:** iOS 17.5 migration 3건이 실패했고 배포 최소 타깃 iOS 17.0 직접 시험도 하지 않았다. 후속 수정 결과와 현재 판정은 아래 기록을 따른다. 이 최초 결과는 ownership allowlist나 CloudKit 계정 동기화 proof를 의미하지 않는다.

### iPadOS 17.5 migration 후속 검증 (2026-09-24)

최초 전체 회귀에서 발견한 SwiftData migration 실패 3건을 수정하고, 같은 기준 툴체인 Xcode 26.3 (17C529 / Swift 6.2.4)으로 집중 회귀와 전체 회귀를 다시 수행했다. 검증은 iPad simulator와 CLI `xcodebuild test`만 사용했다. 미추적 미완성 `Domain/Domain/Sources/SwiftData/LegacyRowCorrespondence.swift`는 계속 검증 대상에서 제외했다.

실패 원인은 두 갈래였다.

1. V1 `willMigrate`에서 V2 `@Model` 객체를 만들어 정적 배열에 보관했다. iOS 17.5에서는 원본 컨텍스트가 활성화된 동안 목적지 모델이 아직 로드된 컨테이너에 속하지 않는다는 오류가 났다. 원본 단계에서는 스칼라·날짜·데이터 값만 담은 `Sendable` DTO를 만들고, 목적지 컨텍스트가 활성화되는 `didMigrate`에서 V2 모델을 생성하도록 바꿨다.
2. V2 저장소를 V1 custom stage를 포함한 전체 migration plan으로 열면 iOS 17.5에서 Core Data `134504`(unknown model version)가 발생했다. V2 저장소로 재현한 최소 시험은 전체 plan에서 실패했고, V2부터 시작하는 suffix plan에서는 통과했다. `LocalStoreLoader`가 확인된 V2~V6 저장소에 V2→V6 plan을 선택하고, V1·무버전·미확인 저장소에는 기존 전체 plan을 유지하도록 했다. 이 선택은 로더 경로를 거치는 V2→V6 대응 보존·무대응 행 migration 시험으로 확인했다.

| 검증 | 결과 | 산출물 |
|---|---|---|
| 직접 만든 V2 저장소를 V1 포함 전체 plan으로 열기 (원인 재현) | **실패**, iOS 17.5에서 `134504` 확인 | `/private/tmp/carve-2-0-0-v2-minimal-ios17.5.xcresult` |
| 같은 V2 저장소를 V2 시작 suffix plan으로 열기 | **1/1 통과** | `/private/tmp/carve-2-0-0-v2-suffix-ios17.5.xcresult` |
| `DrawingDatabaseTesting/migrationV1toV2` | **1/1 통과** | `/private/tmp/carve-2-0-0-migration-v1-fix-ios17.5.xcresult` |
| 무버전 1.0.0~1.0.3 parameterized migration | **2 dynamic runs 통과** | `/private/tmp/carve-2-0-0-unversioned-v1-fix-ios17.5.xcresult` |
| V1·무버전·V2→V6 대응 보존·V2 무대응 행·V2 suffix·V5→V6를 포함한 집중 migration 회귀 | iOS 17.5·18.6·26.2에서 각각 **6/6 테스트 정의 통과**(동적 parameter 포함 7회 실행), 실패·skip 0 | `/private/tmp/carve-2-0-0-migration-regression-ios17.5.xcresult`, `/private/tmp/carve-2-0-0-migration-regression-ios18.6.xcresult`, `/private/tmp/carve-2-0-0-migration-regression-ios26.2.xcresult` |
| iPadOS 17.5 `Carve-Workspace` 전체 회귀 | **998 통과 · 0 실패 · 6 skip · 4 expected failure (총 1008)** | `/private/tmp/carve-2-0-0-full-after-migration-fix-ios17.5.xcresult`; 로그 `/private/tmp/carve-2-0-0-full-after-migration-fix-ios17.5.log` |

전체 회귀의 6 skip은 실기기 전용 UI 시험 5개와 iOS 18·26에서만 관측한 V1-only no-op 시험 1개다. 네 expected failure는 기존 테스트 선언이다. 이 기록은 iOS 17.5에서 확인한 로컬 migration 결과이며 iOS 17.0, 실기기 동작, 소유 proof나 CloudKit 왕복을 대신하지 않는다. 최신 strict-profile의 live CloudKit proof, iOS 18 migration marker 의미와 계정 왕복, 로그인 상태 1.3.0 업데이트 경로, iOS 17.0 및 iOS 19~25 profile은 여전히 확인되지 않아 출시 판정은 **NO-GO**다. 미추적 미완성 파일을 포함한 시험도 별도 재검증해야 한다.

### Xcode 27.0 F60 후속 재현·서명 진단 (2026-09-24)

**환경 확인:** macOS `27.2 (26B5086k)`, `xcode-select -p` `/Applications/Xcode.app/Contents/Developer`, Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`. 확인에 사용한 명령은 `xcode-select -p`, `xcodebuild -version`, `swift --version`, `mise x -- tuist version`, `xcrun simctl list runtimes`, `xcrun simctl list devices available`이다. 두 simctl 조회는 성공했다. iPad runtime은 17.5 (`21F79`), 18.6 (`22G86`), 26.2 (`23C54`), 26.4 (`23E244`), 26.5 (`23F77`), 27.0 (`24A5370g`, `24A434`)였다. iPad mini (A17 Pro) iPadOS 18.6 simulator는 UDID `7E95B700-3976-42D7-BF85-BCAF028B7605`로 목록에서 확인됐다. 첫 시도 당시 `CarveApp.xcodeproj`와 `Carve.xcworkspace`는 이미 있어 생성하지 않았다. 이후 workspace 파일(9/12)이 앱 프로젝트(9/24)보다 오래됐고 `xcodebuild -list -workspace`가 인식 오류를 내어, 생성물 복사본을 보존한 뒤 아래 기록처럼 `mise x -- tuist generate --no-open`으로 전체 그래프를 갱신했다.

**빌드 재실행:**

| 실행 | 결과 | 전체 로그 / 종료 결과 |
|---|---|---|
| `xcodebuild build -project App/CarveApp/CarveApp.xcodeproj -scheme CarveApp -configuration Debug -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924/DerivedData` (기본 샌드박스) | CoreSimulatorService 연결 오류로 destination 해석 전에 실패, 종료 코드 **70**. 서명 단계 미도달 | 로그 `/private/tmp/carve-2.0.0-xcode27-f60-20260924/build.log`, 종료 `/private/tmp/carve-2.0.0-xcode27-f60-20260924/build.exit`; 자동 생성 result bundle `/var/folders/83/7jccsyy179s48jt_6w4c1cb40000gn/T/ResultBundle_2026-24-09_21-18-0024.xcresult` |
| `xcodebuild build -project App/CarveApp/CarveApp.xcodeproj -scheme CarveApp -configuration Debug -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-escalated/DerivedData` (CoreSimulator 서비스 접근 오류 뒤 재실행) | `ProcessXCFramework` 작업과 Swift 컴파일이 시작됐으나 TCA `ComposableArchitectureMacros`의 `SwiftDiagnostics`, `SwiftOperators`, `SwiftSyntax`, `SwiftSyntaxBuilder`, `SwiftSyntaxMacros`, `SwiftSyntaxMacroExpansion`, `SwiftCompilerPlugin` 모듈을 해석하지 못해 종료 코드 **65**. 앱 소스 컴파일·테스트 미도달 | 전체 로그 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-escalated/build.log`, 종료 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-escalated/build.exit` |
| `xcodebuild build -project App/CarveApp/CarveApp.xcodeproj -scheme CarveApp -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-generic/DerivedData` | `ProcessXCFramework`는 실패 목록에 없고, SwiftPM `Sharing` 컴파일에서 `Dependencies`, `PerceptionCore`, `IssueReporting`, `ConcurrencyExtras`, `CustomDump`, `IdentifiedCollections` 모듈을 해석하지 못해 종료 코드 **65**. 앱 소스 컴파일·테스트 미도달 | 전체 로그 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-generic/build.log`, 종료 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-generic/build.exit` |

기본 샌드박스 실패 뒤 동일한 iPadOS 18.6 빌드를 서비스 접근이 가능한 CLI 실행으로 한 번 재시도했다. generic 재현 로그에서 Google/Firebase의 `UserMessagingPlatform`, `GoogleAppMeasurementIdentitySupport`, `GoogleAppMeasurement`, `FirebaseAnalytics`, `GoogleMobileAds` XCFramework `ProcessXCFramework` 작업은 각각 실행됐고 “identity … is not recorded in your project”는 **note**로 출력됐다. 이 재실행에서는 해당 작업의 서명 오류가 실패로 보고되지 않았다. 따라서 이번 generic 빌드는 기존 F60의 `ProcessXCFramework` 종료를 그대로 재현하지 못했으며, 현 시점의 빌드 종료 원인은 SwiftPM 의존성 모듈 해석 오류다. 다만 이것도 Xcode 27 앱 호환성 통과를 뜻하지는 않는다.

**읽기 전용 서명 조사:** 위 5개 XCFramework에 `codesign -dv --verbose=4`와 `codesign --verify --deep --strict --verbose=2`를 실행했다. 모두 서명 메타데이터와 TeamIdentifier `EQHXZ8M8AV`가 있었지만, `Authority`는 `unavailable`이고 번들 검증은 `invalid signature (code or signature have been modified)`로 종료됐다. 각 iOS simulator `.framework` slice는 별도 `codesign` 검사에서 서명되지 않은 코드 객체로 보고됐다. 상세 출력은 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-escalated/codesign-inspection.txt`에 보존했다. 이는 캐시된 artifact의 서명 상태 이상을 확인한 것이지만, 이번 빌드 로그의 `ProcessXCFramework` 실패는 아니므로 두 현상의 인과관계는 아직 확정하지 않는다. 서명·의존성·빌드 설정을 수정하거나 검증을 우회하지 않았다.

**당시 테스트·Device Hub:** 이 첫 재현 시점에는 빌드가 성공하지 않아 가장 좁은 관련 iPad simulator 테스트도 실행하지 않았다. 이후 결과는 아래 별도 Xcode 27 재검증 기록에 있다. Device Hub UI는 CUA에서 Mac이 잠겨 접근할 수 없다는 상태가 반환되어 열람하지 못했고, 앱 설치·실행 수동 스모크도 하지 않았다. 이는 자동화 테스트 결과와 별도 상태다. ACC 표본·CloudKit 계정·서버 상태는 사용하지 않았다.

### Tuist workspace 갱신 후 Xcode 27 빌드·회귀 (2026-09-24)

앞 절의 `-project CarveApp` 명령은 F60의 XCFramework 서명 실패를 재현하지 못했고 SwiftPM `Sharing` 타깃의 모듈 의존성 오류로 끝났다. 해당 시점의 생성 workspace는 앱 프로젝트보다 오래됐으며 Xcode 27 `-list -workspace`가 “not a workspace file”을 반환했다. 기존 상태를 덮지 않도록 실행 전에 다음 생성물을 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-regenerate/preserved/`에 복사했다: `Carve.xcworkspace`, `CarveApp.xcodeproj`, `Tuist/.build/tuist-derived`.

```bash
mise x -- tuist generate --no-open
# 성공, 전체 로그: /private/tmp/carve-2.0.0-xcode27-f60-20260924-regenerate/tuist-generate.log

xcodebuild build -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-workspace/DerivedData
# BUILD SUCCEEDED, exit 0
```

빌드 전체 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-workspace/build.log`, 종료 코드는 `build.exit`다. destination은 iPad mini (A17 Pro) iPadOS 18.6 (`22G86`)이며 SDK는 Xcode 27의 iOS Simulator 27.0이다. Google/Firebase XCFramework 다섯 개 모두 `ProcessXCFramework`를 통과했고 앱·Domain 소스 컴파일까지 진행했다. 앞서 읽기 전용 `codesign --verify`에서 확인한 artifact 상태 이상은 이 빌드의 실패 원인이 아니었다. 다만 별도 `-project CarveApp` generic 명령의 SwiftPM 모듈 오류는 계속 남으며 그 원인은 확정하지 않았다. `xcodebuild -list -workspace`는 생성 전후 exit 66 “not a workspace file”이었지만 실제 `-workspace Carve-Workspace` build/test는 실행됐다.

가장 좁은 두 suite를 최신 iPadOS 27.0 iPad mini (A17 Pro), UDID `C72A6CC6-4E3C-4822-BED1-9D76F8542D6B` (`24A434`)에서 먼저 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/focused-reader-ownership.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacyRowLinkageReaderTesting \
  -only-testing:DomainTest/DrawingStoreOwnershipProofTesting
# TEST SUCCEEDED: 37 tests in 2 suites, exit 0
```

이후 같은 runtime에서 전체 `Carve-Workspace` 회귀를 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/full-ios27.xcresult \
  -parallel-testing-enabled NO
# TEST FAILED, exit 65
```

전체 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/full-ios27.log`, exit는 `full-ios27.exit`다. 총 1008건 중 994 통과, 5개 미해결 실패, 기존 known issue 4건, 실기기 전용 UI 5건 skip이었다. `CarveFeatureTest/ChapterCanvasControllerTesting.changelessToolUseIsCancelled` 1건은 `cancelledCount == 1` 기대가 450ms 뒤에도 0이었다. Domain의 `LegacySeparationGateTesting.unversionedStoreIsMigratedButHeld` 1건과 `LocalStoreLoadFailureTesting` 3건은 iOS 27 SwiftData의 `unknownDataStoreSchema` / Core Data `134504 Cannot use staged migration with an unknown model version`로 기록됐다. 네 expected known issue는 별도 표본 probe 부재에 따른 기존 known issue다.

전체 결과의 안정성을 분리하려고 세 실패 suite를 같은 iPadOS 27.0 iPad mini에서 다시 실행했다. 첫 기본 sandbox 호출은 CoreSimulatorService 연결이 무효화되어 테스트를 시작하지 못했고, 종료 코드는 66이다(`/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27-rerun/focused-failures-ios27-rerun.log`, `.exit`; 지정 xcresult 디렉터리는 생겼지만 테스트 결과는 없다). 서비스 접근이 가능한 CLI 재실행은 다음과 같다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27-rerun-escalated/focused-failures-ios27-rerun.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacySeparationGateTesting \
  -only-testing:DomainTest/LocalStoreLoadFailureTesting \
  -only-testing:CarveFeatureTest/ChapterCanvasControllerTesting
# TEST FAILED, exit 65
```

`ChapterCanvasControllerTesting`은 **22/22 통과**해 전체 회귀의 cancellation timing 실패는 재현되지 않았다. Domain 두 suite는 총 26 tests 중 4 issues로 실패했다: `LegacySeparationGateTesting.unversionedStoreIsMigratedButHeld` 1건, `LocalStoreLoadFailureTesting`에서 기대한 `loadIssueModelContainer` 대신 `unknownDataStoreSchema`가 나온 1건, 1.0.0~1.0.3 무버전 migration dynamic case 2건이다. 따라서 다섯 실패 중 한 건은 focused rerun에서 재현되지 않았고, 네 SwiftData 관련 실패는 반복됐다. 전체 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27-rerun-escalated/focused-failures-ios27-rerun.log`, 종료 코드는 `.exit`, xcresult는 `focused-failures-ios27-rerun.xcresult`다. Test runner는 test 실행 후 simulator diagnostics 응답을 600초 기다렸다가 타임아웃했고 총 663.729초 뒤 종료했지만, 결과·로그 bundle은 생성됐다.

#### iOS 27 SwiftData 오류 대응 및 전체 회귀 재검증 (2026-09-24)

후속 재검증을 시작할 때 `CarveApp.xcodeproj`는 없고 `Carve.xcworkspace`는 9/12 생성본이었다. 재생성 전에 workspace와 `Tuist/.build/tuist-derived`를 `/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/preserved/`에 각각 복사했다. `mise x -- tuist generate --no-open`은 exit 0으로 workspace와 앱 프로젝트를 새로 만들었다. 그 전 첫 `xcodebuild` 시도는 stale workspace 및 sandbox CoreSimulatorService 연결 오류로 exit 66이었고 테스트는 0건이었다(`/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/focused-ios27.log`, `.exit`).

실패한 1.0.x store는 `NSPersistentStoreCoordinator` metadata의 모델 해시가 확인된 `unversionedLegacy`였지만, iOS 27 SwiftData가 Core Data 134504를 `.loadIssueModelContainer` 대신 새 `.unknownDataStoreSchema`로 노출해 기존 폴백 판별이 막았다. `LocalStoreLoader`는 iOS 27에서 해당 오류를 legacy schema mismatch로 인정하되, metadata 해시가 정확히 확인된 1.0.x store에만 V1 경로를 허용한다. `.unknown` store는 계속 `.unknownVersion`으로 막고 V7 데이터·파일 보존 테스트도 유지했다. V7 오류 기대 테스트는 OS에 따라 두 공개 SwiftData error 중 하나를 허용한다. 서명·빌드 설정·의존성은 바꾸지 않았다.

두 migration suite를 각각 26건 실행한 focused 검증은 Xcode 27에서 iOS 17.5, 18.6, 26.2, 27.0 모두 통과했다. 명령 형식은 다음과 같고 `<UDID>`는 각 runtime의 iPad mini (A17 Pro) 대상이다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath '/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/focused-{runtime}-after-fix.xcresult' \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacySeparationGateTesting \
  -only-testing:DomainTest/LocalStoreLoadFailureTesting
```

| Xcode 27 runtime | UDID | 결과 | 로그 / exit / xcresult |
|---|---|---|---|
| iOS 17.5 | `0347221E-08F5-48C9-9F8E-6D7995C25D9F` | 26/26 통과 | `/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/focused-ios17.5-after-fix.{log,exit,xcresult}` |
| iOS 18.6 | `7E95B700-3976-42D7-BF85-BCAF028B7605` | 26/26 통과 | 같은 폴더 `focused-ios18.6-after-fix.{log,exit,xcresult}` |
| iOS 26.2 | `086F17F4-649B-4AE5-9C78-22659E0F93F6` | 26/26 통과 | 같은 폴더 `focused-ios26.2-after-fix.{log,exit,xcresult}` |
| iOS 27.0 | `C72A6CC6-4E3C-4822-BED1-9D76F8542D6B` | 26/26 통과 | 같은 폴더 `focused-ios27-after-fix.{log,exit,xcresult}` |

수정 뒤 첫 iOS 27.0 전체 run은 997 통과·1 SQLite `database is locked`·4 expected failure·6 skip으로 끝났다. reader suite 31/31 단독 재실행은 통과해 잠금이 재현되지 않았다(`/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/reader-suite-ios27.{log,exit,xcresult}`). 함수 단위 `-only-testing` 시도는 Swift Testing 케이스를 선택하지 않아 **0건 실행**이었으며 결과에서 제외한다(`reader-single-ios27.*`). 이어 실행한 파일 제외 없는 전체 `Carve-Workspace` 회귀는 **998 통과·실패 0·4 expected failure·6 skip (총 1008)**로 통과했다(`/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/full-ios27-rerun.{log,exit,xcresult}`). 따라서 기존 다섯 unexpected failure는 수정 후 최신 전체 run에서 남지 않았다. iOS 27.0 CloudKit ownership 허용, live sync, 배포 아카이브 자격은 이 로컬 simulator 회귀로 승인하지 않는다.

runtime 차이를 분리하기 위해 실패 suite를 같은 Xcode 27에서 iPad mini (A17 Pro) iPadOS 26.2 (`23C54`), UDID `086F17F4-649B-4AE5-9C78-22659E0F93F6`로 재실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=086F17F4-649B-4AE5-9C78-22659E0F93F6' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios26.2/focused-failures.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacySeparationGateTesting \
  -only-testing:DomainTest/LocalStoreLoadFailureTesting \
  -only-testing:CarveFeatureTest/ChapterCanvasControllerTesting
# TEST SUCCEEDED: 48 tests in 3 suites, exit 0
```

세 suite의 실패가 iOS 26.2에서 재현되지 않아 같은 iPadOS 26.2 destination에서 전체 회귀를 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=086F17F4-649B-4AE5-9C78-22659E0F93F6' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios26.2/full-ios26.2.xcresult \
  -parallel-testing-enabled NO
# TEST SUCCEEDED: 999 passed, 4 known issues, 5 device-only UI skips; 0 unexpected failures (1008 total)
```

전체 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios26.2/full-ios26.2.log`, 종료 코드는 `full-ios26.2.exit`다. 집중 재실행 로그·결과도 같은 폴더의 `focused-failures.log`, `focused-failures.exit`, `focused-failures.xcresult`에 보존했다. Xcode 27의 iPadOS 26.2와 27.0 전체 회귀는 모두 통과했다. iOS 27.0의 `.unknownDataStoreSchema` 처리는 metadata가 확인된 1.0.x store에 한해 적용하며 ownership allowlist `[26]`은 유지한다. live CloudKit proof와 배포 자격은 별도로 확인해야 한다. Xcode 26.3 결과는 비교용 과거 기준으로 계속 분리한다.

### Xcode 27 전체 회귀 추가 runtime (2026-09-25)

macOS `27.2 (26B5086k)`, 기본 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`에서 `Carve-Workspace` 전체를 `xcodebuild test`로 실행했다. 모든 destination은 iPad simulator였고, runtime마다 새 DerivedData·xcresult를 사용했으며 파일 제외 설정을 주지 않았다. 첫 sandbox simulator 접근은 CoreSimulatorService 권한 오류를 냈고, 승인된 simulator 접근으로 전체 테스트를 완료했다. iCloud 로그인, ACC simulator/데이터, 실기기 입력 또는 서버 변경은 사용하지 않았다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=0347221E-08F5-48C9-9F8E-6D7995C25D9F' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios17.5/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios17.5/full.xcresult \
  -parallel-testing-enabled NO
# iPad mini (6th generation), iOS 17.5 (21F79): 998 passed, 4 expected failures, 6 skipped, 0 failed (1008 total)
```

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios18.6/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios18.6/full.xcresult \
  -parallel-testing-enabled NO
# iPad mini (A17 Pro), iOS 18.6 (22G86): 999 passed, 4 expected failures, 5 skipped, 0 failed (1008 total)
```

두 실행의 전체 로그·exit·xcresult는 각각 `/private/tmp/carve-2.0.0-xcode27-full-20260925/ios17.5/`와 `.../ios18.6/` 아래 `full.log`, `full.exit`, `full.xcresult`다. xcresult summary는 두 runtime 모두 `Passed`, unexpected failure 0, `runtimeWarnings` 없음이었다. iOS 17.5의 전체 로그에는 simulator `data/tmp` 아래 UUID 임시 migration/store fixture와 `-wal`·`-shm` 파일을 가리키는 `vnode unlinked while in use` 382건과 `invalidated open fd` 382건이 기록됐다. 대표 사례는 V3→V5 및 V4 migration 테스트 중 임시 저장소 정리 시점이며 해당 테스트는 통과했다. 로그만으로 컨테이너 객체 수명 원인을 확정할 수 없어 fixture cleanup 후속 조사 항목으로 남긴다. iOS 18.6 로그에서는 같은 경고가 관찰되지 않았다. 이 로그 진단은 xcresult failure/runtime warning으로 집계되지 않았고 사용자 저장소를 가리키지 않았다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=2C610CAE-8E1D-4145-A145-9FE7E1CC1356' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios26.4/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios26.4/retry.xcresult \
  -parallel-testing-enabled NO
# iPad mini (A17 Pro), iPadOS 26.4 (23E244): 999 passed, 4 expected failures, 5 skipped, 0 failed (1008 total)
```

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=589A8DAB-2D5C-45FC-B76B-C4260FB87C67' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios26.5/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios26.5/full.xcresult \
  -parallel-testing-enabled NO
# iPad mini (A17 Pro), iPadOS 26.5 (23F77): 999 passed, 4 expected failures, 5 skipped, 0 failed (1008 total)
```

iPadOS 26.4·26.5 결과 bundle도 `Passed`, unexpected failure 0, `runtimeWarnings` 없음이다. 26.4 최종 로그·exit는 `ios26.4/retry.log`·`retry.exit`·`retry.xcresult`에 있다. 앞선 sandbox service 조회는 exit 66, service 접근 뒤 첫 빌드 호출은 기존 `full.xcresult` 경로 충돌(exit 64)로 테스트를 시작하지 못했다. 그 경로를 보존하고 최종 검증은 별도 `retry.xcresult`로 수행했다. 26.5 로그·exit·xcresult는 `ios26.5/full.log`·`full.exit`·`full.xcresult`다. 두 runtime의 테스트는 Xcode 27 CLI로 수행했고 ACC·iCloud 로그인·CloudKit 서버 변경은 없었다.

초기 검증 시점에는 CUA가 호스트 Mac 잠금 상태를 반환해 Device Hub 스모크를 하지 못했다. 2026-09-24 잠금 해제 뒤 수행한 수동 확인은 아래 별도 기록에 있다. 이는 자동 CLI build/test와 별도다. ACC simulator/데이터를 사용하지 않았고, CloudKit 계정 로그인·필기 입력·의도적인 서버 상태 변경은 하지 않았다. 앱 시작 화면은 기존 iCloud 필사를 받고 있다고 표시했으므로 백그라운드 네트워크 읽기 여부는 검증하지 않았으며 이 결과를 CloudKit proof로 세지 않는다. Release Archive·배포 서명·TestFlight도 확인하지 않았다. 당시 출시 판정은 **NO-GO**였다. 이후 Xcode 27 iPadOS 26.5 ACC sandbox clone에서 기존 private-store ownership proof를 통과했으며, 전체 현행 게이트와 제한은 이 절 뒤의 2026-09-25 기록을 따른다. iOS 18 migration marker·계정 왕복, 로그인 상태 1.3.0 업데이트, iOS 17.0 직접 시험, production CloudKit 및 배포 archive/TestFlight는 여전히 남아 있어 출시 판정은 **NO-GO**다.

#### Device Hub 수동 UI smoke (2026-09-24, 자동 테스트와 별도)

호스트 잠금 해제 후 새 simulator `Carve-Xcode27-DeviceHub-Smoke-20260924` (iPad mini (A17 Pro), iPadOS 27.0 build `24A434`, UDID `0D967FE8-ECAC-42F5-AAC6-56E927A3844D`)를 만들었다. 생성 직후 Device Hub에 `No Developer Apps`로 보였고, Xcode 27 `Carve-Workspace` Debug build의 `CarveApp.app` (bundle `kr.co.carve.leetaek`, version 2.0.0 (1))을 설치했다. Device Hub에서 앱을 직접 열고 “먼저 시작하기”와 첫 실행 안내 “건너뛰기”를 눌러 창세기 1장 reader까지 확인했다. 31절 본문과 빈 필사 열이 표시됐고 실행 취소·다시 실행은 비활성이었다. 필기 입력, 메뉴, 장 이동, 저장 기능은 누르지 않았다. 크래시나 화면 오류는 관찰하지 않았다.

후속 수동 확인에서 Device Hub의 `nextChapter` 버튼을 눌러 창세기 2장으로 이동한 뒤 이전 장 버튼으로 창세기 1장에 복귀했다. 양쪽 장 제목과 본문이 표시되는 것을 접근성 트리에서 확인했다. 본문 이동 확인만 했으며 필기나 절 메뉴를 조작하지 않았다. Device Hub 창과 simulator 명칭은 기존 startup smoke와 같고 자동화 테스트 결과에는 포함하지 않는다.

시작 중 앱 UI는 “iCloud에 저장된 필사를 확인”하고 “아직 기존 필사를 받고 있어요”라고 표시했다. 이 simulator에 iCloud 계정을 로그인하지 않았고 기존 ACC 기기·데이터를 사용하지 않았다. 앱 시작 자체에서 백그라운드 CloudKit/network read가 발생했는지는 별도로 계측하지 않았으므로 서버와 통신이 전혀 없었다고 단정하지 않는다. 사용자가 CloudKit에 로그인하거나 필기를 쓰는 조작, 의도적인 서버 상태 변경은 하지 않았다. 이 확인은 **수동 UI startup 및 인접 장 이동 smoke만 통과**한 것이며 자동 테스트, 계정 동기화, CloudKit ownership proof, 저장·복원 검증은 아니다. Device Hub 화면만 사용했고 Xcode MCP는 쓰지 않았다.

### Xcode 27 기존 private CloudKit ownership proof 사전 실행 (2026-09-25, 첫 시도 계정 확인에서 차단)

현행 환경은 macOS `27.2 (26B5086k)`, 기본 선택 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`이다. `xcode-select -p`는 `/Applications/Xcode.app/Contents/Developer`를 가리킨다. 대상은 ownership reader 허용 범위 `[26]`에 속하는 iPadOS 26.5 (`23F77`)이며, iPhone destination은 사용하지 않았다.

사용자가 2026-09-25 기존 ACC 데이터 변경을 허용했다. 원본 `Carve-ACC-B` (`DB142B76-153A-462E-AC54-4A9B3BDF6D9F`)는 종료 상태로 두고 `xcrun simctl clone`으로 `Carve-ACC-Xcode27-Proof-20260925` (`E73A3120-C87C-4017-BF59-BA227BFCD580`)를 만들었다. 복제는 같은 sandbox 계정과 Development private DB를 공유할 수 있으므로 서버 격리가 아니다. 계정 전환이나 로그인 조작은 하지 않았다.

앱 실행 전 원본 SQLite, `-wal`, `-shm`, Preservation, EraseState를 `/private/tmp/carve-2.0.0-acc-proof-20260925/pre-local/`에 복사했다. 원본 store는 V6, `integrity_check=ok`, `BibleDrawing` 12행, record metadata 12행, nonempty·unique CK record name 12개, upload/cloud-delete/local-delete pending은 각각 0이었다. Genesis 1:1 및 1:2의 row UUID 해시, line/layout byte 수와 SHA-256은 복제 전 snapshot과 앱 실행 뒤 복제본에서 같았다(1:1 line 1340B, 1:2 line 1220B). 복제본도 무결성 `ok`, 12행·12 metadata, pending 0이며 StoreOwnership marker는 없었다. ACC-B 원본의 DB 본문과 WAL 해시는 snapshot과 같았다. 다만 한 번 `simctl get_app_container`가 clone 호출에도 원본 경로를 반환했고, 그 경로를 읽기 전용 SQLite로 확인하는 동안 원본 `-shm`가 바뀌었다. SQLite의 읽기 전용 open도 `-shm`를 갱신할 수 있다는 F35 관측과 맞으며, DB/WAL 및 표본 payload는 바뀌지 않았다. 원본 simulator는 계속 종료 상태다.

로컬-only strict profile 재확인에서는 `ANSCKMETADATAENTRY`가 예상 metadata key 7개를 중복 없이 모두 가지고 있었고 값 형식 profile 완전, `needsMigration=false`, 저장소 내부 `identityChecked=true`였다. 이 flag는 저장소 내부 값만 확인한 것이며 현재 iCloud 계정 identity와 일치한다는 뜻은 아니다. 세 legacy entity를 합쳐 12행 모두 대응 12개, 이름 존재·유일성 12개, orphan 0, pending 0이었다. 계정 상태와 CloudKit fetch가 준비되지 않아 이 로컬 결과만으로 ownership marker를 만들거나 소유를 인정하지 않았다.

```bash
xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=DDE9B05A-B684-486E-A8A2-AFFCED4BA600' \
  -derivedDataPath /private/tmp/carve-2.0.0-acc-proof-20260925/DerivedData
# BUILD SUCCEEDED, exit 0; build.log, build.exit

SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=/private/tmp/carve-2.0.0-acc-proof-20260925/libCarveCloudKitReadOnlyProbe.dylib \
SIMCTL_CHILD_CARVE_CK_PROBE_LABEL=baseline \
  xcrun simctl launch E73A3120-C87C-4017-BF59-BA227BFCD580 kr.co.carve.leetaek
# launch exit 0; launch-baseline.log, launch-baseline.exit
```

임시 probe는 앱의 entitlements로 `iCloud.Carve.SwiftData.iCloud.dev` private zone `com.apple.coredata.cloudkit.zone`을 조회하고 `desiredKeys=[]`로 필드/payload를 요청하지 않는다. CloudKit write API는 호출하지 않는다. baseline 작업은 120초 동안 끝나지 않아 취소됐고 JSON은 `status=timeout`, `recordCount=0`이다. 이 0건은 zone이 비었다는 증거가 아니며 inventory baseline 확보 실패다. 요약은 복제 앱의 `tmp/carve-cloudkit-baseline.json`이다.

앱이 시작된 뒤 CloudKit 로그는 account status `Temporarily Unavailable`, `hasValidCredentials=false`를 보였다. Core Data CloudKit setup은 `NSCocoaErrorDomain 134400` / `CKAccountStatusTemporarilyUnavailable`로 실패했다. 현재 계정 identity를 검증하거나 기존 private DB 레코드를 조회하지 못했고, fail-closed 소유 marker는 생성되지 않았다. clone의 후속 local store 검증에서 Genesis 1:1·1:2 payload 지문과 모든 pending count가 실행 전과 같았다. 로그인 상태가 준비되지 않아 서버 전후 inventory 및 production ownership proof는 미실행/미판정이다.

빌드 전체 로그·exit는 `/private/tmp/carve-2.0.0-acc-proof-20260925/build.log`·`build.exit`이다. 첫 launch/app 로그는 account identifier 필드를 가린 `/private/tmp/carve-2.0.0-acc-proof-20260925/app.log`에 있고, launch 결과는 `launch-baseline.log`·`launch-baseline.exit`, 읽기 전용 CloudKit 요약은 위 JSON이다. 첫 시도에서는 자동 테스트나 Device Hub 수동 조작을 하지 않았다. 자동 테스트는 기존 Xcode 27 iPadOS 26.5 전체 회귀(999 passed · 4 expected failures · 5 skips · unexpected failure 0)와 별도다. 사용자가 같은 ACC sandbox account를 복제 simulator에 로그인한 뒤 이어서 확인한 결과는 다음 절에 기록한다. 계정 전환이나 auto-review 우회는 하지 않았다. 출시 판정은 **NO-GO** 유지다.

### Xcode 27 기존 private CloudKit ownership proof — 로그인 후 재개 (2026-09-25)

첫 시도 뒤 사용자가 `Carve-ACC-Xcode27-Proof-20260925`와 Xcode 27에 기존 ACC와 같은 sandbox account로 로그인했다. 계정 전환은 없었다. 원본 `Carve-ACC-B`는 계속 종료 상태로 보존하고, 기존 복제본에서만 Debug 앱을 재실행했다. 실행 대상은 iPadOS 26.5 (23F77), Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27.2 (26B5086k), Tuist 4.208.0이다.

로그인 뒤 앱 실행과 함께 같은 private zone의 inventory를 다시 수집했다. CloudKit probe는 앱 entitlements의 `iCloud.Carve.SwiftData.iCloud.dev`와 `com.apple.coredata.cloudkit.zone`을 사용하며, `desiredKeys=[]`, `readOnly=true`로 필드/payload 없이 record name·change tag 지문만 읽는다. 앱 시작 로그에서는 첫 시도의 `Temporarily Unavailable`/134400이 다시 나오지 않았다. Core Data가 원격 레코드를 가져왔고 clone의 drawing/record metadata 행 수는 12에서 20으로 늘었다. 앱 로그에는 `Found 0 objects needing export`와 `madeChanges: 0`이 기록됐다.

로그인 후 완료 inventory는 20개 `CD_BibleDrawing`, record error 0, SHA-256 `8473c94c3afe622ecde121a07b7189512f9384d27d531fbc605948804ea791d3`였다. 앱을 다시 시작한 뒤 두 번째 읽기 전용 inventory도 20개·오류 0·같은 지문으로 완료됐다. 따라서 확인 가능한 범위에서 두 완료 조회 사이 서버 record inventory 변화는 없었다. 첫 12개에서 20개로의 로컬 증가는 clone의 CloudKit import 결과다. probe는 CloudKit write API를 호출하지 않았다.

재실행 후 clone store는 `integrity_check=ok`, `BibleDrawing` 20행, `ANSCKRECORDMETADATA` 20행이었다. 로컬 record name은 원문을 출력하지 않고 SHA-256으로 변환해 비교했으며, 20개 전부가 remote record name hash 집합과 일치했다(로컬 누락 0, 서버 추가 0). upload·cloud-delete·local-delete pending은 모두 0이었다. Genesis 1:1(1340B)·1:2(1220B)의 present payload 지문은 앱 실행 전 clone snapshot과 같았다. `StoreOwnership/Carve.dev.sqlite.json`은 `formatVersion=1`, `proof=currentPrivateCloudRecords`로 생성됐으며 owner 값은 읽거나 기록하지 않았다. 이 표식은 앱의 기존 private-store 판정이 현재 계정 일치·strict local profile·전체 private record 조회를 통과했음을 나타낸다. 허용 OS 범위는 여전히 `[26]`이다.

주요 명령과 증거 경로:

```bash
SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=/private/tmp/carve-2.0.0-acc-proof-20260925/libCarveCloudKitReadOnlyProbe.dylib \
SIMCTL_CHILD_CARVE_CK_PROBE_LABEL=post-login-baseline \
  xcrun simctl launch --terminate-running-process E73A3120-C87C-4017-BF59-BA227BFCD580 kr.co.carve.leetaek

SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=/private/tmp/carve-2.0.0-acc-proof-20260925/libCarveCloudKitReadOnlyProbe.dylib \
SIMCTL_CHILD_CARVE_CK_PROBE_LABEL=post-proof \
  xcrun simctl launch --terminate-running-process E73A3120-C87C-4017-BF59-BA227BFCD580 kr.co.carve.leetaek
```

두 launch는 exit 0이다. baseline·최종 JSON은 clone app container의 `tmp/carve-cloudkit-post-login-baseline.json` 및 `tmp/carve-cloudkit-post-proof.json`, 마지막 로그는 identifier 필드를 가린 `/private/tmp/carve-2.0.0-acc-proof-20260925/app-after-login.log`에 있다. 민감한 원본 로그는 같은 디렉터리의 `.private-raw.log`로 남아 파일 모드 600이다. 이 실행에서는 자동 회귀를 재실행하거나 Device Hub를 사용하지 않았다. Xcode 27 iPadOS 26.5 전체 회귀(999 passed · 4 expected failures · 5 skips · unexpected failure 0)는 별도 CLI 결과다. 이 성공은 iOS 26.5의 기존 store + ACC sandbox private CloudKit ownership 경로에 한정되며 iOS 18 marker, 로그인 상태 1.3.0 업데이트, iOS 17, production CloudKit, Archive·배포 서명·TestFlight를 통과시키지 않는다. 출시 판정은 **NO-GO** 유지다.

### Xcode 27 iPadOS 18.6 1.3.0 → 2.0.0 계정 없는 V3 migration probe (2026-09-25)

환경은 macOS `27.2 (26B5086k)`, 기본 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, 현재 checkout Tuist `4.208.0`이다. 대상은 새 iPad mini (A17 Pro) iOS 18.6 simulator `Carve-X27-iOS18.6-V3-Offline-20260925` (`9078BCF2-5F9C-40F9-A265-3F0600BC3A0D`)이며 ACC/F59 원본 simulator를 사용하지 않았다. 이 실행에서는 simulator에 iCloud 계정을 추가하지 않았다.

정확한 1.3.0 소스 commit `49f2dc2791c632627257d28f33278d43e7df8cc9`에서 Tuist `4.39.0`으로 프로젝트를 생성했다. 고정된 29개 package pin을 임시 cache에 설치했고 `Tuist/Package.resolved` SHA-256은 전후 `e9c594efdef65c60c2002f6948764d14a8a76cc4076fb4a75156f401d6d4e628`로 같았다. Xcode 27로 historical 1.3.0 앱을 다시 빌드한 시도는 exit 65로 실패했다. Firebase·GoogleUtilities 계열 등의 iOS 12/13 및 SwiftSyntax 계열의 macOS 10.15 deployment target을 Xcode 27 SDK가 지원하는 최솟값(iOS 15/macOS 12)보다 낮다고 거절했다. 로그에 Swift compile task가 없어 자사 Swift 소스 컴파일 전 빌드 계획 단계에서 멈췄다. 의존성 버전이나 deployment target/build setting을 바꾸지 않았다. 시작 앱은 `Carve-2.0.0-test-legacy` (`0A956010-5DAA-44BC-BA22-5BAE53FF6D82`)에 이미 설치돼 있던 1.3.0(1) simulator bundle을 임시 디렉터리로 복사해 사용했고, 복사본의 `codesign --verify --deep --strict`는 통과했다. 따라서 이 과거 앱 bundle 자체를 Xcode 27에서 새로 빌드한 결과로 취급하지 않는다.

재빌드 시도 명령은 다음과 같다. 사용한 2.0.0(1) 앱은 이전 Xcode 27 workspace build 산출물 `/private/tmp/carve-2.0.0-acc-proof-20260925/DerivedData/Build/Products/Debug-iphonesimulator/CarveApp.app`이며, 해당 `build.exit`는 0이다. 이 후보 앱의 소스는 이 probe 전후 바뀌지 않았다.

```bash
xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-1.3.0-artifact-20260925.hYLOHD/DerivedData
xcrun simctl launch --terminate-running-process 9078BCF2-5F9C-40F9-A265-3F0600BC3A0D kr.co.carve.leetaek
```

입력은 F59에서 보존한 계정 없는 V3 synthetic 표본 `/private/tmp/carve-2.0-live-proof-20260924/legacy-ios18.6-pointer-sample-before-2.0.sqlite`의 별도 복사본이다. 원본 및 F59 simulator는 변경하지 않았다. 복사본은 무결성 `ok`, Genesis 1:1 한 행, `ZLINEDATA` 298B / SHA-256 `07876e8b1910039124914f5c44b9619a90b8ad488a08500bdfa6abc07762c3d6`, `ANSCKMETADATAENTRY` 네 개, `ANSCKRECORDMETADATA` 0행이었다. 해당 표본의 기존 1.3.0(1) 앱을 새 simulator에 설치하고 store를 심은 뒤 Xcode 27 빌드 2.0.0 앱을 같은 bundle ID로 설치·실행했다. install과 launch는 각각 exit 0이다.

2.0.0 실행 후 SQLite `integrity_check=ok`, `BibleDrawing` 1행이었다. iOS 17.x→2.0 스키마 migration 열 `ZROWUUID`와 `ZLAYOUTMETADATADATA`가 생겼고, Genesis 1:1 `ZLINEDATA`는 298B이며 입력 snapshot과 SHA-256이 같았다. `Library/Application Support/Preservation/.../Carve.dev.sqlite` 원본 사본의 SHA-256도 입력 파일과 같아 보존 snapshot을 확인했다. 앱이 만든 metadata key는 다섯 개로 늘었고 새 키 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`가 있었다. 이 private marker의 의미는 확인되지 않았으며 iOS 18 ownership 허용 근거로 쓰지 않는다. 앱 로그의 Core Data CloudKit setup은 `NSCocoaErrorDomain 134400` / `CKAccountStatusNoAccount`로 중단됐다. record metadata·pending 작업은 0, `StoreOwnership` marker는 없었다. 이는 이 합성 단일 행의 **로컬 migration·payload 보존 통과**만 뜻한다. 계정 proof·CloudKit import/export·서버 변경 여부는 시험하지 않았다.

새 실행의 초기 전체 로그와 exit는 `/private/tmp/carve-1.3.0-artifact-20260925.hYLOHD/` 아래에 기록됐으나 2026-09-25 후속 점검 시 이 임시 디렉터리는 이미 없어 원본 파일을 재열 수 없었다. 저장소에는 당시 exit·결과가 위 문단과 이 문서의 실행 기록에 보존돼 있다. 당시 Device Hub 최초 화면 관찰은 필사 획이 보이지 않는다고 기록했지만, 이것은 확대 전·일시 오버레이를 열린 화면의 관찰이었다.

#### 2026-09-25 후속 read-only CanvasDisplayProbe 및 Device Hub 재확인

기존 no-account 시뮬레이터 `Carve-X27-iOS18.6-V3-Offline-20260925`에서 앱에 `-CanvasDisplayProbe`만 전달해 읽기 전용 캔버스 상태를 다시 관찰했다. `-CanvasDisplayExperiments`는 전달하지 않았고, 필기 입력·절 메뉴·CloudKit write는 실행하지 않았다.

```bash
xcrun simctl launch --terminate-running-process --console \
  9078BCF2-5F9C-40F9-A265-3F0600BC3A0D kr.co.carve.leetaek -CanvasDisplayProbe
xcrun simctl terminate 9078BCF2-5F9C-40F9-A265-3F0600BC3A0D kr.co.carve.leetaek
```

probe 로그 `/private/tmp/carve-x27-v3-display-probe-20260925/probe-console.raw.log`와 launch/terminate 로그·exit 파일은 확인 시 존재했고 파일 mode는 600이었다. launch와 terminate는 각각 exit 0이다.

첫 fetch 전 sample은 `expected=n0`, `canvas=n0`였고, fetch 완료 sample은 `expected=n1:(433.0, 145.0, 49.0, 4.0)`, `canvas=n1:(433.0, 145.0, 49.0, 4.0)`, `storeDiff=0`, `deliveredDiff=0`, `screenInk=(433.0, 287.0, 49.0, 4.0)`였다. 실제 canvas가 store의 한 획을 받아 동일 경계로 적용했고 화면 변환에서도 non-empty 영역을 보고했다. 기존 SQLite 행도 `drawingVersion=1`, payload 298B, 기존 SHA-256과 일치했다. Device Hub에서 일시 오버레이를 닫고 화면을 확대하자 Genesis 1:1 오른쪽 필사 영역에 작은 획이 보였다. 창세기 1→2→1 이동 뒤 확인한 이 수동 화면 관찰은 자동 CLI 테스트 결과와 구분한다.

이에 따라 최초 “화면에 획이 보이지 않음” 관찰은 표시 결함 판정에서 철회한다. 이 한 개의 synthetic no-account iOS 18.6 표본에서 로컬 payload 보존, fetch 후 canvas 적용, 확대 화면 표시와 장 이동 뒤 표시를 확인했다. 이는 로그인 상태 1.3.0 업데이트, 좌표 기준 legacy 비교, iOS 18 migration marker 의미, ownership proof 또는 CloudKit 동기화 자격을 증명하지 않는다. iOS 18 marker 의미·계정 proof, 로그인 상태 1.3.0 업데이트, iOS 17 proof/직접 회귀, production CloudKit, Archive·배포 서명·TestFlight는 계속 NO-GO다.

### Xcode 27 iPadOS 26.5 로그인 상태 1.3.0 → 2.0.0 기존 store 승격 (2026-09-25)

실행 환경은 macOS `27.2 (26B5086k)`, 기본 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`이다. Xcode 27의 iOS Simulator SDK `27.0`으로 빌드했고, 자동 테스트는 iPad mini (A17 Pro) iPadOS `26.5 (23F77)` (`589A8DAB-2D5C-45FC-B76B-C4260FB87C67`)를 사용했다. 이 테스트 destination은 ACC clone과 별도이며 iPhone destination은 사용하지 않았다. checkout에 Tuist workspace가 있으므로 재생성하지 않았다.

먼저 Xcode 27 후보 앱을 CLI로 빌드했다. 변경된 서명·빌드 설정은 없었다.

```bash
xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=589A8DAB-2D5C-45FC-B76B-C4260FB87C67' \
  -derivedDataPath /private/tmp/carve-x27-acc-login-update-20260925/DerivedData
# BUILD SUCCEEDED, exit 0
```

전체 빌드 로그·종료 코드는 `/private/tmp/carve-x27-acc-login-update-20260925/build.log`·`build.exit`다. 생성된 simulator 앱의 bundle version은 2.0.0 (1)이며 `codesign --verify --deep --strict`가 통과했다. 로그에는 File Length와 Sendable 관련 비치명적 경고가 있었고 빌드는 성공했다. 이는 simulator 산출물 검사이고 배포 서명·Archive 증거가 아니다.

기존 로그인 proof source `Carve-ACC-Xcode27-Proof-20260925` (`E73A3120-C87C-4017-BF59-BA227BFCD580`)를 종료 상태로 보존하고 같은 기기의 별도 복제본 `Carve-ACC-Xcode27-LoginUpdate-20260925` (`6C59D527-24D2-4519-AD43-2AC988C14F54`)에서만 설치·실행했다. clone과 source의 private CloudKit identity 지문은 일치했다. `Carve-ACC-dut`는 identity 지문이 달라 이번 시험에서 제외했다. 원본 ACC-B와 해당 기기의 데이터는 변경하지 않았다.

legacy 입력 앱은 기존 `Carve-2.0.0-test-legacy` simulator에서 복사한 historical 1.3.0 (1) bundle(`/Users/leetaek/Library/Developer/CoreSimulator/Devices/0A956010-5DAA-44BC-BA22-5BAE53FF6D82/data/Containers/Bundle/Application/B90495D8-3A9B-4E2B-A035-F4D6D54799D2/CarveApp.app`)이다. 이 bundle의 읽기 전용 strict signature 확인은 통과했으나 Xcode 27에서 다시 빌드한 것은 아니다. 정확한 1.3.0 소스의 Xcode 27 재빌드는 이전 기록처럼 dependency deployment target 검증 단계에서 중단됐고, 그 설정은 바꾸지 않았다.

clone의 기존 2.0.0 앱 컨테이너를 제거한 뒤 위 1.3.0 bundle을 설치·실행했다. 동일 계정 private store에서 기존 레코드 20개가 local V3 store로 들어왔고 `BibleDrawing`/`ANSCKRECORDMETADATA` 각각 20행, pending export 0, 무결성 `ok`를 확인했다. payload multiset·CloudKit record-name hash 집합·계정 identity 지문은 source proof clone과 일치했다. 그 다음 새 Xcode 27 2.0.0 산출물을 같은 clone에 설치·실행했다. 실행 뒤 무결성은 `ok`, drawing/record metadata는 각각 20행, pending export 0, V4 `ZROWUUID` 열과 새 `currentPrivateCloudRecords` ownership marker가 확인됐다. payload multiset, record-name hash 집합, marker의 owner scope는 source와 같았다. identity 원문이나 account identifier는 저장·출력하지 않았다. 이 upgrade 실행 뒤 별도 read-only server inventory를 재수집하지 않았으므로 서버의 독립적인 전후 inventory 불변성까지 주장하지 않는다.

Device Hub 수동 확인은 자동 CLI 테스트와 별도다. 잠금 해제 뒤 clone을 선택했을 때 2.0.0이 창세기 1장 reader와 기존 필기 몇 개를 표시했다. 첫 실행 안내와 AdMob 검증 팝오버가 겹쳐 있었으며 이를 닫거나 필기·절 메뉴·장 이동을 조작하지 않고 화면만 관찰했다. 수동 확인은 기존 필기가 보이는 상태를 관찰한 것이며 자동 테스트 또는 CloudKit 서버 proof로 세지 않는다.

새 후보로 가장 좁은 두 Domain suite를 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=589A8DAB-2D5C-45FC-B76B-C4260FB87C67' \
  -derivedDataPath /private/tmp/carve-x27-acc-login-update-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-acc-login-update-20260925/ownership-focused-retry.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacyRowLinkageReaderTesting \
  -only-testing:DomainTest/DrawingStoreOwnershipProofTesting
# 37 passed, 0 failed, 0 skipped; xcresult Passed, exit 0
```

제한된 sandbox에서 같은 테스트를 처음 호출했을 때 CoreSimulatorService의 log/runtime 조회 권한 오류와 workspace 읽기 오류로 테스트 시작 전 exit 66이 났다. 해당 원본 로그·exit는 `/private/tmp/carve-x27-acc-login-update-20260925/ownership-focused.log`·`ownership-focused.exit`에 보존했다. 더 넓은 CLI 권한으로 별도 `ownership-focused-retry.*` 경로에 재시도했고, `/private/tmp/carve-x27-acc-login-update-20260925/ownership-focused-retry.log`·`ownership-focused-retry.exit`·`ownership-focused-retry.xcresult`에 성공 실행 전체 로그·exit·결과 bundle을 보존했다. 재시도는 37 통과, 실패 0, skip 0이다.

또한 Xcode 27 iOS Simulator 27.0 SDK의 CoreData simulator SDK 파일에서 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey` 문자열을 읽기 전용 검색했지만 정의를 찾지 못했다. 이는 private marker의 의미를 확인하지 못한 상태를 바꾸지 않으며 iOS 18 허용 근거가 아니다.

이번 결과는 **iOS 26.5 same-account, 기존 CloudKit-backed V3 store에서 1.3.0 실행 뒤 2.0.0으로 업데이트하는 한 복제 경로**를 확인한다. 미업로드 local-only 필기·pending export가 있는 로그인 전환, 무계정 V3의 첫 로그인 upload와 다른 기기 수신, iOS 18 marker 허용, iOS 17 ownership/직접 iOS 17.0 회귀, production CloudKit, 서명 Archive·배포 entitlement·TestFlight는 미완료다. 계정·시뮬레이터를 사용한 경험은 해당 경로로만 제한하며 전체 출시 판정은 **NO-GO**다.

### Xcode 27 iPadOS 26.5 무계정 V3 첫 로그인 업로드·peer 수신 (2026-09-25)

실행 환경을 다시 확인했다. `xcode-select -p`는 `/Applications/Xcode.app/Contents/Developer`, `xcodebuild -version`은 Xcode `27.0 (27A266a)`, Swift는 `6.4 (swiftlang-6.4.0.34.1)`, Tuist는 `mise x -- tuist version` 결과 `4.208.0`이다. 첫 sandbox Tuist 조회는 user state session 권한 오류로 실패해 같은 표준 명령을 권한을 높여 재시도했다. iOS 17.5·18.6·26.2·26.4·26.5·27.0 runtime이 있으며 이번 대상은 iPad mini (A17 Pro) iPadOS `26.5 (23F77)`다. iPhone destination을 사용하지 않았다.

대상 `Carve-X27-FirstLogin-20260925` (`7284FDE5-6F95-4CC6-8EE6-75A794009F0F`)은 새 계정 없는 simulator에서 historical 1.3.0 (1) 앱으로 synthetic Genesis 1:31 필기를 저장하고 Xcode 27 2.0.0 (1) 앱으로 덮어 업데이트한 동일 기기다. historical 앱 bundle은 이미 존재하던 1.3.0 simulator 산출물이며 Xcode 27에서 재빌드하지 않았다. 로그인 전 2.0.0 local store는 V4 `ZROWUUID`를 갖고 integrity `ok`, Genesis 1:31 한 행, drawing/record metadata 미생성, pending export 0이었다. 입력 payload는 300B, SHA-256 `2174feb6c509e187417d9aa41400618b86c12e07cb4f39f729d98d71c87c3558`이다. 원본·로그인 전후 snapshot은 `/private/tmp/carve-x27-first-login-preflight-20260925/` 아래에 둔다.

사용자가 이 simulator의 설정에서 기존 ACC와 같은 sandbox Apple 계정으로 직접 로그인했고 계정 전환은 없었다. Xcode 27에도 같은 계정이 로그인된 상태였다. 비밀번호·계정 식별 원문은 문서에 기록하지 않았다. 로그인 뒤 앱을 CLI로 실행했다.

```bash
xcrun simctl launch --terminate-running-process 7284FDE5-6F95-4CC6-8EE6-75A794009F0F kr.co.carve.leetaek
# exit 0; /private/tmp/carve-x27-first-login-preflight-20260925/candidate-first-login-launch.log(.exit)

xcrun simctl spawn 7284FDE5-6F95-4CC6-8EE6-75A794009F0F log show --last 10m --style compact \
  --predicate 'process == "CarveApp"'
# 앱 프로세스 전체 로그: /private/tmp/carve-x27-first-login-preflight-20260925/candidate-carveapp-full.log
```

Core Data가 private Development container 연결을 성공했다. 시작 중 export 재요청 2건은 이미 대기 중인 요청과 겹쳐 `134417`으로 취소됐으나, 뒤이어 원격 import가 `success=1, madeChanges=1`, synthetic local row export가 `success=1, madeChanges=1`, 후속 export가 `success=1, madeChanges=0`으로 끝났다. 앱 실행 뒤 store는 drawing 21행·record metadata 21행, `ZROWUUID` 존재, `integrity_check=ok`였다. Genesis 1:31 payload는 300B와 위 SHA-256 그대로다. 이 row metadata의 upload·cloud-delete·local-delete pending 합계는 각각 0이며 StoreOwnership marker의 비민감 필드는 `formatVersion=1`, `proof=firstLoginFromUnaccountedV3`였다. 전체 로그인 후 SQLite 복사본은 `post-first-login-store/`다.

독립 peer `Carve-ACC-Xcode27-LoginUpdate-20260925` (`6C59D527-24D2-4519-AD43-2AC988C14F54`)은 같은 계정의 iPadOS 26.5 simulator clone이다. 앱 실행 전 보존한 store는 drawing/metadata 각 20행이고 Genesis 1:31 row는 없었으며 기존 `currentPrivateCloudRecords` marker와 integrity `ok`를 확인했다. CLI로 2.0.0 앱을 실행한 뒤 보존한 store는 drawing/metadata 각 21행, Genesis 1:31 row 한 개와 동일한 300B payload SHA-256, row metadata pending 세 종류 모두 0, integrity `ok`였다. Device Hub 관찰 뒤 다시 보존한 사본에서도 21행·payload 지문·pending 0이 같았다. 이 전후 차이는 peer의 기존 로컬 store에는 없던 sample이 첫 기기 export 뒤 peer의 CloudKit 연동 store에 수신된 것을 확인한다. 사본은 `peer-before-receive-store/`, `peer-after-receive-store/`, `peer-post-observation-store/`다.

read-only CloudKit probe artifact가 `/private/tmp`에서 사라져 이 실행의 업로드 직후 remote-zone inventory/hash를 직접 다시 읽지는 못했다. 따라서 새 레코드의 원격 필드 자체를 독립 조회했다고 주장하지 않는다. 다만 첫 기기의 성공 export와 peer의 사전 부재·사후 동일 payload 수신으로 이 synthetic 한 행의 Development private CloudKit 첫 로그인 전송·다른 simulator 수신은 확인했다. 원본 `Carve-ACC-B` simulator는 종료 상태로 보존했다. 두 simulator clone은 같은 Development private DB를 공유하므로 sandbox 서버에는 synthetic Genesis 1:31 테스트 row가 존재한다. 이번 작업에서는 이를 삭제하지 않았다.

Device Hub 결과는 자동 결과와 분리한다. 로그인 전 첫 기기에서 2.0.0 Genesis 1:31 sample이 남은 것을 시각적으로 확인했다. 첫 peer 관찰에서는 Genesis 1:31 위치가 화면 밖이라 UI 수신을 확정하지 못했다. 후속 수동 확인에서는 peer clone 앱을 Device Hub에서 다시 열고 화면을 확대했다. Device Hub `Capture Keyboard`를 켠 뒤 `Page_Down`으로 본문을 이동해 Genesis 1:31 필기 한 줄을 확인했다. 손가락 드래그·절 메뉴·장 이동·필기 입력은 사용하지 않았고 확인 뒤 키보드 전달을 껐다. 이 관찰은 자동화 테스트 결과가 아니다. 앱 종료 뒤 live peer SQLite를 읽기 전용으로 검사해 `integrity_check=ok`, drawing/metadata 각 21행, Genesis 1:31 payload 300B와 동일 SHA-256, upload/cloud-delete/local-delete pending 합계 0을 재확인했다. 이번 왕복에는 `xcodebuild test`를 실행하지 않았다. 같은 후보의 좁은 `LegacyRowLinkageReaderTesting` + `DrawingStoreOwnershipProofTesting` CLI 회귀는 직전 기록대로 37/37 통과이며, Xcode 27 여섯 runtime 전체 회귀도 별도 기록대로 통과했다.

첫 로그인 과정에서 기존 remote row로 보이는 `1-01Genesis.txt.1`, verses `[10, 11, 12]`에 대해 iPadOS 26.5 앱의 single-canvas decode 실패가 앱 로그에 남았다. 읽기 전용 `post-first-login-store/Carve.dev.sqlite`에는 10절 4행·11절 3행·12절 1행, 총 8행이 있었고 모두 22B였다(각 verse 내 payload hash 하나). macOS 27.2 호스트의 PencilKit으로 snapshot의 8개 payload 각각을 `PKDrawing(data:)`에 넣었을 때는 decode 성공·0 strokes였다. 이는 iPadOS 26.5 앱의 실패를 해소하지 않으며, 저장 데이터 손상이나 의도된 빈 drawing 어느 쪽도 단정할 수 없다. 현재 `DrawingCodec.decodeStored`의 `try? PKDrawing(data:)` 경로는 실제 throw 사유를 숨긴다. 앱은 이 행들을 표시·활성 편집에서 제외해 다음 편집을 새 행으로 분리하며, 이 시험에서는 원본 행을 편집하거나 덮어쓰지 않았다. 플랫폼별 decode 차이의 원인·사용자 영향은 미해결이고 별도 표시·복구 점검이 필요하다. 앱 전용 전체 로그는 `/private/tmp/carve-x27-first-login-preflight-20260925/candidate-carveapp-full.log`, 읽기 전용 SQLite snapshot은 `post-first-login-store/`, peer launch 결과는 `peer-first-receive-launch.log`·`.exit`다.

이번 결과는 iOS 26.5에서 만든 **한 개의 synthetic, 무계정 1.3.0 V3 행**의 Xcode 27 2.0.0 first-login export 및 다른 simulator 수신 경로를 확인한 것이다. historical 1.3.0 bundle을 Xcode 27에서 재빌드한 검증, peer physical iPad 표시, 새 sample의 독립 read-only server inventory, iOS 18 marker 의미/allowlist, iOS 17 ownership·iOS 17.0 직접 회귀, widget/history/N-Canvas 왕복, production CloudKit, App Store 배포 서명 Archive·Production entitlement·TestFlight는 여전히 미완료다. 전체 출시 판정은 **NO-GO**다.

### Xcode 27 generic iOS Release Archive 서명 사전 검증 (2026-09-25)

실행 환경은 macOS `27.2 (26B5086k)`, 선택된 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`이다. `Carve.xcodeproj`가 없어서 기존 manifest·dependency 설정은 바꾸지 않고 `mise x -- tuist generate --no-open`으로 workspace와 프로젝트를 생성했다(exit 0). Archive는 iOS SDK `27.0`의 generic iOS destination으로 수행했으며 simulator runtime과 iPhone destination을 사용하지 않았다.

Archive action의 Release build settings를 읽기 전용 조회했다. `CODE_SIGNING_ALLOWED=YES`, `CODE_SIGNING_REQUIRED=YES`, `CODE_SIGN_STYLE=Automatic`, `CODE_SIGN_IDENTITY=iPhone Developer`, CloudKit/App Group entitlement 파일이 설정돼 있었다. `xcodebuild archive`는 provisioning update 허용 옵션 없이 기존 설정만 사용했다.

```bash
mise x -- tuist generate --no-open
# exit 0; /private/tmp/carve-x27-release-archive-preflight-20260925-tuist-generate-elevated.log

xcodebuild -showBuildSettings -workspace Carve.xcworkspace -scheme CarveApp \
  -configuration Release -destination 'generic/platform=iOS' archive
# exit 0; /private/tmp/carve-x27-release-archive-preflight-20260925-show-archive-settings.log

xcodebuild archive -workspace Carve.xcworkspace -scheme CarveApp -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/carve-x27-release-archive-20260925/Carve.xcarchive \
  -derivedDataPath /private/tmp/carve-x27-release-archive-20260925/DerivedData
# ** ARCHIVE SUCCEEDED **, exit 0

codesign --verify --deep --strict \
  /private/tmp/carve-x27-release-archive-20260925/Carve.xcarchive/Products/Applications/CarveApp.app
# exit 0
```

Archive의 bundle/version은 `kr.co.carve.leetaek`, 2.0.0 (1)이고 서명 검증은 통과했다. 단, 서명 클래스는 Apple Development이며 embedded profile은 `get-task-allow=true`인 Development profile이다. 현재 로컬에는 이 bundle의 Development profile만 있고 Apple Distribution identity 및 App Store profile은 없다. 서명된 app에는 CloudKit entitlement가 있으나 `com.apple.developer.icloud-container-environment`는 설정·서명 결과 모두에 없었다. 따라서 이 Archive는 Release 구성의 generic iOS 컴파일과 Development 서명만 증명하며 App Store 배포 서명·Production CloudKit entitlement·TestFlight 적격성을 증명하지 않는다. `xcodebuild -exportArchive`와 TestFlight upload는 실행하지 않았다. 설정·의존성·서명 프로필은 바꾸지 않았다.

전체 Archive 로그는 `/private/tmp/carve-x27-release-archive-20260925/archive.log`, 읽기 전용 Archive build settings는 `/private/tmp/carve-x27-release-archive-preflight-20260925-show-archive-settings.log`, Tuist 생성 로그는 `/private/tmp/carve-x27-release-archive-preflight-20260925-tuist-generate-elevated.log`다. 서명 inventory는 로컬에서 값 노출 없이 분류했다. 빌드는 성공했으나 Sendable closure, N-Canvas 전용 `undoManager` deprecated use, SwiftLint 파일/타입 길이 경고가 로그에 남았다. 이 로컬 Development Archive 이후에도 배포 서명·entitlement·TestFlight는 NO-GO 게이트다.

### Device Hub 물리 iPad Xcode 27 후보 접근성 확인 (2026-09-25)

Device Hub에서 연결된 iPad mini (A17 Pro) iPadOS `27.2`를 확인했다. 설치된 `새기다`는 TestFlight `2.0.0 (220)`이며 TestFlight의 테스트 안내 화면이 표시됐다. 현재 Xcode 27 로컬 Archive는 `2.0.0 (1)` Apple Development 서명이고 별도 Development profile을 사용한다. TestFlight 안내의 `계속`을 누르지 않았고, 현재 설치 앱을 대체하거나 실행 상태에서 계정·필기·동기화를 조작하지 않았다. Home으로 돌아왔으며 Device Hub 화면 관찰은 자동 테스트가 아니다.

물리 iPad에서 Xcode 27 후보 기능 스모크는 아직 수행하지 않았다. 사용자는 TestFlight 설치본 교체를 승인했지만, 설치 전 서명·CloudKit 환경 사전 점검에서 별도 blocker가 확인됐다. TestFlight `2.0.0 (220)` 화면 관찰은 Xcode 27 후보 검증으로 세지 않는다.

### 물리 iPad 후보 설치 사전 점검 후속 (2026-09-25)

사용자의 TestFlight 설치본 교체 승인을 받은 뒤 `devicectl`로 기기를 읽기 전용 확인했다. 기기는 unlocked, Developer Mode enabled, iPadOS `27.2`이며 연결 transport는 `localNetwork`였다. 설치 앱은 `kr.co.carve.leetaek` `2.0.0 (220)`이었다. Release Archive의 Development profile에는 물리 iPad UDID가 포함돼 있었다. 그러나 Release 구성은 `iCloud.Carve.SwiftData.iCloud` 컨테이너 ID를 사용하고 signed app에서 `com.apple.developer.icloud-container-environment`가 빠져 있다. 따라서 실행 시 Development/Production CloudKit 환경을 이 산출물만으로 단정할 수 없어 Release Archive를 설치·실행하지 않았다.

Production 컨테이너에 접근하지 않는 물리 UI 확인 가능성을 보기 위해 기존 설정을 바꾸지 않고 macOS 27.2 / Xcode 27.0 (27A266a) / Swift 6.4 / iPhoneOS 27.0 SDK에서 기본 Debug 구성을 generic iOS destination으로 빌드했다(시뮬레이터 runtime은 사용하지 않음). Debug 앱 Info.plist는 명시적으로 `iCloud.Carve.SwiftData.iCloud.dev`를 가리켰고, signed app에는 CloudKit service와 두 container ID가 있었으나 environment entitlement는 역시 없었다. Debug provisioning profile은 `get-task-allow=true`, Development·Production environment 허용, 해당 물리 iPad 포함으로 확인됐다. 전체 로그는 `/private/tmp/carve-x27-physical-debug-smoke-20260925/build.log`, 종료 코드는 `build.exit`이며 빌드는 exit 0이다.

```bash
xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/carve-x27-physical-debug-smoke-20260925/DerivedData
# BUILD SUCCEEDED (exit 0)

codesign --verify --deep --strict \
  /private/tmp/carve-x27-physical-debug-smoke-20260925/DerivedData/Build/Products/Debug-iphoneos/CarveApp.app
# CSSMERR_TP_NOT_TRUSTED (exit 1)
```

Debug 앱의 엄격한 서명 검증은 `CSSMERR_TP_NOT_TRUSTED`로 실패했고 상세 서명 표시에서 Authority를 확인할 수 없었다. 서명 검증 완화·우회, profile/identity 갱신, 서명 설정 변경은 하지 않았다. 따라서 승인된 교체는 실행하지 않았고 물리 iPad의 TestFlight 앱은 그대로 남아 있다. 앱을 설치·실행·로그인하지 않아 이 기기에서 앱 컨테이너와 CloudKit 상태 변경도 없었다. 물리 smoke 재개 조건은 기기에서 엄격한 검증을 통과하는 Xcode 27 서명 산출물과 실행 환경이 개발 CloudKit으로 한정됐다는 확인이다. 이 Debug 빌드는 Release 후보 smoke나 자동 테스트 결과로 세지 않는다.

### Xcode Cloud TestFlight build 220의 툴체인 확인 (2026-09-25)

사용자가 기존 Xcode Cloud→TestFlight 배포가 성공했다고 알려 주어 Xcode 27의 Report Navigator에서 기존 결과를 읽기 전용으로 확인했다. `DevelopBranch` workflow의 build `220`은 2026-09-21에 시작했고, Overview에 Xcode `26.6 (17F113)` 및 macOS Tahoe `26.3 (25D125)`가 표시됐다. Build, Test, Archive 작업은 완료로 표시됐으며 각각 30, 115, 30 issues 배지가 있었다. `TestFlight Internal Testing - iOS` 작업은 이 화면을 확인한 시점에 `Running… / In Progress`였다. 별도 `devicectl device info apps` 조회에서 물리 iPad mini (A17 Pro), iPadOS 27.2의 설치 앱이 `2.0.0 (220)`임을 확인했다. 사용자가 TestFlight 배포 성공을 확인했고 해당 빌드가 설치돼 있으나, Xcode Cloud Report의 작업 상태가 종료 상태는 아니어서 UI가 보여 준 실행 단계도 그대로 기록한다.

```bash
xcrun devicectl device info apps \
  --device 00008130-000C24A60C92001C \
  --bundle-id kr.co.carve.leetaek \
  --json-output /private/tmp/carve-x27-testflight-cloud-check-20260925/device-apps.json \
  --log-output /private/tmp/carve-x27-testflight-cloud-check-20260925/device-apps.log
# exit 0; 새기다 2.0.0 (220)
```

일반 sandbox 호출은 CoreDeviceService 초기화 timeout으로 실패했고 위의 읽기 전용 조회는 권한 상승 후 exit 0으로 끝났다. JSON 결과와 진단 로그는 위 경로에 보존했다.

이는 Xcode Cloud 배포 파이프라인 자체의 실패가 아니다. build 220은 Xcode 26.6으로 생성된 기존 TestFlight 앱이고 Xcode 27 후보의 빌드·서명·수동 smoke를 증명하지 않는다. 앞서 실패한 `CSSMERR_TP_NOT_TRUSTED`는 로컬 Xcode 27 Debug 기기용 산출물의 서명 확인 결과이며 Xcode Cloud build 220과는 다른 산출물·실행 환경이다. 이번 Cloud report 조회 중 기기에 앱을 설치·실행하거나 CloudKit을 변경하지 않았다. 따라서 Xcode 27용 물리 후보 smoke는 계속 미실행이고, 로컬 Xcode 27 Development 산출물의 서명 신뢰 및 CloudKit environment blocker도 그대로다.

후속으로 Xcode Cloud Report를 다시 열어도 build 220의 상태는 `Running (3days 22hr 5min)`이고 `TestFlight Internal Testing - iOS`는 `Running… / In Progress`였다. 이는 사용자가 확인한 TestFlight 배포나 기기 설치를 부정하는 실패 신호로 기록하지 않는다. Apple의 workflow reference는 각 workflow에서 임시 빌드 환경의 Xcode·macOS 버전을 선택하도록 설명한다. 따라서 Xcode Cloud→TestFlight 성공은 유효한 배포 이력이지만, 보고서상 Xcode `26.6` 결과를 Xcode `27.0` 후보 자격으로 대체할 수 없다. [Apple Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference). 이번 상태 재확인도 읽기 전용이며 workflow 설정·빌드·TestFlight 상태를 변경하지 않았다.

### Xcode 27 디코드 실패 행 비덮어쓰기 focused 회귀 (2026-09-25)

Genesis 1:10–12의 플랫폼별 PencilKit decode 차이와 직접 관련된 fail-safe를, ACC clone이 아닌 일반 iPadOS 26.5 simulator에서 확인했다. 이 suite는 synthetic 입력만 쓰고 CloudKit client를 사용하지 않는다. 첫 method-level `-only-testing` 호출은 종료 코드 0이었지만 Swift Testing의 실제 선택 결과가 **0 tests**여서 통과 근거에서 제외했다. 두 번째 suite-level filter는 결과 번들의 실제 수를 확인해 9/9로 기록했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=589A8DAB-2D5C-45FC-B76B-C4260FB87C67' \
  -derivedDataPath /private/tmp/carve-x27-undecodable-row-focus-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-undecodable-row-focus-20260925/UndecodableRow.xcresult \
  -only-testing:CarveFeatureTest/SingleCanvasRollbackTesting/undecodableRowIsNotOverwritten \
  -parallel-testing-enabled NO
# exit 0, 실제 선택 0 tests — 무효 시도, 결과 bundle은 보존
```

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=589A8DAB-2D5C-45FC-B76B-C4260FB87C67' \
  -derivedDataPath /private/tmp/carve-x27-undecodable-row-focus-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-undecodable-row-focus-20260925/SingleCanvasRollbackSuite.xcresult \
  -only-testing:CarveFeatureTest/SingleCanvasRollbackTesting \
  -parallel-testing-enabled NO
# iPad mini (A17 Pro), iPadOS 26.5 (23F77): 9 passed, 0 failed, 0 skipped (exit 0)
```

환경은 macOS 27.2, Xcode 27.0 (27A266a), Swift 6.4, Tuist 4.208.0이다. `xcresulttool get test-results summary`에서 `Passed`, 9 passed, failed/skip/expected failure 0, runtime warning 없음과 목적 simulator를 확인했다. 특히 `undecodableRowIsNotOverwritten`는 synthetic decode 실패 행을 활성 행에서 제외하고 다음 편집에 새 row를 만들어 원본 식별 행을 덮지 않는 테스트다. 전체 suite 로그와 종료 코드는 `suite.log`·`suite.exit`, 0건 시도의 로그·종료 코드는 `test.log`·`test.exit`이며 디렉터리는 `/private/tmp/carve-x27-undecodable-row-focus-20260925/`다. 계정 clone이나 CloudKit을 사용하지 않았다. 이 결과는 fail-safe 회귀만 입증하며 Genesis 1:10–12 실제 22B payload의 플랫폼별 decode 원인이나 표시·복구 결과를 설명하지 않는다.

### Genesis 1:10–12 22B payload 직접 PencilKit 재확인 (2026-09-25)

첫 로그인 시 `candidate-carveapp-full.log`의 `ChapterCanvasFeature` 로그는 verses `[10, 11, 12]`를 undecodable로 표시했다. 이 현상이 원시 `PKDrawing(data:)` 입력에서 재현되는지 확인하기 위해, ACC clone은 수정하지 않고 앞서 보존된 `post-first-login-store/Carve.dev.sqlite`의 **복사본**에서 여덟 `ZLINEDATA` 값을 읽었다. 10절 4행, 11절 3행, 12절 1행이 모두 22B였고 여덟 값의 SHA-256은 `fd34c90bb64fe7516efce8a76fe2ece33b9821935183664dfda18c84b31c1d2f`로 같았다. 원본 DB·행·CloudKit 레코드는 이 검사에서 쓰지 않았다.

작은 iPad-only Tuist 앱을 `/private/tmp/carve-x27-22b-decode-audit-20260925/harness`에 만들고 같은 payload 파일을 앱 리소스로 포함했다. 앱은 각 값을 `PKDrawing(data:)`로 열고 byte count, SHA-256, stroke count 또는 NSError domain/code만 임시 Documents 파일에 남겼다. 앱에 CloudKit entitlement나 네트워크 동작은 없었다. macOS 호스트, iPadOS 26.5 새 iPad mini (A17 Pro) simulator, iPadOS 27.0 iPad mini (A17 Pro) simulator에서 각 3개 verse payload가 모두 **decode 성공·0 strokes**였다. 따라서 현재 확인된 직접 PencilKit 호출에서는 플랫폼별 decode 실패가 재현되지 않았고, 이 표본은 세 런타임에서 유효한 빈 drawing으로 해석됐다.

실행 환경은 macOS `27.2 (26B5086k)`, 선택된 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`, iOS Simulator SDK `27.0`이다. iPadOS 26.5 runtime은 `23F77`, iPadOS 27.0 대상은 `24A434`였다. Tuist 생성은 기본 세션 경로와 Swift module cache 권한 문제로 첫 시도들이 실패했다. 공유 설정을 변경하지 않고, 임시 Tuist state와 `.mise.toml`의 일회성 trust 경로를 지정해 생성했다. CoreSimulator의 user log/device set 접근은 sandbox에서 실패해 분리된 26.5 simulator의 생성·부팅·설치·실행과 27.0 simulator 실행은 권한 상승으로 수행했다.

```bash
XDG_STATE_HOME=/private/tmp/carve-x27-22b-decode-audit-20260925/tuist-state \
MISE_TRUSTED_CONFIG_PATHS=/Users/leetaek/Carve/.mise.toml \
MISE_DATA_DIR=/Users/leetaek/.local/share/mise \
mise x -- tuist generate \
  --path /private/tmp/carve-x27-22b-decode-audit-20260925/harness --no-open
# exit 0

xcodebuild -project /private/tmp/carve-x27-22b-decode-audit-20260925/harness/CarveDrawingDecodeProbe.xcodeproj \
  -scheme CarveDrawingDecodeProbe -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/carve-x27-22b-decode-audit-20260925/DerivedData build
# BUILD SUCCEEDED, exit 0

swift -module-cache-path /private/tmp/carve-x27-22b-decode-audit-20260925/clang-module-cache \
  /private/tmp/carve-x27-22b-decode-audit-20260925/macOS-decode.swift
# macOS 27.2: verse 10–12 각각 bytes=22, 위 SHA-256, decode=success, strokes=0, exit 0

xcrun simctl create Carve-22B-Decode-20260925 \
  com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
# D4E5AA55-2C2D-4E04-AE73-51D6D14E5105; iPad 전용 임시 simulator
xcrun simctl boot D4E5AA55-2C2D-4E04-AE73-51D6D14E5105
xcrun simctl bootstatus D4E5AA55-2C2D-4E04-AE73-51D6D14E5105 -b
xcrun simctl install D4E5AA55-2C2D-4E04-AE73-51D6D14E5105 \
  /private/tmp/carve-x27-22b-decode-audit-20260925/DerivedData/Build/Products/Debug-iphonesimulator/CarveDrawingDecodeProbe.app
xcrun simctl launch D4E5AA55-2C2D-4E04-AE73-51D6D14E5105 kr.co.carve.pencilkitdecodeprobe
# iPad mini (A17 Pro), iPadOS 26.5 (23F77): 3/3 decode success, strokes=0

xcrun simctl boot C72A6CC6-4E3C-4822-BED1-9D76F8542D6B
xcrun simctl bootstatus C72A6CC6-4E3C-4822-BED1-9D76F8542D6B -b
xcrun simctl install C72A6CC6-4E3C-4822-BED1-9D76F8542D6B \
  /private/tmp/carve-x27-22b-decode-audit-20260925/DerivedData/Build/Products/Debug-iphonesimulator/CarveDrawingDecodeProbe.app
xcrun simctl launch C72A6CC6-4E3C-4822-BED1-9D76F8542D6B kr.co.carve.pencilkitdecodeprobe
# iPad mini (A17 Pro), iPadOS 27.0 (24A434): 3/3 decode success, strokes=0
```

전체 Tuist·build·host decode·simulator boot/install/launch 기록과 결과는 `/private/tmp/carve-x27-22b-decode-audit-20260925/`에 있다. `harness/Project.swift`, `harness/Sources/ProbeApp.swift`, `macOS-decode.swift`, `ios-simulator-build.log`, `macOS-decode.log`, `ios26.5-decode.log`, `ios27.0-decode.log`, 각 `sim-*.log` 및 `tuist-generate-elevated.log`를 보존했다. 신규 26.5 simulator는 삭제했고, 기존 27.0 test simulator에서는 probe 앱만 제거한 뒤 shutdown했다. 직접 재현은 `DrawingCodec.compose`를 호출하지 않은 원시 PencilKit API 검사이지 Carve 앱의 화면 검증이나 CloudKit 시험이 아니다. 따라서 이전 앱 로그의 undecodable 경고와 이후 직접 API 성공 사이의 불일치는 남는다. 실행 중 앱이 선택한 snapshot과 저장 후 DB payload가 같은 값이었는지, 해당 compose 시점의 앱 상태가 무엇이었는지는 관측하지 못했다. 실제 DrawingCodec 통합·표시 결과를 성공으로 간주하지 않으며 데이터 변경이나 자동 회귀를 수행하지 않았다. Xcode Cloud/TestFlight·Production CloudKit·서명 게이트에는 영향이 없으므로 전체 출시 판정은 **NO-GO**다.

### 동일 22B payload의 `DrawingCodec.compose` focused 확인 (2026-09-25)

위 raw PencilKit 검사와 앱 로그 사이를 좁히기 위해, 보존된 `verse-10.bin`을 읽는 임시 테스트 하나를 기존 `DrawingCodecTesting` suite에 추가해 Xcode 27에서 iPadOS 17.5·18.6·26.5·27.0 simulator로 각각 실행했다. 각 목적지는 일반 iPad mini simulator였고 ACC/오프라인 migration clone을 쓰지 않았다. 테스트는 입력 bytes를 외부 저장소에 쓰지 않고 `DrawingCodec.compose`가 `undecodableVerses`를 비우는지, 해당 row를 `activeRowIDs`에 유지하는지, 결과 drawing이 0 strokes인지 확인했다. 네 runtime 모두 **각 13/13 통과, xcodebuild exit 0**이다. 임시 테스트 코드는 실행 직후 제거했고, 원본 테스트 파일 backup과 현재 파일의 차이가 없으며 저장소에 코드 변경을 남기지 않았다. CloudKit client를 호출하지 않았다.

실행 환경은 macOS `27.2 (26B5086k)`, 기본 선택 Xcode `27.0 (27A266a)`, Swift `6.4 (6.4.0.34.1)`, Tuist `4.208.0`, iOS Simulator SDK `27.0`이다. 네 대상은 iPad mini (6th generation) iPadOS `17.5 (21F79)`, iPad mini (A17 Pro) iPadOS `18.6 (22G86)`, iPad mini (A17 Pro) iPadOS `26.5 (23F77)`, iPad mini (A17 Pro) iPadOS `27.0 (24A434)`다. `xcode-select -p`, `xcodebuild -version`, `swift --version`, `mise x -- tuist version`, `xcrun simctl list runtimes`, `xcrun simctl list devices available`를 확인했다. Tuist version은 읽기 전용 확인도 `/private/tmp/carve-x27-compose-probe-20260925/state`의 임시 XDG 상태 경로로 실행했다.

```bash
XDG_STATE_HOME=/private/tmp/carve-x27-compose-probe-20260925/state \
MISE_TRUSTED_CONFIG_PATHS=/Users/leetaek/Carve \
mise x -- tuist generate --no-open
# 권한 상승 실행, exit 0; tuist-generate-elevated.log / tuist-generate-elevated.exit

xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=0347221E-08F5-48C9-9F8E-6D7995C25D9F' \
  -derivedDataPath /private/tmp/carve-x27-compose-probe-20260925/WorkspaceDerivedData \
  -resultBundlePath /private/tmp/carve-x27-compose-probe-20260925/compose-22b-ios17.5.xcresult \
  -parallel-testing-enabled NO -only-testing:CarveFeatureTest/DrawingCodecTesting
# iPad mini (6th generation), iPadOS 17.5 (21F79): 13/13, exit 0

xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-x27-compose-probe-20260925/WorkspaceDerivedData \
  -resultBundlePath /private/tmp/carve-x27-compose-probe-20260925/compose-22b-ios18.6.xcresult \
  -parallel-testing-enabled NO -only-testing:CarveFeatureTest/DrawingCodecTesting
# iPad mini (A17 Pro), iPadOS 18.6 (22G86): 13/13, exit 0

xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=589A8DAB-2D5C-45FC-B76B-C4260FB87C67' \
  -derivedDataPath /private/tmp/carve-x27-compose-probe-20260925/WorkspaceDerivedData \
  -resultBundlePath /private/tmp/carve-x27-compose-probe-20260925/compose-22b-workspace.xcresult \
  -parallel-testing-enabled NO -only-testing:CarveFeatureTest/DrawingCodecTesting
# iPad mini (A17 Pro), iPadOS 26.5 (23F77): 13/13, exit 0

xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-x27-compose-probe-20260925/WorkspaceDerivedData \
  -resultBundlePath /private/tmp/carve-x27-compose-probe-20260925/compose-22b-ios27.0.xcresult \
  -parallel-testing-enabled NO -only-testing:CarveFeatureTest/DrawingCodecTesting
# iPad mini (A17 Pro), iPadOS 27.0 (24A434): 13/13, exit 0
```

단독 `CarveFeature.xcodeproj`로 같은 suite를 먼저 실행한 시도는 `Dependencies`, `PerceptionCore`, `IssueReporting`, `ConcurrencyExtras`, `CustomDump`, `IdentifiedCollections` 모듈 해석 오류로 테스트 전 build 단계에서 중단됐다. 이를 test 실패로 세지 않았고, Tuist workspace 경로로 다시 실행했다. sandbox에서는 workspace listing 중 CoreSimulator/Xcode 사용자 로그 경로 접근이 막혀 exit 66이었으며 권한 상승 read-only `xcodebuild -list -workspace Carve.xcworkspace`는 exit 0으로 scheme을 확인했다. 전체 생성·실패 시도·성공 실행 로그와 exit 파일은 `/private/tmp/carve-x27-compose-probe-20260925/`에 보존했다.

동일 22B payload의 `PKDrawing(data:)`와 `DrawingCodec.compose`는 iPadOS 17.5·18.6·26.5·27.0에서 모두 성공했다. 최초 앱 경고가 발생한 시점에 SwiftData repository가 넘긴 `snapshot.lineData`가 이 보존 snapshot과 동일했는지는 보지 못했다. 앱 내부 합성 입력의 byte count/hash와 결과를 읽기 전용 clone 실행에서 관찰하기 전에는 최초 warning 원인을 확정하거나 사용자 화면 영향을 닫지 않는다. 이 확인은 iOS 18 marker, iOS 17.0 ownership proof, Production CloudKit, Distribution 서명·TestFlight 게이트를 대체하지 않아 출시 판정은 계속 **NO-GO**다.

### Genesis 1:31 synthetic row의 Development CloudKit 독립 inventory 시도 (2026-09-25)

첫 로그인 synthetic 검증에서 업로드·peer 수신은 확인했지만 독립 Development server inventory와 row-name hash를 수집하지 못했다. 이를 읽기 전용 `cktool` query로 보완하려 했으나 두 번 모두 요청 전 로컬 keychain token 조회에서 멈췄다. 기존 ACC/Xcode iCloud 로그인만으로 `cktool` 사용자 token은 생성되지 않았다.

```bash
xcrun cktool query-records \
  --team-id H4MSW7FUBB \
  --container-id iCloud.Carve.SwiftData.iCloud.dev \
  --environment development \
  --database-type private \
  --zone-name com.apple.coredata.cloudkit.zone \
  --record-type CD_BibleDrawing \
  --requested-fields ___recordID \
  --limit 200
# Error: Could not read token from keychain with status: -50
```

초기 시도는 서버에 query가 도달하기 전에 Keychain에서 멈췄고 CloudKit 데이터 변경은 없었다. 사용자가 target simulator에 로그인된 계정으로 User token을 발급·등록했다고 확인한 뒤 2026-09-25 같은 read-only query를 두 번 재시도했다. 기본 sandbox 호출은 Keychain 조회 `status: -50`으로 종료됐고, 승인된 권한 있는 CLI 재시도는 Keychain 단계 뒤 CloudKit의 `authorization-failed`로 종료됐다. 어느 쪽도 레코드를 반환하지 않았으며 CloudKit 데이터 생성·수정·삭제는 없었다. 따라서 token이 CloudKit에서 받아들여지는지, Console의 Act As 계정·container context·token 유효기간이 맞는지는 확인되지 않았다. 원문 token은 출력·로그·문서에 저장하지 않았다. 전체 로그와 종료 코드는 `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/remote-query-after-correct-account-token.log`, `.exit`, `remote-query-keychain-access-retry.log`, `.exit`에 있다. 다음 단계는 CloudKit Console에서 Carve Development container를 선택한 상태로 `Act As iCloud Account` banner가 ACC target account를 가리키는지 확인하고, 해당 사용자용 fresh User token을 Keychain에 다시 저장하는 것이다. token이 CloudKit에서 승인되면 Development private-zone query를 재개하며 Production database는 조회하지 않는다. [Apple cktool guide](https://developer.apple.com/icloud/ck-tool/)는 User token이 private database 접근에 쓰이고 짧은 유효기간으로 재인증이 필요할 수 있음을 설명하며, [CloudKit Console의 Act As 기능](https://developer.apple.com/videos/play/wwdc2022/10115/)은 이후 query의 계정 관점을 바꾼다고 설명한다.

사용자는 이번 token 발급에 사용한 계정이 개발자 Apple Account가 아니라 App Store Connect에서 만든 Sandbox Apple Account라고 추가 확인했다. Apple 문서상 이 Sandbox 계정은 앱 내 구입·Apple Pay 테스트용이고, CloudKit private database는 기기에 실제 iCloud account가 연결돼 있어야 접근할 수 있다 ([Sandbox 테스트 범위](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox), [CloudKit private database 요건](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)). 따라서 해당 Sandbox Apple Account에서 발급된 token은 CloudKit 사용자 inventory 증거로 사용할 수 없다. 앞선 first-login synthetic upload에서 실제 iCloud identity가 무엇이었는지는 앱 로그·비식별 기록으로 확인되지 않았다. 기존 simulator 계정을 바꾸기 전에 업로드 당시 `Settings > Apple Account`의 실제 iCloud 로그인 계정을 확인한다. 새 검증은 전용 iCloud test account를 우선 사용하고, 개인 개발자 iCloud 계정은 그 private Development DB와 기타 iCloud 서비스에 영향을 줄 수 있음을 사용자가 확인한 뒤에만 선택한다. ASC Sandbox Apple Account를 CloudKit identity와 혼동하지 않는다.

사용자가 `Carve-X27-FirstLogin-20260925` (iPadOS 26.5, UDID `7284FDE5-6F95-4CC6-8EE6-75A794009F0F`)에 iCloud 계정을 로그인하고 User token을 등록했다고 알린 뒤 같은 private-zone `CD_BibleDrawing` read-only inventory query를 실행했다. 기본 sandbox 실행은 Keychain 접근 때문에 실패했지만 권한 있는 CLI 호출은 exit 0으로 끝나 token authorization을 통과했다. 응답은 `records: []`였다. 로그 `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/remote-query-after-icloud-account-login.log`, exit `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/remote-query-after-icloud-account-login.exit`에 있다. 이는 해당 User token·Development container·private zone·record type 조합에서 레코드가 반환되지 않았다는 뜻이다. Genesis 1:31 업로드 당시 실제 iCloud identity·환경·zone이 현재 쿼리와 같았는지 미확인이라, 표본이 업로드되지 않았거나 CloudKit 데이터가 없다고 확대 해석하지 않는다. 이번 실행은 record ID 목록을 받지 못했으며 CloudKit 데이터 변경은 없었다.

zone mismatch 가능성만 확인하기 위해 같은 `CD_BibleDrawing` record type을 Development private DB의 `_defaultZone`에서도 조회했다. 이 query도 exit 0, `records: []`였으며 결과·종료 코드는 `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/remote-query-default-zone-after-icloud-account-login.log`와 `.exit`에 있다. 확인 범위는 두 zone의 해당 record type뿐이다. 다른 record type·환경·사용자·production DB는 조회하지 않았다.

### 남은 게이트 사전 점검 및 22B 전후 snapshot 비교 (2026-09-25)

이번 점검 전 `git status --short --branch`와 문서 diff를 확인했다. 브랜치는 `codex/2-0-0-migration-sync-release`이며 기존 미커밋 변경은 없었다. Xcode 27/macOS 27.2 기준은 그대로 두고 환경을 다시 조회했다.

| 명령 | 결과 |
|---|---|
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| `xcodebuild -version` | Xcode `27.0 (27A266a)` |
| `swift --version` | Swift `6.4 (swiftlang-6.4.0.34.1)`, macOS `27.2` target |
| `mise x -- tuist version` | Tuist `4.208.0` |
| `xcrun simctl list runtimes` | 조회 성공. iOS 17.5·18.6·26.2·26.4·26.5·27.0이 설치됨. 27.0 runtime은 `24A5370g`와 `24A434` 두 항목이며, 현재 기기가 나열된 것은 `24A434`; iOS 17.0은 없음 |
| `xcrun simctl list devices available` | 조회 성공. 실행 중인 iPadOS 18.6·26.5·27.0 기기 포함 |
| `xcodebuild -showsdks` | iOS와 iOS Simulator SDK `27.0` 확인 |

iOS 17.0은 현재 직접 회귀 대상이 없다. 설치된 iOS 17.5 전체 회귀를 17.0 결과로 확대하지 않는다. 이전 runtime이 Xcode Components catalog에 제공되는지는 아직 확인하지 않았으며, 이번에는 다운로드·설치를 시도하지 않았다. simulator 회귀 자체에는 iCloud 로그인이 필요하지 않다. iOS 17 ownership proof를 추후 수행하려면 새 simulator에서 기존 ACC와 같은 sandbox 계정 로그인 및 synthetic Development CloudKit 표본이 필요하다.

Xcode 27 계정 로그인 이후 로컬 서명 자격을 읽기 전용으로 다시 확인했다. `security find-identity -v -p codesigning`은 exit 0, `0 valid identities found`였다. Xcode profile store의 3개 CMS payload를 로컬 임시 경로에 풀어 bundle/entitlement 조건을 분류했을 때 Carve bundle의 App Store profile과 Production CloudKit entitlement가 각각 0개였다. payload 내용 분류는 서명 검증이나 서명 설정 변경이 아니다. 이전 Xcode 27 Development Archive 결과를 현재 로컬 배포 자격으로 간주하지 않으며, 새 Distribution 자격·Production 환경 entitlement·Xcode 27 후보 TestFlight가 확보되기 전 물리 후보 앱을 설치하지 않는다.

앱 경고 원인을 좁히기 위해 `/private/tmp/carve-x27-first-login-preflight-20260925/`의 보존 SQLite 복사본을 Python 표준 `sqlite3`로 `mode=ro&immutable=1` 연결해 읽었다. `source-store`, `post-first-login-store`, `peer-before-receive-store`, `peer-after-receive-store`, `peer-post-observation-store` 모두 Genesis 1:10–12의 총 8행(10절 4행, 11절 3행, 12절 1행)이 남아 있었다. 모든 payload가 22B이며 SHA-256은 `fd34c90bb64fe7516efce8a76fe2ece33b9821935183664dfda18c84b31c1d2f`로 같았다. DB 파일은 수정하지 않았다.

보존된 앱 로그 `/private/tmp/carve-x27-first-login-preflight-20260925/candidate-carveapp-full.log`에는 2026-09-25 13:02:25.437에 `verses=[10, 11, 12]` undecodable 경고가 있다. source/post-login/peer snapshot의 payload가 동일하고, 동일 22B 값의 raw PencilKit 및 `DrawingCodec.compose` focused 확인도 성공했지만 당시 메모리의 대표 snapshot `lineData` hash와 `PKDrawing(data:)` 오류는 로그에 없다. 따라서 앱 warning의 원인은 여전히 미확정이고 표시·사용자 영향도 닫지 않는다. 새 빌드, 앱 재실행, CloudKit 조회 또는 행 쓰기는 이번 비교에서 하지 않았다.

별도 Development private-zone server inventory는 여전히 미실행이다. ACC 및 Xcode 27 로그인과 다른 `cktool` User token이 필요하다. CloudKit Console에서 만든 token을 사용자가 터미널의 `xcrun cktool save-token --type user --method keychain` 프롬프트에 직접 입력해 Keychain에 저장해야 한다. token이나 계정 비밀번호를 대화에 보내지 않는다. token이 저장되면 Genesis 1:31 synthetic row에 한정해 Development private DB를 읽기 전용 조회한다.

이번 사전 점검·스냅샷 비교는 자동 빌드나 테스트를 실행하지 않았다. Xcode 27 전체 회귀 및 네 runtime의 22B focused 결과는 별도 위 절에 기록한 결과 그대로다. iOS 18 marker 의미·proof, iOS 17.0 직접 회귀·ownership, 31 표본의 독립 server inventory, Production CloudKit, Distribution 서명 Archive/export·Production entitlement·TestFlight와 물리 후보 smoke는 미완료여서 출시 판정은 **NO-GO**다.

### 병렬 남은 게이트 점검 및 iOS 18 simulator clone 격리 실패 (2026-09-25)

작업 시작 시 `git status --short --branch`와 diff는 clean이었다. 다시 확인한 기본 환경은 macOS `27.2`, `/Applications/Xcode.app/Contents/Developer`의 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`이다. `xcrun simctl list runtimes`와 `list devices available`는 조회됐다. iOS 27 runtime 두 항목은 같은 runtime identifier를 쓰지만 build가 `24A5370g`와 `24A434`로 다르다.

이번에 필요한 생성·scheme 확인 명령은 성공했다. 자동 빌드나 테스트는 새로 실행하지 않았다.

```bash
mise x -- tuist generate --no-open
# exit 0; /private/tmp/carve-x27-remaining-gates-20260925/tuist-generate-elevated.log

xcodebuild -list -workspace Carve.xcworkspace
# read-only scheme listing exit 0; /private/tmp/carve-x27-remaining-gates-20260925/xcodebuild-list.log
```

두 iOS 27 runtime 가운데 `24A5370g`를 검증하려고 그 runtime root로 전용 iPad mini simulator를 만들었지만, 부팅 후 runtime build 환경은 `24A434`를 반환했다. 동일 identifier만으로는 런타임을 구별할 수 없어서 테스트를 시작하지 않았다. 이번에 만든 simulator는 종료·삭제했고 사후 목록에서 사라진 것을 확인했다. 생성·부팅·정리 로그는 `/private/tmp/carve-x27-alt-runtime-20260925/`에 있다. 따라서 새 iOS 27 회귀 결과는 없다.

iOS 18.6 무계정 marker 비교를 위해 기존 `Carve-X27-iOS18.6-V3-Offline-20260925`의 앱 컨테이너를 두 번 복사해 hash 안정성을 확인하고, 원본을 정상 종료한 뒤 전용 clone을 생성했다. 원본과 clone의 Accounts3에는 계정·활성·인증 행이 없었다. clone 실행 전에는 원본 95개 파일의 종료 snapshot과 clone의 별도 data root가 일치했고, clone은 계정 없음 상태였다. 그러나 clone의 `simctl appinfo/get_app_container`가 원본 경로를 반환했고, clone UDID로 시작한 앱의 Core Data CloudKit setup 로그도 원본 UDID의 `Carve.dev.sqlite` URL을 가리켰다. 소스 코드 감사에서는 저장소의 절대 경로 하드코딩을 찾지 못했다. 앱 코드는 `URL.applicationSupportDirectory`에서 저장소 URL을 런타임에 구성하므로, 경로 혼선 원인은 소스 코드가 아니라 복제된 simulator/CoreData 상태에 있을 가능성이 있으나 아직 미확정이다.

clone에서 앱을 한 번 실행한 뒤 원본 DB의 `ANSCKEVENT`가 7건에서 8건으로 늘었다. 새 이벤트는 모두 `NSCocoaErrorDomain 134400` (`CKAccountStatusNoAccount`) setup 실패였다. export operation·exported object·record metadata는 계속 0개였고, Genesis 1:1의 298B payload SHA-256 `07876e8b1910039124914f5c44b9619a90b8ad488a08500bdfa6abc07762c3d6`, marker의 SQLite integer 값 `1`, 단일 drawing 행, integrity check는 유지됐다. clone의 DB는 실행 전후 byte-identical이었다. 앱 데이터 컨테이너 나머지 파일 일부도 원본에서 변경돼 이 결과를 clone 격리 또는 offline-network proof로 인정하지 않는다. 로그인은 하지 않았고 CloudKit 성공·원격 쓰기는 관찰되지 않았다.

증거를 보존한 뒤 두 simulator를 종료했다. CoreSimulatorService 연결이 간헐적으로 끊겨 마지막 `simctl list devices available` 재확인은 실패했지만, 종료 성공 명령과 `/private/tmp/carve-x27-ios18-marker-offline-20260925/devices-after-safety-shutdown.log`에는 두 기기가 Shutdown으로 남아 있다. 원본 side effect로부터 계정 없는 sample을 복구하기 위해 실행 후 원본 app container 전체를 `/private/tmp/carve-x27-ios18-marker-offline-20260925/source-app-data-postlaunch-preserved/`로 보존하고, 95개 파일 종료 전 snapshot `original-app-data-pre-shutdown/`을 같은 app-container UUID 경로에 복원했다. `diff -qr`가 exit 0으로 두 95-file tree의 내용이 같은 것을 확인했고 임시 sibling 디렉터리는 정리했다. 복원은 app-local 파일만 대상으로 했고 CloudKit에는 접근하지 않았다. 전체 비교·DB 보고서·앱 로그는 `/private/tmp/carve-x27-ios18-marker-offline-20260925/`에 남아 있다. marker 의미와 iOS 18 ownership proof는 여전히 미확정이다.

보존된 historical `Carve-2.0.0-test-legacy` 앱 번들은 읽기 전용 검증에서 `1.3.0 (1)`, iOS 17.0 minimum, Xcode 26.3 / iOS Simulator SDK 26.2 산출물이며 `codesign --verify --deep --strict`가 통과했다. ad-hoc 서명이고 Team ID·프로비저닝 profile·CloudKit entitlement가 비어 있으므로 전용 iPadOS 26.5에서 local install/update/migration 입력으로는 쓸 수 있지만 live CloudKit pending export proof에는 사용할 수 없다. 감사 결과는 `/private/tmp/carve-x27-historical-130-artifact-audit-20260925/read-only-audit-corrected.log`에 있다.

별도 pending/local-only export gate의 조사 결과, online 상태에서 합성 행을 쓰고 곧바로 update하는 방식은 Core Data export가 먼저 끝날 수 있어 재현성이 없다. 실행에는 해당 simulator 하나에만 적용되는 신뢰할 수 있는 100% 양방향 network loss가 필요하다. 2026-09-25 Xcode 27 Device Hub의 Controls·More Actions·inspector와 Simulator Developer 설정을 직접 확인했지만 선택 simulator용 네트워크 차단/Network Link Conditioner 제어는 찾지 못했다. 과거 Xcode의 Device Conditions 자료는 네트워크 shaping을 설명하나, 현재 Xcode 27에서 확실한 양방향 차단이 가능하다는 증거가 아니다. Mac 전체 network disconnect는 다른 앱 통신에도 영향을 주므로 사용자의 명시 승인을 받기 전에는 하지 않는다. 확인된 차단 수단이 생긴 뒤 Core Data network error 및 `ZNEEDSUPLOAD=1`을 함께 보며, 같은 simulator에서 old app의 오프라인 합성 행 → Xcode 27 Debug 덮어 설치 → pending 유지 → 네트워크 복구 뒤 Development export·peer receive 순서로 진행한다. 새 simulator의 같은 ACC sandbox 로그인과, CloudKit Console User token을 통한 독립 Development server baseline/final query가 필요하다. 현재 historical artifact에는 Development CloudKit entitlement가 없고 simulator 전용 차단 수단 및 token도 확인되지 않아 이 gate는 실행하지 않았다. 이 절차 설계는 시뮬레이터·계정·CloudKit 데이터에 접근하지 않았다.

이번 단계에서 완료된 것은 문서 밖 환경·아티팩트 사전 점검과 원본 app-local snapshot 복구뿐이다. 테스트는 미실행이며 기존 Xcode 27 통과 결과를 새 gate의 통과로 확대하지 않는다. iOS 18 marker/ownership, iOS 17.0 직접 회귀, Development server inventory, pending export update, Production CloudKit, Distribution 서명 Archive/export·TestFlight 및 물리 후보 smoke는 미완료여서 출시 **NO-GO**를 유지한다.

### Xcode 27 직접 V3 로컬 마이그레이션 회귀 (2026-09-25)

테스트 시작 전 tracked worktree는 clean이었다. 기본 선택 Xcode는 `/Applications/Xcode.app/Contents/Developer`의 `27.0 (27A266a)`, macOS `27.2`, Swift `6.4 (6.4.0.34.1)`, Tuist `4.208.0`이다. `Carve-Workspace`의 Debug scheme에서 iPad mini (A17 Pro), iOS `18.6 (22G86)`, UDID `7E95B700-3976-42D7-BF85-BCAF028B7605`를 사용했다. SDK는 iOS Simulator `27.0`이다. 모든 명령은 CLI `xcodebuild test`, `-parallel-testing-enabled NO`로 실행했다. Xcode 27 전체 회귀를 대신하려는 시험이 아니라 V3 local migration 경로에 집중한 추가 증거다.

| suite | 결과 | 목적 |
|---|---:|---|
| `DomainTest/LegacyRowLinkageReaderTesting` | 31/31 | iOS 18.6의 미지원 migration marker를 fail-closed로 유지 |
| `DomainTest/DrawingStoreOwnershipProofTesting` | 6/6 | 지원되지 않는 OS에서 ownership proof가 열리지 않는지 확인 |
| `DomainTest/MigrationSyncReleaseTesting` | 5/5 | 무계정 V3 행·별도 초안·보존 실패 경계를 확인 |
| `CarveFeatureTest/LegacyStoreMigrationTesting` | 3/3 | V3 임시 store → 현재 schema → repository → legacy 필기 합성·편집 왕복 |
| `DomainTest/DrawingSchemaV4MigrationTesting` + `CarveFeatureTest/DrawingCodecLegacyMigrationTesting` | 14/14 | V3→V4 행·blob 보존과 legacy 좌표 배치 확인 |

다섯 실행 묶음은 총 **59/59 통과**, failed·skip·expected failure 0, `xcodebuild` 종료 코드 0이다. 실제 V3 end-to-end suite의 xcresult는 `Passed`, 3/3이고 runtimeWarnings 0이다. 인접 두 suite는 11+3으로 14/14이며 xcresult runtimeWarnings 0이다. 앞서 실행한 첫 세 suite 로그·결과와 두 migration 실행 전체 로그·종료 파일은 각각 `/private/tmp/carve-x27-marker-focused-20260925/`와 `/private/tmp/carve-x27-legacy-store-migration-20260925/`에 있다.

직접 migration suite는 테스트 전용 임시 SQLite에 synthetic V3 행과 PencilKit blob을 만들고 제거한다. `CarveFeatureTest`는 CarveApp이 아닌 unit-test target이며 앱을 설치·실행하지 않았다. ACC 저장소, iCloud 로그인, CloudKit 서버, 네트워크 데이터는 사용하지 않았다. 따라서 이 결과는 실제 1.3.0 앱 번들 업데이트·iOS 18 marker 해석·계정 소유 proof를 통과시킨 것이 아니다.

V3 store를 여는 두 migration suite의 전체 로그에는 CoreData가 `NSManagedObjectModel` checksum을 아직 editable인 시점에 조회했다는 `[error]` 진단이 반복된다. 두 xcresult summary는 runtimeWarnings 0이고 관련 테스트는 통과했지만, 이 진단의 기원·제품 영향은 이번 실행에서 따로 분류하지 않았다. 경고를 무시 가능한 것으로 승격하지 않고 후속 분석 항목으로 남긴다. 전체 로그의 Swift/TCA deprecated warning 및 AppIntents metadata skip은 별도로 출력됐으며 빌드·시험 실패는 없었다.

대표 실행 명령은 다음과 같다. 다른 두 `DomainTest` suite도 같은 workspace, scheme, destination, configuration, parallelism으로 각각 `-only-testing`을 지정했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/carve-x27-legacy-store-migration-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-legacy-store-migration-20260925/LegacyStoreMigrationTesting.xcresult \
  -only-testing:CarveFeatureTest/LegacyStoreMigrationTesting
# 3/3 passed, exit 0; 전체 로그 xcodebuild.log, 종료 코드 xcodebuild.exit

xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/carve-x27-legacy-store-migration-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-legacy-store-migration-20260925/AdjacentMigrationSuites.xcresult \
  -only-testing:DomainTest/DrawingSchemaV4MigrationTesting \
  -only-testing:CarveFeatureTest/DrawingCodecLegacyMigrationTesting
# 14/14 passed, exit 0; 전체 로그 adjacent-suites.log, 종료 코드 adjacent-suites.exit
```

직접 simulator 앱 업데이트는 별도 전용 기기에서 아직 실행하지 않았다. Carve 시작 시 Firebase Analytics가 설정되고 저장소에 수집 중단 launch switch가 없다. `simctl`에는 per-simulator 네트워크 차단 명령이 없고, 2026-09-25 Xcode 27 Device Hub 및 Simulator Developer 설정에서도 해당 simulator에만 적용되는 네트워크 차단 제어를 찾지 못했다. 따라서 simulator 한 대만의 Airplane Mode 적용은 확인된 절차가 아니다. Mac 전체 네트워크를 끊는 방식은 모든 Mac 앱에 영향을 주므로 사용자의 명시 승인을 받기 전에는 사용하지 않으며, 승인 또는 별도 simulator 전용 수단 확인 전까지 앱 install/launch는 보류한다.

이 focused 결과는 기존 Xcode 27 전체 회귀와 합쳐 새로운 full regression 판정을 만들지 않는다. iOS 18 marker 의미 및 live ownership proof, iOS 17.0 직접 회귀, independent Development server inventory, pending export update, Production CloudKit, Xcode 27 Distribution 서명 Archive/export·TestFlight 및 해당 후보의 실기기 smoke는 미완료다. 26.3/26.6 빌드나 과거 TestFlight 결과로 바꾸지 않고 출시 판정은 **NO-GO**다.

### 현재 개발자 iCloud 계정의 CloudKit inventory 재확인 및 격리 시뮬레이터 준비 (2026-09-25)

사용자가 `Carve-X27-FirstLogin-20260925` (iPadOS 26.5, UDID `7284FDE5-6F95-4CC6-8EE6-75A794009F0F`)에 개발자 iCloud 계정을 로그인하고 CloudKit Console User token을 등록했다고 알렸다. 해당 token으로 Development private DB read-only query를 다시 실행했다. 지정한 `com.apple.coredata.cloudkit.zone`과 `_defaultZone`의 `CD_BibleDrawing` 결과는 각각 `records: []`, 명령 종료 코드는 0이다. 원격 응답과 종료 코드는 `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/remote-query-after-icloud-account-login.log` 및 `.exit`, `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/remote-query-default-zone-after-icloud-account-login.log` 및 `.exit`에 있다. 쿼리는 Development·private·해당 record type·두 zone에 한정됐고 record ID 목록을 받지 못했다. 다른 record type·계정·environment·Production DB는 조회하지 않았다.

같은 첫 로그인 시뮬레이터의 `Carve.dev.sqlite`를 `sqlite3 -readonly`로 조사했다. `ZBIBLEDRAWING` 21행, `ANSCKRECORDMETADATA` 21행, `ZNEEDSUPLOAD` 합계 0, export operation 0건, exported object 0건이었다. zone metadata는 `com.apple.coredata.cloudkit.zone` / `__defaultOwner__`, `needsImport=0`이었고 `PRAGMA integrity_check`는 `ok`였다. 집계 로그는 `/private/tmp/carve-x27-cloudkit-31-inventory-20260925/simulator-local-store-metadata-summary.log`에 있다. local store에는 CloudKit metadata가 연결된 21개 행이 있지만 현재 token으로 조회한 서버 목록에서는 행이 반환되지 않았다. 이것만으로 계정·소유자 불일치, 이전 업로드 실패 또는 서버 데이터 부재 중 어느 것이 원인인지 확정하지 않는다. 데이터는 읽기만 했으며 기존 시뮬레이터 앱을 재실행하거나 행을 수정하지 않았다.

기존 21행을 새 계정과 섞지 않고 독립 검증하기 위해 빈 iPad mini (A17 Pro), iPadOS 26.5 simulator `Carve-X27-CloudKit-CurrentIdentity-20260925` (UDID `D0E83844-A29A-4031-B174-9663A138CEEA`)를 생성했다. 첫 부팅 OS data migration 완료를 기다린 뒤 기존 Xcode 27 Debug 앱 `2.0.0 (1)`을 설치했고 `simctl appinfo`로 bundle/version을 확인했다. Settings만 열었으며 Carve 앱은 실행하지 않았다. 사용자가 이 새 simulator에 기존 개발자 iCloud 계정으로 로그인하는 단계가 남아 있다. 다음에는 이 빈 store에서 synthetic Genesis 1:31 행 하나를 만들고 local pending/export 완료와 peer/server read-only inventory를 분리해 확인한다. 기존 simulator의 21행을 복사·삭제·재전송하지 않는다.

추가로 시도한 `xcrun cktool export-schema`는 user token만으로 schema 조회를 허용하지 않고 `No management token found`로 exit 64를 반환했다. schema export는 하지 못했다. 이번 단계에서는 앱 빌드·테스트를 실행하지 않았고 CloudKit 데이터 변경도 없었다. 두 zone query 결과는 server inventory 완료로 인정하지 않는다. iOS 18 marker/ownership, iOS 17.0 직접 회귀, Development CloudKit first-login 독립 inventory, pending export update, Production CloudKit, Distribution 서명 Archive/export·TestFlight와 물리 후보 smoke는 미완료여서 출시 판정 **NO-GO**를 유지한다.

### Xcode 27 current-identity Development first-login 및 server payload 대조 (2026-09-25)

2026-09-25 재확인 환경은 macOS `27.2 (26B5086k)`, `xcode-select -p` `/Applications/Xcode.app/Contents/Developer`, Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `mise x -- tuist version` `4.208.0`이다. 샌드박스에서 Tuist 사용자 session 경로 권한 오류가 한 번 발생해 같은 `mise x -- tuist version`을 권한 있는 CLI로 재확인했다. `xcrun simctl list runtimes`와 `list devices available`도 권한 있는 CLI에서 성공했다. 확인된 iOS runtime은 17.5, 18.6, 26.2, 26.4, 26.5, 27.0이며 iOS 27.0은 build `24A5370g`와 `24A434` 두 항목이다. 이번 업로드 source는 iPad mini (A17 Pro), iPadOS `26.5 (23F77)`이고 iPhone destination은 사용하지 않았다.

새 current-identity source simulator `Carve-X27-CloudKit-CurrentIdentity-20260925` (`D0E83844-A29A-4031-B174-9663A138CEEA`)에서 Tuist workspace를 생성한 뒤 Xcode 27 Debug `CarveApp` `2.0.0 (1)`을 build·install했다. Debug 앱 `Info.plist`의 `CLOUDKIT_CONTAINER_ID`는 `iCloud.Carve.SwiftData.iCloud.dev`이고 일반 simulator signing/entitlement 경로를 사용했다. signature 우회, build setting·dependency 변경은 없었다.

```bash
mise x -- tuist generate --no-open
# exit 0

xcodebuild -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=D0E83844-A29A-4031-B174-9663A138CEEA' \
  -derivedDataPath /private/tmp/carve-x27-cloudkit-current-identity-20260925/DerivedData build
# exit 0; 전체 로그 /private/tmp/carve-x27-cloudkit-current-identity-20260925/xcodebuild-build.log

xcrun simctl launch D0E83844-A29A-4031-B174-9663A138CEEA kr.co.carve.leetaek \
  -UITestChapter '{"title":"1-01Genesis.txt","chapter":1}'
# 수동 UI smoke 시작용 launch; 앱 로그 /private/tmp/carve-x27-cloudkit-current-identity-20260925/carve-log-stream.log
```

사용자가 이 source simulator에 로그인한 뒤 합성 Genesis 1:31 필기 한 획을 Simulator UI에서 입력했다. 이는 수동 UI smoke이며 `xcodebuild test` 자동화 결과가 아니다. 자동 테스트는 이번 proof에서 새로 실행하지 않았다. Genesis 1:5로 잘못 잡힌 앞선 UI 드래그는 즉시 Undo했다. 읽기 전용 확인에서 이 절의 local `ZLINEDATA`는 `NULL`로 남았지만 빈 Core Data 행과 CloudKit metadata가 생겼고 Development inventory에도 빈 verse 5 record가 보여, 이를 payload가 있는 필기로 세지 않는다.

서버 query 전 baseline은 Development private DB의 Core Data custom zone `com.apple.coredata.cloudkit.zone`과 `_defaultZone` 모두 `CD_BibleDrawing` `records: []`, exit 0이었다. Genesis 1:31 입력 뒤 `NSPersistentCloudKitContainerEvent` Export 성공이 앱 log에 기록됐다. `Carve.dev.sqlite`의 read-only 검사에서는 integrity `ok`, verse 31 drawing metadata `ZNEEDSUPLOAD=0`, last exported transaction `3`, export operation 0건이며 metadata record name `7FA1F4D1-EBDE-4DD1-8687-5CD801914172`였다.

같은 개발자 iCloud identity의 CloudKit Console User token을 Keychain에서 읽는 `cktool` query를 Development·private·`CD_BibleDrawing`에 한정해 실행했다. custom zone query와 전체 field query는 exit 0이고 두 record를 반환했다. verse 31 server record `7FA1F4D1-EBDE-4DD1-8687-5CD801914172`의 `CD_titleName=1-01Genesis.txt`, `CD_titleChapter=1`, `CD_verse=31`, `CD_isPresent=1`, `CD_drawingVersion=3`, `CD_lineData` 321 bytes다. 이 record name은 local CloudKit metadata와 같다. local SQLite의 `.externalStorage` 원시 `ZLINEDATA` blob은 322 bytes이고 첫 byte가 `0x01`이었다. 그 한 byte 뒤의 321 bytes는 server `CD_lineData`와 바이트 단위로 같고 SHA-256은 양쪽 모두 `dba2e45b2762abd627907d43e6b1a53a6b678ba03d46a5f619b79a30e28496de`다. `_defaultZone` query는 exit 0, `records: []`였다. 이번 조회는 Development private zone과 record type에 한정하며 Production DB는 조회하지 않았다.

전체 build·app log·baseline 및 post-upload query와 exit 파일은 `/private/tmp/carve-x27-cloudkit-current-identity-20260925/`에 있다 (`post-sample-custom-zone.log`, `post-sample-custom-zone-full-fields.log`, `post-sample-custom-zone.exit`, `post-sample-default-zone.log`, `post-sample-default-zone.exit`, local/server `verse31-lineData` 비교 파일). 원문 User token은 출력·저장하지 않았다. 합성 verse 31 sample과 Undo 뒤 남은 빈 verse 5 test row는 Development sandbox에 유지되며 삭제하지 않았다.

새 record의 independent peer 수신은 별도 신규 simulator에서 확인했다. 기존 `Carve-ACC-Xcode27-LoginUpdate-20260925`는 verse 31의 다른 record ID를 이미 포함하고 있어 이번 record의 baseline peer로 사용하지 않았다. 현재 source를 `simctl clone`한 임시 장치는 `get_app_container`가 source app container 경로를 그대로 반환해 격리 peer로 인정하지 않았고 앱을 삭제·실행하지 않았다. 대신 신규 iPad mini (A17 Pro), iPadOS 26.5 `Carve-X27-CloudKit-Peer-CurrentIdentity-20260925` (`99987218-4E3C-471F-8000-7BFACC072452`)를 만들고 같은 Xcode 27 Debug `2.0.0 (1)`을 설치했다. 사용자가 source와 같은 개발자 iCloud 계정으로 로그인한 뒤 앱을 실행했다. 앱 실행 직전 CoreData store는 없었다. 앱 log의 CloudKit Setup은 success, 이어진 Import는 `succeeded: YES`; fetch count는 2였다. peer store는 integrity `ok`, drawing·record metadata 각 2행, import/export operation 0, Genesis 1:31의 record name `7FA1F4D1-EBDE-4DD1-8687-5CD801914172`, `ZNEEDSUPLOAD=0`이다. peer `.externalStorage` raw blob에서 첫 `0x01`을 제외한 payload는 서버와 동일 321 bytes이며 SHA-256 `dba2e45b2762abd627907d43e6b1a53a6b678ba03d46a5f619b79a30e28496de`로 일치했다. peer Import 뒤 Development server query는 exit 0, 동일 record 2개와 동일 record IDs를 반환해 추가·중복 레코드가 없었다. 완료된 peer 앱의 Genesis 1:31 화면에서도 수신 표본을 수동으로 관찰했다. 이는 Simulator UI 관찰이며 자동 테스트와 분리한다. peer app/launch/event 로그 및 post-import server query는 `/private/tmp/carve-x27-cloudkit-current-identity-20260925/`에 보존했다.

이에 따라 새 current-identity synthetic row의 first-login Development export, independent server record/payload 일치, 독립 iPadOS 26.5 peer simulator import까지 확인했다. 물리 iPad 수신, iOS 18 marker/ownership, iOS 17 ownership·17.0 직접 회귀, pending export update, Production CloudKit, Distribution 서명 Archive/export·Xcode 27 TestFlight는 미완료다. 자동 전체 회귀의 기존 Xcode 27 결과는 별도 기준으로 유지하고, 출시 판정은 **NO-GO**다.

### Xcode 27 ownership/migration focused CLI 재실행 (2026-09-25)

CloudKit peer proof와 별도로, 새 빈 iPad mini (A17 Pro) simulator `Carve-X27-Focused-Sync-Tests-20260925` (`9513D5AF-A266-4178-B3F9-19EC89A13BE8`), iPadOS `26.5 (23F77)`에서 관련 두 suite를 다시 실행했다. 환경은 macOS `27.2 (26B5086k)`, Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`이며 iPhone destination은 사용하지 않았다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=9513D5AF-A266-4178-B3F9-19EC89A13BE8' \
  -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/carve-x27-focused-sync-tests-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-focused-sync-tests-20260925/OwnershipAndMigration.xcresult \
  -only-testing:DomainTest/DrawingStoreOwnershipProofTesting \
  -only-testing:DomainTest/MigrationSyncReleaseTesting
# exit 0 — 11 passed, 0 failed, 0 skipped, 0 expected failures
```

`xcresulttool get test-results summary`도 `Passed`, 11/11, runtimeWarnings 0을 반환했다. 전체 로그는 `/private/tmp/carve-x27-focused-sync-tests-20260925/xcodebuild-test.log`, 종료 코드는 `xcodebuild-test.exit`, xcresult는 위 경로에 있다. fail-closed 입력을 검증하는 두 테스트가 의도한 보존 실패 경로를 지나는 중 진단용 CoreData/SQLite error 로그를 출력했지만 해당 테스트들은 통과했고 xcresult runtime warning은 없었다.

첫 시도는 기존 iPad mini (A17 Pro), iPadOS 26.5 UDID `589A8DAB-2D5C-45FC-B76B-C4260FB87C67`를 destination으로 지정했으나 Xcode가 요청 destination을 available로 찾지 못해 exit 70으로 테스트 시작 전에 끝났다. 당시 Xcode 오류는 같은 UDID를 compatible 목록에 함께 표시했다. 이 첫 시도의 전체 로그는 `/private/tmp/carve-x27-cloudkit-peer-focused-20260925/xcodebuild-test.log`다. 보호 계정/필기 데이터가 있는 simulator를 선택하지 않고 새 빈 iPadOS 26.5 simulator에서 재시도해 통과했다. 이 두 synthetic/local suite 결과는 live CloudKit marker 의미, 실제 store migration의 모든 OS, 물리 iPad, Production CloudKit 또는 배포 서명 증거를 대신하지 않으며 출시 판정 **NO-GO**를 유지한다.

### Xcode 27 physical iPad Debug artifact 재확인 (2026-09-25)

사용자가 같은 iCloud developer 계정으로 Xcode 27 로그인까지 완료한 뒤 연결된 물리 iPad mini (A17 Pro), iPadOS 27.2를 다시 확인했다. `security find-identity -v -p codesigning`은 Apple Development identity 1개를 반환했고, 기기는 USB(`Transport Type: wired`) 연결·Developer Mode enabled였다. Apple Distribution identity와 이 bundle의 App Store provisioning profile은 없다. 이 변화로 앞서 기록한 `CSSMERR_TP_NOT_TRUSTED`는 재현되지 않았다.

```bash
xcodebuild -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'platform=iOS,id=00008130-000C24A60C92001C' \
  -derivedDataPath /private/tmp/carve-x27-physical-smoke-20260925/DerivedData build
# BUILD SUCCEEDED, exit 0

codesign --verify --deep --strict \
  /private/tmp/carve-x27-physical-smoke-20260925/DerivedData/Build/Products/Debug-iphoneos/CarveApp.app
# valid on disk; satisfies its Designated Requirement; exit 0
```

이 산출물은 `kr.co.carve.leetaek` `2.0.0 (1)`이고 `Info.plist`의 `CLOUDKIT_CONTAINER_ID`는 `iCloud.Carve.SwiftData.iCloud.dev`다. signed entitlements에는 CloudKit service와 두 container ID가 있으나 `com.apple.developer.icloud-container-environment`는 없다. embedded Development profile은 `get-task-allow=true`이며 해당 environment 값을 `Development`와 `Production` 모두 허용한다. Apple 문서에 따르면 CloudKit은 이 entitlement로 런타임의 Development/Production 환경을 선택한다([CKContainer — Development 환경 테스트](https://developer.apple.com/documentation/cloudkit/ckcontainer)). 따라서 container ID만으로 CloudKit Development environment가 고정됐다고 추정하지 않는다. 같은 bundle ID로 설치하면 기존 TestFlight 앱과 설치본이 교체될 수 있고, 현재 서명 결과로는 이 기기에서 Production environment 접근을 배제할 수 없어 설치·실행하지 않았다. 읽기 전용 재확인에서 기존 TestFlight `2.0.0 (220)`은 그대로 설치돼 있었다. 물리 iPad 앱·데이터는 이번 작업에서 변경하지 않았다.

전체 build log/exit, strict codesign 결과, signed entitlement·profile 검사는 `/private/tmp/carve-x27-physical-smoke-20260925/`에 있다. 이 physical Debug build·서명 검증은 자동 테스트와 분리하며, Release Distribution/Production 환경, TestFlight 후보 및 물리 CloudKit peer smoke의 증거로 세지 않는다. Development-only environment가 서명으로 확인되는 후보 없이는 해당 smoke를 진행하지 않는다.

### Xcode 27 iPadOS 18.6 앱 컴파일 및 집중 회귀 (2026-09-25)

환경은 macOS `27.2 (26B5086k)`, `xcode-select -p` `/Applications/Xcode.app/Contents/Developer`, Xcode `27.0 (27A266a)`, Swift `6.4.0.34.1`, Tuist `mise x -- tuist version` `4.208.0`이다. 대상은 iPad mini (A17 Pro), iPadOS `18.6 (22G86)` simulator다.

새 빈 simulator `Carve-X27-Ownership-Migration-iOS18.6-20260925` (`1314A38C-D931-4733-AD31-31B4D415F9C8`)에서 먼저 관련 소유권·마이그레이션 suite를 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=1314A38C-D931-4733-AD31-31B4D415F9C8' \
  -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/carve-x27-focused-sync-tests-20260925/DerivedData \
  -resultBundlePath /private/tmp/carve-x27-ios18.6-ownership-20260925/OwnershipAndMigration.xcresult \
  -only-testing:DomainTest/DrawingStoreOwnershipProofTesting \
  -only-testing:DomainTest/MigrationSyncReleaseTesting
# exit 0; 11 passed, 0 failed, 0 skipped, 0 expected failures; xcresult runtimeWarnings 0
```

전체 로그·종료 코드는 `/private/tmp/carve-x27-ios18.6-ownership-20260925/xcodebuild-test.log` 및 `xcodebuild-test.exit`에 있다. 합성/local 경로의 결과로 CloudKit 로그인·데이터 변경은 없었으며 iOS 18.6의 실제 private metadata marker 의미나 live ownership proof는 닫지 않는다.

그 다음 Xcode 27 workspace에서 `CarveApp` Debug simulator build를 실행했다.

```bash
xcodebuild -workspace Carve.xcworkspace -scheme CarveApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-x27-ios18.6-app-build-20260925/DerivedData build
# BUILD SUCCEEDED, exit 0
```

destination은 iPad mini (A17 Pro), iPadOS `18.6 (22G86)`이며 Xcode 27.0의 iOS Simulator 27.0 SDK를 사용했다. 전체 로그·종료 코드는 `/private/tmp/carve-x27-ios18.6-app-build-20260925/xcodebuild-build.log` 및 `xcodebuild-build.exit`에 있다. 기존 `undoManager` deprecated 진단, 매크로의 non-Sendable 변환 경고와 SwiftLint 경고가 남았다. 앱을 simulator에 설치·실행하지 않았고 CloudKit/Firebase 실행 데이터도 바꾸지 않았다. 따라서 이것은 iOS 18.6 runtime에서의 앱 동작이나 Distribution 서명 검증이 아니다.

같은 환경 확인에서 일반 sandbox 호출은 Tuist session 경로와 CoreSimulatorService 로그 접근 권한 오류를 냈다. 동일한 `xcode-select -p`, `xcodebuild -version`, `swift --version`, `mise x -- tuist version`, `xcrun simctl list runtimes`, `xcrun simctl list devices available`을 권한 있는 CLI로 조회해 각각 성공했으며 Tuist `4.208.0`, Xcode `27.0 (27A266a)`, Swift `6.4.0.34.1`과 runtime/device 목록을 얻었다. runtime은 iOS `17.5`, `18.6`, `26.2`, `26.4`, `26.5`, `27.0`이며 iOS `17.0`은 없다.

`xcrun simctl help`에는 simulator 한 대의 네트워크 차단/비행기 모드 명령이 없다. 계정 없는 임시 `Carve-X27-AirplaneMode-NetProbe-20260925`를 Device Hub에서 선택해 `Controls`를 확인했으나 Home·Lock·Siri·App Switcher·회전·화면 캡처/녹화만 있었고 네트워크 제어는 없었다. 네트워크 격리를 설정하거나 Mac 네트워크를 끊지 않았으므로 pending-export offline update 시험은 실행하지 않았다.

마지막 read-only 서명 자격 재확인에서 `security find-identity -v -p codesigning`은 `0 valid identities found`를 반환했다. 두 표준 provisioning profile 저장 경로에서 찾은 프로파일 3개 중 정확한 Carve bundle profile은 Development/ad-hoc 1개뿐이었고 `get-task-allow=true`, CloudKit environment는 `Development`와 `Production` 모두였다. 이는 앞선 physical Debug build 시점의 Apple Development identity 1개 기록과 다르며 원인은 미확정이다. 현재 Apple Distribution identity와 App Store profile은 확인하지 못했다. 인증서·profile·signing 설정은 바꾸지 않았으며 Distribution Archive/export·Xcode 27 TestFlight gate는 계속 NO-GO다.

따라서 iOS 18.6 focused suite와 앱 컴파일은 통과했지만 iOS 18 marker 의미·계정/ownership 왕복, iOS 17.0 직접 회귀, pending export offline update, Production CloudKit, Distribution Archive/export·TestFlight 및 물리 후보 smoke는 미완료다. Xcode 26.3 결과로 대체하지 않고 출시 판정은 **NO-GO**다.

## 2026-09-25 iPadOS 17.5 1.3.0 로그인 후 실제 CloudKit 가져오기 확인

사용자가 전용 `Carve-X27-iOS17.5-V3-Update-Probe-20260925` simulator(iPad mini 6, iPadOS 17.5, UDID `3E2D5B97-1682-400B-BB62-0DD640A0F62D`)의 `Settings > Apple Account`에 Carve Development 시험 계정으로 로그인했다. 이 기기에는 기존 1.3.0 앱 `1.3.0 (1)`을 실행했고, 컨테이너는 `iCloud.Carve.SwiftData.iCloud.dev`였다. 2.0.0 업데이트 전에 앱의 첫 CloudKit 연결·가져오기 결과를 확인했다.

1.3.0 콘솔에서 Core Data CloudKit setup 성공, import 요청 완료, incremental import 적용 7건을 관찰했고 비-null CloudKit 오류나 `CKAccountStatusNoAccount`는 없었다. 다만 앱 컨테이너 `Library/Application Support/Carve.dev.sqlite`는 `PRAGMA quick_check=ok`였지만 `ZBIBLEDRAWING=0`, `ZBIBLEPAGEDRAWING=0`, `ANSCKRECORDMETADATA=0`이었다. 별도로 캡처한 수동 화면에서도 창세기 1장 필사란은 비어 있었다. 실행 로그와 캡처는 `/private/tmp/carve-x27-ios17.5-v3-update-20260925/legacy-1.3-console.log`, `/private/tmp/carve-x27-ios17.5-v3-update-20260925/legacy-1.3-after-import.png`에 있다. 저장소는 해당 simulator 앱 컨테이너의 `09BA1B79-D807-406E-A8CC-308810335DC9/Library/Application Support/Carve.dev.sqlite`였다.

이 세션에서 실제 historical V3 필기가 앱으로 들어오지 않았으므로 importer setup 성공을 필사 수신으로 세지 않는다. 실제 표본의 화면 표시, 좌표·내용, 앱 재실행 후 보존, 첫 로그인 업로드는 여전히 미검증이다. 이전 별도 계정 없는 synthetic V3 fixture에서 확인한 298-byte 보존 결과와도 다른 시험이다. 빈 저장소를 업데이트해 무유실 성공으로 잘못 판정하지 않도록 1.3.0 상태를 유지했다.

현재 `LegacyRowLinkageReader.validatedOSMajors`는 `[26]`이며, iOS 18 표본에서 확인된 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`의 의미도 미확인이다. 사용자는 지원 보장 유지와 근거가 마련될 때까지 NO-GO를 선택했다. OS/metadata allowlist나 쓰기 안전장치는 변경하지 않았다. 실제 V3 행이 없는 이 계정은 ownership proof blocker를 닫지 않으며, 필수 release gate는 계속 **NO-GO**다.

## 2026-09-25 Xcode Cloud build 220 및 후보 생성 경로 read-only 확인

Xcode Cloud Report Navigator에서 `Carve > DevelopBranch > build 220`을 열어 읽기 전용으로 확인했다. run은 2026-09-21 17:57 시작, workflow `DevelopBranch`, branch `develop`, Xcode `26.6 (17F113)`, macOS `26.3 (25D125)`이며 Build·Test·Archive는 완료됐고 TestFlight Internal Testing은 조회 시 `Running… / In Progress`였다. 화면의 마지막 커밋 short SHA `c466f80`을 로컬 git object와 대조해 `c466f8066b2a57900c6ea105500f8bd002419efd` (2026-09-21, `[Fix] 시안 본문도 앱이 싣는 개역개정 표기로 맞춤`)로 확인했다. 물리 iPad에 설치된 기존 TestFlight는 `2.0.0 (220)`이다. 이 Cloud report는 signed archive의 서명 identity/profile, CloudKit container/environment, Production schema를 노출하지 않아 확인값으로 기록하지 않았다.

Workflow 편집 화면은 열어 값만 읽고 취소했다. TestFlight action이 있는 `DevelopBranch`는 Xcode `26.6 (17F113)` / macOS `26.3 (25D125)`이며 환경 변수 `FORCE_BUILD_RESET=1`이 보였다. 배포용 `MAIN`은 Xcode `26.3 (17C529)` / macOS `26.3 (25D125)`이고 Build·Archive만 있어 TestFlight action은 없다. 어느 workflow도 Xcode 27.0으로 설정돼 있지 않다. 설정 화면에서 저장한 변경은 없고, 저장소 안에도 workflow 설정 파일은 없다.

Cloud 후보를 trigger하지 않고 현재 checkout과 build 220 commit의 `ci_scripts/ci_pre_xcodebuild.sh`, `.gitignore`, `ci_scripts/ci_post_clone.sh`를 읽기 전용으로 확인했다. `.last_version`은 ignore 대상이며 checkout에 없다. 스크립트는 빈 tracker를 `MARKETING_VERSION=2.0.0` 변경으로 판단해 build number `1`을 지정하고 App Store Connect(ASC) 조회를 건너뛴다. `FORCE_BUILD_RESET=1`도 독립적으로 build number를 `1`로 강제하고 ASC 조회를 건너뛴다. `ci_post_clone.sh`는 `.last_version`을 복구하지 않는다. 따라서 현재 DevelopBranch 설정으로 후보를 trigger하면 build 220 뒤에 build 1을 시도할 위험이 있다. ASC 최신 build 조회 결과를 받지 않아 다음 번호를 확정하지 않았다.

후보 생성에는 다음 최소 변경이 필요해 보인다. (1) `DevelopBranch` Xcode selector를 Xcode `27.0 (27A266a)`으로 변경, (2) 2.0.0 후보에서 `FORCE_BUILD_RESET`을 `0`으로 변경, (3) `ci_pre_xcodebuild.sh`에서 빈 `.last_version`을 버전 변경으로 오인하지 않고 ASC 최신 build 조회를 수행하도록 해당 분기만 조정한다. 기존 TestFlight `220`이 ASC 최신이라는 조회가 확인되면 다음 값은 `221`이어야 한다. 이는 workflow/CI 변경이므로 승인 전에는 적용하지 않는다. 읽기 전용 점검에서 push, build trigger, workflow·CI·signing 변경, TestFlight 배포는 하지 않았다. 로컬 Apple Distribution 인증서 부재만으로 Xcode Cloud 배포를 차단 판정하지 않는다.

## 2026-09-25 보존된 historical V3 표본과 시험 계정 identity 대조

`Carve-X27-ACC-Xcode27-LoginUpdate-20260925` simulator의 기존 2.0.0 앱 컨테이너에 보존된 V3 snapshot을 읽기 전용으로 확인했다. snapshot은 `Library/Application Support/Preservation/Carve.dev.sqlite/raw/1790306211-394F9AD7/Carve.dev.sqlite`; `PRAGMA quick_check=ok`, V3 drawing 20행(그중 `ZISPRESENT=1` 14행), CloudKit record metadata 20행이며 외부 payload 디렉터리도 존재한다. 이 snapshot은 앞서 기록된 historical 1.3.0 CloudKit-backed 업데이트 표본의 보존본이며 현재 2.0.0 컨테이너에 있는 21행과 동일 자료가 아니다.

사용자가 로그인한 iOS 17.5 target store와 snapshot의 `NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey`는 값을 출력하지 않고 내부에서만 비교했다. 두 키는 모두 있었지만 **같은 CloudKit identity가 아니었다**. 그래서 이 표본을 현재 target account로 복사·업로드하지 않았다. 현재 target 계정에서 1.3.0 앱은 import 뒤 0 drawing row였던 관측과도 일치한다. 화면·좌표·업데이트 보존을 이 20행으로 시험하려면 같은 V3 source identity에 연결된 Development 시험 계정이 정확한 iOS 17.5 simulator에서 필요하다. 값·토큰·계정 식별자는 출력하거나 문서에 저장하지 않았다.

현재 iOS 17.5 시험 기기의 계정은 사용자가 CloudKit `userToken`을 등록한 계정이다. 사용자가 다른 계정으로 바꿀지 물었으나, 이번 시험에서는 계정을 그대로 두는 것이 맞다고 판단했다. 보존된 20행 표본은 이미 계정 식별 metadata와 CloudKit 레코드 대응을 가진 linked store이므로, source identity로 계정을 바꿔도 무계정 V3 첫 로그인 시험이 되지 않고 등록된 token으로 서버 payload를 대조할 수도 없다. 대체 무계정 historical V3 위치는 아직 지정되지 않았다. 계정 변경이나 해당 linked 표본 사용은 하지 않았다.

pending export update를 위해 사용자가 Mac 전체 연결을 약 5분 끊는 데 동의했다. 복구 준비용 read-only 조회에서 기본 route는 Wi-Fi `en0`였고 `USB 10/100/1000 LAN`·`iPad USB`에는 IP route가 없었다. `sudo -n -l`은 관리자 암호가 필요하다고 반환했다. networksetup·route 조회 외에는 어떤 네트워크 설정도 바꾸지 않았고, 이 환경에서는 아직 중단/자동복구를 시작할 수 없었다. 시험용 pending note가 준비되고 안전한 복구 경로가 확인되기 전에는 네트워크를 변경하지 않는다.
