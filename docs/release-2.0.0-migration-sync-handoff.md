# Carve 2.0.0 iCloud 동기화 인계

작성: 2026-09-23 · 실험 기록 추가: 2026-09-25 · 당시 작업 브랜치: `codex/2-0-0-migration-sync-release` (현재 checkout은 별도 확인)

## 현재 판정

출시 판정은 **NO-GO**다. production 저장소 소유 증명 공급자는 연결했고 증거가 맞지 않거나 읽히지 않으면 계속 fail-closed 한다. 현재 `LegacyRowLinkageReader.validatedOSMajors`는 `[26]`이다. **현행 주 검증·출시 후보 자격 확인 대상은 macOS 27.2 / Xcode 27.0이며, Device Hub는 기기 확인·수동 스모크에 사용한다.** Xcode 27에서 Tuist workspace Debug iPad simulator 빌드가 통과했고, iPadOS 17.5 전체 회귀는 **998 passed · 4 expected failures · 6 skips**, 18.6·26.2·26.4·26.5는 각각 **999 passed · 4 expected failures · 5 skips**, 27.0은 **998 passed · 4 expected failures · 6 skips**로 설치된 여섯 runtime 모두 총 1008건·예기치 않은 실패 0이다. 17.5 로그에는 임시 migration/store fixture 관련 SQLite 경고가 있으나 xcresult failure/runtime warning은 없고 정리 시점 원인은 미확정이다. 최초 F60의 XCFramework `ProcessXCFramework` 실패는 재현되지 않았다. iOS 27 SwiftData 네 실패는 새 `unknownDataStoreSchema` 오류를 확인된 1.0.x metadata shape에 한해 처리한 뒤 해결됐다. 첫 수정 후 전체 실행에서 reader fixture의 SQLite 잠금이 한 번 발생했으나 reader suite 단독 31/31과 후속 전체 회귀에서 재현되지 않았다. 개별 `-project CarveApp` 명령의 SwiftPM 모듈 의존성 오류와 읽기 전용 artifact 서명 이상은 확인했으나 서로의 인과관계는 미확정이다. Device Hub에서 새 iPadOS 27.0 simulator의 창세기 1장 reader 표시와 1장→2장→1장 수동 이동을 확인했지만, 앱 시작 때 iCloud 필사 수신 대기 상태를 표시했으므로 CloudKit 검증으로 세지 않는다. Xcode 26.3 결과는 비교 기준으로 보존하며 Xcode 27 검증으로 대신하지 않는다. iOS 19~25 runtime은 현재 목록에 없다.

2026-09-25 Xcode 27 iPadOS 26.5 기존 private store proof는 첫 계정 확인 실패 뒤 사용자가 같은 ACC sandbox account를 복제 simulator와 Xcode 27에 로그인해 재개했다. ACC-B 원본은 종료 상태로 보존하고 clone에서만 진행했다. 읽기 전용 private-zone inventory 20개와 로컬 record name hash 20개가 일치하고, 재조회 inventory 지문도 같았으며, pending 0·Genesis 1:1/1:2 payload 보존·`currentPrivateCloudRecords` ownership marker를 확인했다. 이어 same-account proof clone을 분리 복제해 historical 1.3.0(1) 앱 bundle을 설치·실행한 뒤 Xcode 27 Debug 2.0.0으로 업데이트했다. 20개 cloud-backed V3 row, 무결성 `ok`, pending export 0, payload·record-name hash set 일치와 새 `currentPrivateCloudRecords` marker를 확인했고 focused two-suite CLI 회귀는 37/37 통과했다. 이 앱 화면은 Device Hub에서 별도 관찰했으며 기존 필기 몇 개가 보였지만 첫 실행 안내·AdMob 팝오버를 남긴 읽기 관찰뿐이다. historical 1.3.0 bundle은 Xcode 27에서 새로 빌드한 것이 아니다. 별도로 Xcode 27 iPadOS 18.6의 새 계정 없는 simulator에서 synthetic 1.3.0 V3 한 행을 2.0.0으로 로컬 migration했고 298B payload와 원본 Preservation snapshot이 보존됐다. 최초 Device Hub 화면은 일시 오버레이가 열린 축소 화면에서 획을 놓쳤으나, 후속 read-only CanvasDisplayProbe에서 store와 canvas의 한 획·bounds가 같고 diff 0임을 확인했다. 오버레이를 닫고 Device Hub를 확대하자 Genesis 1:1 획이 보였고 1→2→1 이동 뒤에도 표시됐다. 이 단일 오프라인 표본의 화면 확인은 통과로 정정하되 2.0.0 store에 의미 미확인 migration marker가 추가돼 iOS 18은 계속 fail-closed다. 무계정 local-only row의 first-login 업로드·peer 수신은 아래의 제한된 Xcode 27 synthetic 결과로 보완했다. production CloudKit·iOS 17 및 배포 검증은 미완료다. 상세 명령·로그 경로와 첫 시도 경위는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)을 참조한다.

2026-09-25 후속으로 새 iPadOS 26.5 no-account simulator에서 historical 1.3.0 V3 Genesis 1:31 synthetic row 한 개를 Xcode 27 2.0.0으로 업데이트한 뒤 같은 ACC sandbox 계정에 로그인했다. 앱 로그의 Core Data export는 `success=1, madeChanges=1`이고, 로그인 후 store는 21 drawing/metadata row, sample payload 300B와 기존 SHA-256, pending 0, `firstLoginFromUnaccountedV3` marker를 보였다. 별도 peer clone은 실행 전 20 row이며 1:31 row가 없었고, 실행 후 21 row와 동일 payload·pending 0을 보였다. 이로써 해당 synthetic row의 첫 로그인 업로드와 peer simulator 수신을 확인했고, 후속 Device Hub manual reader에서 Genesis 1:31 필기 한 줄도 관찰했다. 키보드 Page Down만 사용했으며 이 UI 확인은 자동화 테스트와 분리했다. 앱 종료 뒤 읽기 전용 store integrity·payload·pending도 보존됐다. 새 row의 독립적인 read-only CloudKit inventory는 수집하지 못했다. 첫 로그인 앱 로그는 기존 Genesis 1:10–12의 8개 22B row를 undecodable로 표시했다. 그러나 이후 보존된 동일 snapshot bytes를 격리한 harness에서 다시 읽은 결과 macOS 27.2·iPadOS 26.5·iPadOS 27.0 모두 `PKDrawing(data:)` decode 성공·0 strokes였다. 그러므로 현재 증거는 PencilKit 플랫폼 차이를 재현하지 않으며, 앱 로그와 직접 API 검사 사이의 불일치는 `DrawingCodec.compose` 시점의 입력·상태를 보지 못해 미해결이다. 행은 편집·덮어쓰기하지 않았다. CloudKit Development sandbox에는 synthetic Genesis 1:31 테스트 row가 남아 있으며 삭제하지 않았다. 상세 명령·로그와 snapshot은 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)을 따른다.

2026-09-25 Xcode 27 generic iOS Release Archive도 생성됐다. `xcodebuild archive`와 `codesign --verify --deep --strict`가 각각 exit 0이지만 Archive는 Apple Development identity와 `get-task-allow=true` Development profile을 사용했다. 현재 로컬에는 Apple Distribution identity와 이 bundle의 App Store profile이 없고 signed app entitlement에 CloudKit environment가 설정되지 않아, 이 산출물은 배포 서명·Production CloudKit 증거가 아니다. `xcodebuild -exportArchive`와 TestFlight 업로드는 실행하지 않았다. 전체 로그·Archive 경로와 정확한 CLI는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)의 Xcode 27 Release Archive 절을 따른다. 배포 Archive/export·Production entitlement·TestFlight 게이트는 계속 NO-GO다.

같은 날 Device Hub에서 물리 iPad mini (A17 Pro) iPadOS 27.2를 확인했다. 설치 앱은 TestFlight `2.0.0 (220)`이었다. 사용자는 교체를 승인했지만, 사전 점검에서 Release 구성의 signed app CloudKit environment가 불명확했고, 같은 소스의 Debug 기기 빌드는 `codesign --verify --deep --strict`에서 `CSSMERR_TP_NOT_TRUSTED`로 실패했다. 서명 검증 우회나 profile/설정 변경을 하지 않아 앱을 설치·실행하지 않았다. TestFlight 앱과 기기 데이터는 그대로이고 물리 후보 smoke는 미실행이다. 상세 명령·로그 및 blocker는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#물리-ipad-후보-설치-사전-점검-후속-2026-09-25)에 있다. Device Hub 관찰은 자동 테스트 결과에 포함하지 않는다.

2026-09-25 Xcode 27의 Xcode Cloud Report Navigator에서 `DevelopBranch` build 220의 기존 결과를 읽기 전용으로 확인했다. 이 run은 Xcode `26.6 (17F113)` / macOS `26.3 (25D125)`이며 Build·Test·Archive는 완료, TestFlight Internal Testing 단계는 조회 시 `Running… / In Progress`로 표시됐다. 물리 기기에 실제 설치된 `2.0.0 (220)`은 사용자가 말한 기존 TestFlight 배포와 일치한다. 따라서 기존 Xcode Cloud 배포 성공과 로컬 Xcode 27 Debug 서명 오류는 별개다. 다만 build 220은 Xcode 27 검증이 아니며, 현재 Xcode Cloud 화면만으로 TestFlight 단계의 종료 상태도 확정하지 않는다. Xcode 27 후보의 배포 서명·Production entitlement·기기 smoke는 미완료다. 상세는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#xcode-cloud-testflight-build-220의-툴체인-확인-2026-09-25)에 있다.

iOS 18.6에서 실제 1.3.0을 실행해 만든 V3 저장소는 기본 무계정 metadata 네 key 외에 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`가 하나 더 있다. 값은 정수 boolean `true`였다. 이 private Core Data 키의 의미를 확인할 공개 근거가 없어, iOS 18을 안전하게 허용할 수 없다. 현재 정확한 key profile 규칙은 이 표본을 거절한다. `Carve-Ownership-iOS18-6`에는 계정 로그인을 하지 않았다.

## 코드 상태

- `App.swift`가 production `CloudKitStoreOwnershipProofClient`를 live `DrawingEditEnvironment`에 주입한다.
- 소유 증명은 빈 새 저장소, 무계정 1.3.0 V3 원본, 기존 private CloudKit 저장소의 세 갈래다. 계정 확인만으로 소유를 만들지 않는다. 표식은 계정 간 재귀속되지 않는다.
- 기존 private 저장소는 현재 계정 identity 일치, 로컬 행·미러링 레코드 일대일성, 대기 작업 없음, private DB 전체 레코드 조회를 요구한다.
- reader v4는 metadata key 집합과 각 SQLite 값 열의 형식·비어 있지 않음, metadata migration 미요청, identity 확인 상태를 함께 판정한다. 추가·누락·중복·NULL·잘못된 형식은 소유 proof에서 거절한다.
- `SyncedWriteBlock` 경로가 필사 외 즐겨찾기·위젯 보관·이력 복원·N-Canvas 직접 쓰기도 막는 기존 규칙을 유지한다. 계정 변경 차단, server-work 표, 삭제 기준점 K, 원본 보존, 마이그레이션 실패 차단, 무계정 신규 로컬 초안의 자동 업로드 금지도 유지한다.
- 사용자 승인 전 실험에서는 기존 `Carve-ACC-dut` Genesis 1:1·1:2와 `Carve-ACC-B`를 사용하지 않았다. 2026-09-25 후속 실행은 ACC-B 원본을 종료 상태로 둔 채 clone에서만 앱을 실행했다. 원본 DB/WAL은 snapshot과 같은 해시다. 읽기 전용 SQLite 검사 중 `-shm`가 갱신될 수 있어 sidecar에 관한 상세는 호환성 시험 계획에 기록했다.

## 실제 iOS 18.6 관측

- Xcode 26.3 (17C529), iPadOS 18.6 전용 simulator `Carve-Ownership-iOS18-6`에서 historical 1.3.0 build를 실행했다.
- 보호 표본 `Carve-Ownership-iOS18-6`에는 기존 표본을 쓰지 않고 Genesis 1:3 합성 PencilKit stroke를 가진 V3 행을 추가했다. 그 기기의 당시 입력 설정·자동화 경로로는 터치·드래그가 저장되지 않았다. F59의 별도 iPad (A16) 표본에서는 `손가락 필사 허용`을 켠 뒤 Device Hub 포인터 입력이 저장됐다. 어느 쪽도 압력·기울기·Apple Pencil 결과로 간주하지 않는다.
- 저장소 snapshot은 `/private/tmp/carve-ios18-live-proof-evidence/snaps/ios18-1-3-initial-state`와 `.../ios18-1-3-v3-seeded`에 있다. 이 경로는 해당 머신의 임시 자료다.
- simulator는 로그인하지 않은 채 유지한다. 앞선 18.3.1·18.6 test-double 집중 결과는 현재 허용 OS 판정의 증거가 아니다.
- **별도 오프라인 업데이트 시험(2026-09-24, F59):** Device Hub 호스트 macOS 27.2 / Xcode 27.0에서 별도 `iPad (A16)` iPadOS 18.6 simulator에 1.3.0(1)을 설치했다. 앱 설정 `손가락 필사 허용`이 꺼졌을 때 Mac 포인터 드래그는 저장되지 않았고, 이를 켠 뒤 Genesis 1:1에 드래그해 만든 행 1개는 integrity `ok`, payload 298B였다. 이 저장소를 SQLite backup으로 보존한 다음 Xcode 26.3에서 만든 2.0.0(1) 산출물을 같은 기기에 설치했다. 2.0.0 화면에서 필기가 보였고 창세기 2장으로 갔다 돌아와도 남았다. 업그레이드 뒤에도 행·298B payload·SHA-256 `07876e8b1910039124914f5c44b9619a90b8ad488a08500bdfa6abc07762c3d6`이 같았고 integrity `ok`였다. 로그인과 CloudKit 전송은 하지 않았다. 전후 사본은 `/private/tmp/carve-2.0-live-proof-20260924/legacy-ios18.6-pointer-sample-before-2.0.sqlite` 및 `legacy-ios18.6-sample-after-2.0.sqlite`다.
- **Xcode 27 no-account V3 local update (2026-09-25):** F59의 V3 synthetic row snapshot을 새 iPad mini (A17 Pro) iOS 18.6 simulator에서 Xcode 27로 빌드된 2.0.0(1)에 올렸다. `integrity_check=ok`, Genesis 1:1 payload 298B와 SHA-256 `07876e8b1910039124914f5c44b9619a90b8ad488a08500bdfa6abc07762c3d6`가 유지됐고 원본 Preservation snapshot hash도 입력과 같았다. Core Data CloudKit setup은 로그인 계정 없음(134400)으로 실패했으며 ownership marker·record metadata는 생성되지 않았다. 2.0 store에 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`가 생겼지만 의미는 미확인이다. 최초 Device Hub 화면은 일시 오버레이가 열린 축소 상태에서 획을 놓쳤다. 후속 `-CanvasDisplayProbe`에서는 fetch 후 expected·canvas가 같은 1획 `(433,145,49,4)`, diff 0, `screenInk=(433,287,49,4)`를 보고했다. 오버레이를 닫고 확대하자 Genesis 1:1 획이 보였고, 1→2→1 이동 뒤에도 표시됐다. 따라서 이 synthetic 단일 표본의 화면 보존은 확인으로 정정하며, 이전의 화면 미통과 기록은 철회한다. 정확한 1.3.0 소스는 Xcode 27에서 dependency deployment target이 SDK 최솟값보다 낮아 exit 65로 재빌드되지 않았고, 기존 simulator의 1.3.0(1) 앱 bundle을 historical 입력으로 사용했다. 상세 명령과 probe 로그 경로는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)을 따른다.
- F59는 기존 `Carve-2.0.0-test-legacy` iPadOS 26.5의 화면 필기/DB 불일치(F58)를 설명하거나 해소하지 않는다. 해당 사용자 표본은 2.0.0으로 덮어 설치하지 않고 그대로 보존했다. 18.6에서 확인된 것은 손가락 허용 상태의 Device Hub 포인터 필기 및 오프라인 로컬 업데이트다.
- **초기 Xcode 27.0 F60 관측:** 당시 기록된 generic iOS Simulator `CarveApp` 빌드는 기존 Google/Firebase 계열 XCFramework 서명을 검증하지 못해 `ProcessXCFramework` 단계에서 실패했고 앱 Swift 소스 컴파일에 도달하지 않았다. CoreSimulatorService 조회도 한 번 실패했으나 현재 기본 Xcode 27에서는 `simctl` 목록 조회가 성공한다. Xcode 26.3 지정 sandbox 조회는 CoreSimulatorService 연결 오류를 냈고, 권한을 높인 read-only 런타임 조회는 성공했다. 서비스 오류는 Xcode 선택과 sandbox 실행 조건에 따라 다르게 나타났다. 이 초기 관측은 아래의 workspace build·회귀 검증 전 기록이며, 최신 결과와 현재 판정은 `Xcode 27.0 RC 빌드·회귀 명령과 결과` 절을 따른다.
- **F60 후속 재현·서명 진단(2026-09-24):** macOS `27.2 (26B5086k)` · 기본 Xcode `27.0 (27A266a)` · Swift `6.4 (6.4.0.34.1)` · Tuist `4.208.0`. `CarveApp.xcodeproj`가 있어 재생성하지 않았다. 처음 iPad mini (A17 Pro) iPadOS 18.6 destination 빌드는 sandbox의 CoreSimulatorService 연결 오류로 destination 해석 전에 종료 코드 70(`/private/tmp/carve-2.0.0-xcode27-f60-20260924/build.log`). 서비스 접근을 허용한 재실행은 `ProcessXCFramework`를 통과해 TCA 매크로의 SwiftSyntax 모듈들을 해석하지 못했고 종료 코드 65(`/private/tmp/carve-2.0.0-xcode27-f60-20260924-escalated/build.log`). F60과 같은 generic iOS Simulator 명령도 Google/Firebase XCFramework 다섯 개의 `ProcessXCFramework`를 실행한 뒤 `Sharing`의 `Dependencies`, `PerceptionCore`, `IssueReporting`, `ConcurrencyExtras`, `CustomDump`, `IdentifiedCollections` 모듈 의존성 해석 오류로 종료 코드 65(`/private/tmp/carve-2.0.0-xcode27-f60-20260924-generic/build.log`). 각 `build.exit`에 종료 코드를 보존했다. 전체 목록·명령·결과는 [호환성 시험 계획의 Xcode 27 후속 기록](./icloud-sync-compatibility-test-plan.md#xcode-270-f60-후속-재현서명-진단-2026-09-24)에 있다.
- 같은 5개 XCFramework의 번들 서명 메타데이터에는 TeamIdentifier `EQHXZ8M8AV`가 있었지만 읽기 전용 `codesign --verify --deep --strict` 결과는 모두 `invalid signature (code or signature have been modified)`였고 simulator framework slice는 서명되지 않은 코드 객체로 보고됐다. 검사 원문은 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-escalated/codesign-inspection.txt`다. 반면 재실행 build log에서 `ProcessXCFramework`의 “identity … is not recorded in your project”는 note였고 실패 목록에 포함되지 않았다. 따라서 이전 F60의 서명 실패는 이번에 그대로 재현되지 않았으며, 확인된 artifact 서명 이상과 당시 SwiftPM 모듈 오류의 인과관계도 미확정이다. 이 초기 `-project` 재현 단계에서는 테스트를 실행하지 않았고, 이후 workspace 갱신 뒤 수행한 Xcode 27 테스트 결과는 아래에 별도로 기록했다.

## 검증 기록과 남은 차단

### Xcode 27.0 RC 빌드·회귀 명령과 결과 (2026-09-24)

실행 환경은 macOS `27.2 (26B5086k)`, 기본 선택 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, `mise x -- tuist version` 결과 Tuist `4.208.0`이다. 환경 조회 명령은 `xcode-select -p`, `xcodebuild -version`, `swift --version`, `mise x -- tuist version`, `xcrun simctl list runtimes`, `xcrun simctl list devices available`이며 기본 선택 Xcode의 두 simctl 조회가 성공했다. 빌드 destination은 iPad mini (A17 Pro) iPadOS 18.6이고, 테스트는 iPad mini (A17 Pro) iPadOS 27.0 (`24A434`) 및 26.2 (`23C54`)만 사용했다.

기존 생성물은 먼저 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-regenerate/preserved/`에 복사했다. 그 뒤 오래된 workspace 그래프를 Tuist로 다시 생성했다.

```bash
mise x -- tuist generate --no-open
# exit 0; /private/tmp/carve-2.0.0-xcode27-f60-20260924-regenerate/tuist-generate.log

xcodebuild build -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-workspace/DerivedData
# BUILD SUCCEEDED, exit 0; /private/tmp/carve-2.0.0-xcode27-f60-20260924-workspace/build.log
```

이 workspace build에서 Google/Firebase XCFramework 다섯 개의 `ProcessXCFramework` 작업과 앱·Domain Swift 컴파일이 통과했다. 빌드 종료 결과는 같은 경로의 `build.exit`다. `-project CarveApp` 호출에서 관측한 SwiftPM 모듈 의존성 오류와 artifact 서명 검증 이상은 별도로 기록했고 서로의 원인으로 단정하지 않는다.

먼저 reader/ownership 두 suite를 iPadOS 27.0에서 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/focused-reader-ownership.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacyRowLinkageReaderTesting \
  -only-testing:DomainTest/DrawingStoreOwnershipProofTesting
# TEST SUCCEEDED: 37 tests, 2 suites; exit 0
```

그 다음 동일 runtime에서 전체 회귀를 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/full-ios27.xcresult \
  -parallel-testing-enabled NO
# TEST FAILED, exit 65: 994 passed, 5 unexpected failures, 4 known issues, 5 device-only UI skips (1008 total)
```

전체 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/full-ios27.log`, 종료 코드는 `full-ios27.exit`다. 다섯 실패는 `ChapterCanvasControllerTesting.changelessToolUseIsCancelled` 1건과 SwiftData 관련 `LegacySeparationGateTesting` 1건, `LocalStoreLoadFailureTesting` 3건이다.

세 실패 suite를 iPadOS 27.0에서 한 번 더 좁게 재실행했다. 기본 sandbox 호출은 CoreSimulatorService 연결이 무효화돼 테스트 전 종료 코드 66을 반환했고, 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27-rerun/focused-failures-ios27-rerun.log`다. 서비스 접근이 가능한 재실행 명령은 다음과 같다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27-rerun-escalated/focused-failures-ios27-rerun.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacySeparationGateTesting \
  -only-testing:DomainTest/LocalStoreLoadFailureTesting \
  -only-testing:CarveFeatureTest/ChapterCanvasControllerTesting
# exit 65: ChapterCanvasControllerTesting 22/22 통과; Domain 2 suite 26 tests 중 4 issues
```

재실행에서 cancellation timing 실패는 나타나지 않았다. `LegacySeparationGateTesting.unversionedStoreIsMigratedButHeld` 1건과 `LocalStoreLoadFailureTesting` 세 건은 반복됐다. LocalStore 실패는 기대한 `loadIssueModelContainer` 대신 `unknownDataStoreSchema`가 나온 assertion 1건과 1.0.0~1.0.3 무버전 migration dynamic case 2건이다. 로그·exit·xcresult는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27-rerun-escalated/`에 보존했다. simulator diagnostic 수집이 600초 후 타임아웃되어 총 663.729초 만에 종료했다.

#### iOS 27 SwiftData 후속 수정 및 전체 회귀 (2026-09-24)

위 재현 뒤 `CarveApp.xcodeproj`가 없고 workspace가 9/12 생성본임을 확인했다. 기존 workspace와 `Tuist/.build/tuist-derived`를 `/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/preserved/`에 먼저 보존한 뒤 `mise x -- tuist generate --no-open`을 실행했다(exit 0). 첫 sandbox test 호출은 stale workspace 및 CoreSimulatorService 연결 문제로 exit 66, 테스트 0건이었다(`/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/focused-ios27.log`, `.exit`).

제품 로더는 iOS 27에서 새로 보고하는 `SwiftDataError.unknownDataStoreSchema`를 기존 `.loadIssueModelContainer`와 같은 legacy schema mismatch로 받아들이도록 수정했다. 폴백은 모델 해시가 정확히 확인된 1.0.x store에만 허용하고, 미확인 store/V7은 계속 차단한다. 테스트는 V7의 OS별 오류 이름을 모두 허용하되 V7 데이터 보존 기대는 유지한다. migration 관련 두 suite(26 tests)는 Xcode 27에서 iOS 17.5·18.6·26.2·27.0 각각 통과했다. 결과 경로는 `/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/focused-ios{17.5,18.6,26.2,27}-after-fix.{log,exit,xcresult}`다.

수정 뒤 첫 전체 iPadOS 27.0 run은 997 통과·1 SQLite `database is locked`·4 expected failure·6 skip으로 종료했다. `LegacyRowLinkageReaderTesting` 단독 suite는 31/31 통과해 잠금이 재현되지 않았고, 함수 단위 filter는 0건을 선택해 증거에서 제외했다. 후속 파일 제외 없는 전체 회귀는 **998 passed · 4 expected failures · 6 skips · 0 unexpected failures (총 1008)**로 통과했다. 전체 결과는 `/private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/full-ios27-rerun.{log,exit,xcresult}`에 있다. 이 로컬 회귀는 `validatedOSMajors`를 `[27]`로 바꾸지 않으며 live CloudKit proof나 배포 Archive·TestFlight를 대신하지 않는다.

후속 전체 회귀는 기본 선택된 Xcode 27.0에서 iPad mini (A17 Pro), iPadOS 27.0 build `24A434`, UDID `C72A6CC6-4E3C-4822-BED1-9D76F8542D6B`로 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=C72A6CC6-4E3C-4822-BED1-9D76F8542D6B' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-swiftdata-errors-20260924/full-ios27-rerun.xcresult \
  -parallel-testing-enabled NO
# TEST SUCCEEDED: 998 passed, 4 expected failures, 6 skipped, 0 unexpected failures (1008 total)
```

전체 로그와 종료 코드는 같은 디렉터리의 `full-ios27-rerun.log`, `full-ios27-rerun.exit`에 보존했다. DerivedData는 다른 runtime 검증과 공유했으며 `EXCLUDED_SOURCE_FILE_NAMES` 같은 소스 제외 설정을 주지 않았다.

실패 suite를 iPadOS 26.2에서 좁게 다시 확인했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=086F17F4-649B-4AE5-9C78-22659E0F93F6' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios26.2/focused-failures.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:DomainTest/LegacySeparationGateTesting \
  -only-testing:DomainTest/LocalStoreLoadFailureTesting \
  -only-testing:CarveFeatureTest/ChapterCanvasControllerTesting
# TEST SUCCEEDED: 48 tests, 3 suites; exit 0
```

마지막으로 같은 iPadOS 26.2 iPad destination에서 전체 회귀를 실행했다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=086F17F4-649B-4AE5-9C78-22659E0F93F6' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios27/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios26.2/full-ios26.2.xcresult \
  -parallel-testing-enabled NO
# TEST SUCCEEDED: 999 passed, 4 known issues, 5 device-only UI skips, 0 unexpected failures (1008 total)
```

iPadOS 26.2 전체 로그는 `/private/tmp/carve-2.0.0-xcode27-f60-20260924-test-ios26.2/full-ios26.2.log`, 종료 코드는 `full-ios26.2.exit`다. 당시 첫 iPadOS 27.0 전체 회귀는 다섯 실패로 끝났으나, 뒤이어 SwiftData 오류 분기 수정 후 재실행한 전체 회귀는 0 unexpected failure로 통과했다. 첫 검증 시점에는 Mac 잠금으로 Device Hub 수동 스모크를 못 했지만, 2026-09-24 잠금 해제 뒤 별도 새 simulator에서 reader startup과 인접 장 이동을 확인했다. ACC 표본·CloudKit 계정 로그인·필기 입력·의도적 서버 상태 변경은 없었다. 앱 시작 시 iCloud 필사 수신 대기 화면에서 “먼저 시작하기”를 눌러 빈 reader에 도달했고, 창세기 1장→2장→1장 이동이 표시됐다. 시작 과정의 백그라운드 네트워크 read는 계측하지 않아 CloudKit proof로 보지 않는다. 해당 smoke는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#device-hub-수동-ui-smoke-2026-09-24-자동-테스트와-별도)에 있다. 서명된 Archive·배포 entitlement·TestFlight도 미검증이므로 NO-GO를 유지한다. 전체 자동 로그, 결과 bundle, XCFramework 읽기 전용 서명 검사와 최초 F60 단계별 실패는 [호환성 시험 계획의 Xcode 27 기록](./icloud-sync-compatibility-test-plan.md#tuist-workspace-갱신-후-xcode-27-빌드회귀-2026-09-24)에 있다.

- 기존 전체 회귀는 Xcode 26.3 (17C529)에서 통과했다. 이는 비교용 과거 기준이며 현행 주 검증 대상은 기본 선택된 `/Applications/Xcode.app/Contents/Developer`의 Xcode 27.0 (27A266a)이다. Xcode 27 workspace iPadOS 18.6 Debug build와 iPadOS 26.2 전체 회귀는 통과했다. 최초 iPadOS 27.0 전체 회귀의 cancellation timing 실패는 focused 재실행에서 재현되지 않았고 SwiftData 관련 네 실패는 `.unknownDataStoreSchema` 대응 후속 수정으로 해결했다. 수정 후 두 migration suite는 iPadOS 17.5·18.6·26.2·27.0에서 각각 26/26 통과했고, iPadOS 27.0 파일 제외 없는 전체 회귀는 998 통과·4 expected failure·6 skip·0 unexpected failure다. iOS 27 소유 proof 허용은 별도 정책 게이트로 남아 있다. 상세 명령·로그·결과는 [호환성 시험 계획 Xcode 27 재검증](./icloud-sync-compatibility-test-plan.md#tuist-workspace-갱신-후-xcode-27-빌드회귀-2026-09-24)에 있다. 비교용 Xcode 26.3도 `/Applications/Xcode-26.3.0.app/Contents/Developer`에 설치돼 있고 Tuist는 4.208.0이다.
- 2026-09-24 확인에서 기본 Xcode 27의 `simctl list runtimes`와 `list devices available`이 동작했고, Xcode 26.3을 지정한 runtime 조회도 권한을 높인 뒤 성공했다. runtime은 17.5·18.6·26.2·26.4·26.5·27.0이었다. iPadOS 17.5 회귀에는 iPad mini (6th generation)를 사용했다. Device Hub 화면에는 iPadOS 27.2 실기기 iPad mini (A17 Pro)가 표시됐다. 별도 새 iPadOS 27.0 simulator에서 제한적 수동 smoke를 수행한 상세는 위에 기록했다. 기존 `Carve-2.0.0-test-legacy`와 ACC simulator는 이번 smoke에서 사용하지 않았다.
- 이 변경 전 iOS 18.3.1·18.6 집중 test-double suite 66/66 통과, iOS 26.2 Domain 452개(448 통과, 4 expected failure), SettingsFeature 54/54, CarveFeature 457/457, 앱 빌드 성공 결과가 있다. strict metadata profile 적용 뒤 live CloudKit proof는 재실행하지 않았다.
- strict reader 변경 뒤 최초 iOS 18.6 실행은 `productionClientClaimsVerifiedLegacySnapshot` 안에서 5 assertion이 실패했다. 테스트가 iOS 버전과 관계없이 성공을 요구했지만 production reader는 검증 범위 `[26]` 밖인 iOS 18에서 의도적으로 unknown을 반환하고 있었다. 이 정책 실패가 아니라 테스트 기대 오류여서 테스트를 OS-aware로 고쳤고 product 허용 범위는 바꾸지 않았다.
- 실패 뒤 reader 버전 기대값을 4로 고치고 metadata profile assertion을 추가했다. 이어받기 중 fixture의 raw SQLite 쓰기에서 서로 다른 테스트가 간헐적으로 `database is locked`를 냈다. `LinkageFixture.exec`에 테스트 전용 5초 SQLite busy timeout을 추가한 뒤 마지막 실행은 통과했다.
- 직전 산출물: `/private/tmp/carve-migration-sync-release-followup-ios18-derived`
- 직전 로그: `/private/tmp/carve-migration-sync-release-followup-ios18-build.log`, `/private/tmp/carve-migration-sync-release-followup-ios18-tests.log`
- 앞서 iOS 26.2 검증을 수행한 별도 환경의 runtime 목록에는 iOS 18.6이 없었다. 이후 사용자가 runtime을 설치해 아래 iOS 18.6 결과를 새로 얻었다.
- iPadOS 26.2 일반 iPad mini (A17 Pro)에서 `LegacyRowLinkageReaderTesting`, `DrawingStoreOwnershipProofTesting`, `DrawingEditEnvironmentTesting`, `RawStoreSnapshotTesting`, `MigrationSyncReleaseTesting` 다섯 suite를 새로 `build-for-testing`한 뒤 같은 DerivedData로 `test-without-building`했다: **67/67 통과, 실패·건너뜀 0**. `CarveApp` iPadOS 26.2 simulator 빌드도 성공했다. 기존 `Carve-ACC-dut`·`Carve-ACC-B`나 18.6 보존 simulator는 이 실행에서 사용하지 않았다.
- iPadOS 18.6 일반 iPad mini (A17 Pro, build 22G86)에서 같은 다섯 suite를 새로 빌드한 뒤 같은 산출물로 실행했다: **67/67 통과, 실패·건너뜀 0**. Domain 전체는 xcresult 기준 449 통과·4 expected failure·실패 0·건너뜀 0, SettingsFeature 54/54, CarveFeature 457/457도 빌드와 같은 산출물 실행 모두 통과했다. `Carve-Workspace` 앱 빌드도 iPadOS 18.6에서 성공했다.
- **전체 자동 회귀 재실행(2026-09-24):** Xcode 26.3 (17C529), Tuist 4.208.0, iPad mini (A17 Pro) iPadOS 18.6·26.2에서 각각 `Carve-Workspace` 전체 `xcodebuild test`를 재실행했다. 두 OS 모두 **997 passed · 4 expected failures · 5 skipped · 0 failed (1006 total)**이며 skip 5개는 실기기 전용 UI test다. iPadOS 26.2 집중 5 suite(`LegacyRowLinkageReaderTesting`, `DrawingStoreOwnershipProofTesting`, `DrawingEditEnvironmentTesting`, `RawStoreSnapshotTesting`, `MigrationSyncReleaseTesting`)도 **67/67 통과 · 실패·skip 0**. iPadOS 26.2 집중 첫 시도는 제외 설정을 셸 변수로 잘못 전달해 미추적 파일 컴파일 오류로 테스트 시작 전 실패했으며, 빌드 설정 인자로 고친 재실행은 통과했다. 결과 bundle은 `/private/tmp/carve-2-0-0-autotest-20260924-focused.xcresult`(실패한 첫 시도), `/private/tmp/carve-2-0-0-autotest-20260924-focused-retry.xcresult`, `/private/tmp/carve-2-0-0-autotest-20260924-full-ios18.6.xcresult`, `/private/tmp/carve-2-0-0-autotest-20260924-full-ios26.2.xcresult`; DerivedData는 `/private/tmp/carve-2-0-0-autotest-20260924-derived`다. 각 상세 명령은 [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md#지원-os-판독-후속-2026-09-23)에 있다.
- **iPadOS 17.5 최초 전체 자동 회귀(2026-09-24):** 사용자가 설치한 runtime을 확인하고 iPad mini (6th generation), UDID `0347221E-08F5-48C9-9F8E-6D7995C25D9F`, iOS build 21F79에서 `Carve-Workspace` 전체를 실행했다. 최초 결과는 **993 passed · 3 failed · 6 skipped · 4 expected failures (1006 total)**였다. 실패는 `DrawingDatabaseTesting/migrationV1toV2`, `LocalStoreLoadFailureTesting/unversionedStoreKeepsLegacyMigrationPath`의 1.0.0~1.0.3 dynamic case, `LegacyEntityNumberingTesting/v2ToV6KeepsCorrespondences`다. V1-only no-op 시험은 iOS 18·26에서만 관측한 동작이므로 iOS 17.5에서 조건부 skip했다. `actorInsert`는 테스트 전용 컨테이너로 격리해 단독 재검증 통과를 확인했다. 최초 결과와 xcresult 경로는 [호환성 시험 계획의 이력](./icloud-sync-compatibility-test-plan.md#ipados-175-최초-전체-회귀-2026-09-24-migration-수정-전), 수정 후 결과는 바로 아래 후속 기록에 있다.
- **migration 수정 후 후속 검증(2026-09-24):** V1 `willMigrate`에서 destination SwiftData model을 생성하던 코드를 Sendable DTO 전달로 바꾸고, V2 이상 저장소에는 저장소 시작 버전에 맞춘 V2→V6 plan을 선택했다. iOS 17.5·18.6·26.2에서 각각 **6/6 테스트 정의가 통과**했고, 동적 parameter case까지 포함한 실제 실행은 각각 7회였다. 이어 iOS 17.5 전체 회귀는 **998 passed · 0 failed · 6 skipped · 4 expected failures (1008 total)**다. 전체 결과 `/private/tmp/carve-2-0-0-full-after-migration-fix-ios17.5.xcresult`; OS별 집중 결과는 `/private/tmp/carve-2-0-0-migration-regression-ios17.5.xcresult`, `...ios18.6.xcresult`, `...ios26.2.xcresult`이며 상세 과정은 [호환성 시험 계획 후속 기록](./icloud-sync-compatibility-test-plan.md#ipados-175-migration-후속-검증-2026-09-24)에 있다. iOS 17.0 직접 시험, ownership proof, 실제 CloudKit 경로는 이 회귀에 포함되지 않는다.
- 전날 실행한 18.6 mini·26.2 mini·Air 전체 회귀 결과도 각각 **997 passed · 4 expected failures · 5 skipped · 0 failed**였고, blank/no-account 앱은 18.6 mini와 26.2 Air에서 FirstRunGuide까지 크래시 없이 도달했다. 그 안내 이후 필사 화면과 입력은 확인하지 않았다. 9/24 재실행에서는 새 UI smoke를 하지 않았다.
- `CarveApp` Release configuration simulator build는 성공했고 버전은 2.0.0 (build 1)이다. `CODE_SIGNING_ALLOWED=NO`였으므로 archive·배포 서명·entitlement 검증이 아니다. 이 모든 빌드에서는 아래의 미추적 파일을 제외했다.
- iOS 18.6 테스트는 `[26]` 범위 밖에서 `reading.isUnknown`, ownership `nil`, ledger 미생성을 확인한다. synthetic test fixture의 이 결과는 실제 iOS 18.6 1.3.0 표본의 추가 marker를 허용한다는 뜻이 아니며, `Carve-Ownership-iOS18-6` 또는 실제 CloudKit 계정을 사용하지 않았다.
- 미사용·미완성 `LegacyRowCorrespondence.swift` 초안은 실제 호출처가 없고 tracked `LegacyRowLinkageReader`와 역할이 겹쳐 source 경로에서 빼고 `/private/tmp/carve-legacy-row-correspondence-draft-20260924.swift`로 옮겼다. 이 초안에는 `Error` 미준수, `Int64`/`Int` 형식 오류와 `fatalError`가 있었다. 새 DerivedData에서 `EXCLUDED_SOURCE_FILE_NAMES` 없이 전체 회귀를 iPadOS 17.5·18.6·26.2에 실행해 각각 998/999/999 통과·실패 0을 확인했다. 상세 xcresult와 skip·expected failure 수는 [호환성 시험 계획의 후보 재검증](./icloud-sync-compatibility-test-plan.md#미완성-초안-이동-후-파일-제외-없는-회귀-2026-09-24)에 있다.
- iOS 26.2 산출물은 `/private/tmp/carve-migration-sync-release-26.2-intended-derived`; 로그·결과는 `/private/tmp/carve-migration-sync-release-26.2-final-build.log`, `/private/tmp/carve-migration-sync-release-26.2-locked-tests.log`, `/private/tmp/carve-migration-sync-release-26.2-locked-tests.xcresult`, `/private/tmp/carve-migration-sync-release-26.2-app-build.log`다. iOS 18.6의 집중·전체 로그와 결과 bundle 경로는 [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md#지원-os-판독-후속-2026-09-23)에 적었다. 모두 현재 머신의 임시 자료다.
- strict-profile 변경 뒤 live private CloudKit proof를 시도할 때 ACC simulator clone 앱 실행은 auto-review에서 기존 필기의 Development private DB 자동 전송과 서버 상태 변경 위험 때문에 거절됐다. clone에서 앱을 실행하지 않았고 원본 ACC simulator를 수정하지 않았으며 임시 clone은 삭제했다. 다른 실행 경로로 우회하지 않는다. 재개하려면 기존 필기 표본·시험 계정·Development private DB를 쓰고 변경할 수 있다는 명시적 사용자 승인이 필요하다. 또는 synthetic 표본·별도 시험 계정으로 시험을 재설계한다.
- 실제 private CloudKit ownership proof와 로그인 상태 1.3.0 업데이트 분기는 미실행이다. 현재 checkout에는 문서가 참조하는 `tools/cloudkit-observe` probe 스크립트도 없다. iOS 17.5 migration 회귀는 통과했지만 reader의 ownership proof 허용 OS는 여전히 `[26]`이다. iOS 17.0 직접 시험과 iOS 19~25도 미실행이다. `Carve-Ownership-iOS18-6` 계정less synthetic sample을 보존했고 로그인하지 않았다. NO-GO를 유지한다.
- iOS 18 marker 이름은 Apple 공개 문서 및 Xcode 26.3 Core Data simulator SDK headers에서 정의를 찾지 못했다. 공개 근거가 없어 reader allowlist `[26]`은 유지한다. 수정한 Swift test 두 파일의 SwiftLint와 문서 수정 후 `git diff --check`는 통과했다. Xcode build 단계의 저장소 범위 SwiftLint 경고와 이전 파일 경고는 남아 있다.

### Xcode 27 전체 회귀 추가 runtime (2026-09-25)

macOS `27.2 (26B5086k)`, 선택된 Xcode `27.0 (27A266a)`, Swift `6.4 (swiftlang-6.4.0.34.1)`, Tuist `4.208.0`에서 iPad mini simulator로 `Carve-Workspace` 전체 테스트를 추가 실행했다. 설치된 runtime 여섯 개(iPadOS 17.5·18.6·26.2·26.4·26.5·27.0)에서 모두 총 1008건·예기치 않은 실패 0으로 통과했다. 전체 로그·종료 코드·xcresult를 runtime마다 분리했고, source 제외 설정을 주지 않았다. ACC 표본, iCloud 로그인, CloudKit 서버 변경은 없었다.

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=0347221E-08F5-48C9-9F8E-6D7995C25D9F' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios17.5/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios17.5/full.xcresult \
  -parallel-testing-enabled NO
# iPad mini (6th generation), iPadOS 17.5 (21F79): 998 passed, 4 expected failures, 6 skipped, 0 failed (1008 total)
```

```bash
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -configuration Debug \
  -destination 'platform=iOS Simulator,id=7E95B700-3976-42D7-BF85-BCAF028B7605' \
  -derivedDataPath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios18.6/DerivedData \
  -resultBundlePath /private/tmp/carve-2.0.0-xcode27-full-20260925/ios18.6/full.xcresult \
  -parallel-testing-enabled NO
# iPad mini (A17 Pro), iPadOS 18.6 (22G86): 999 passed, 4 expected failures, 5 skipped, 0 failed (1008 total)
```

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

네 실행은 exit 0이고 xcresult summary는 `Passed`, unexpected failure 0, runtimeWarnings 없음이다. 전체 로그와 종료 코드는 각각 위 runtime 폴더의 `.log`와 `.exit`다. iOS 17.5 `full.log`에는 simulator `data/tmp` 안의 UUID 임시 migration/store fixture와 `-wal`/`-shm` 파일을 가리키는 `vnode unlinked while in use` 및 `invalidated open fd` 경고가 각각 382건 있다. 테스트는 통과했고 경고가 컨테이너 수명·fixture 정리 시점에서 생겼는지는 로그만으로 확정하지 않았다. iOS 18.6·26.4·26.5에서는 같은 경고가 보이지 않았다. 26.4는 최초 sandbox 실행의 CoreSimulatorService 오류(exit 66), 이어진 결과 bundle 경로 충돌(exit 64) 뒤 별도 `retry.xcresult`에서 통과했으며, 앞선 bundle은 보존했다. 세부 runtime별 기록 및 앞서 통과한 iPadOS 26.2·27.0 결과는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#xcode-27-전체-회귀-추가-runtime-2026-09-25)에 있다.

## 이어서 할 일

Xcode 27 workspace build와 iPadOS 17.5·18.6·26.2·26.4·26.5·27.0 전체 자동 회귀는 통과했다. 26.5에서는 same-account existing-store proof, historical 1.3.0 cloud-backed V3 → Xcode 27 2.0.0 clone update, 그리고 별도 무계정 Genesis 1:31 synthetic row의 first-login export·peer simulator 수신을 확인했다. 좁은 ownership/migration 두 suite도 37/37 통과했고, 2026-09-25 `SingleCanvasRollbackTesting`은 iPadOS 26.5에서 9/9 통과해 synthetic decode 실패 행의 원본 비덮어쓰기 경로를 재확인했다. method-level filter가 0건을 선택한 첫 시도는 무효로 별도 보존했다. Genesis 1:10–12의 실제 22B 표본은 격리 raw-PencilKit harness에서 macOS 27.2·iPadOS 26.5·27.0 모두 0획 빈 drawing으로 decode됐다. 따라서 최초 앱 로그의 undecodable 경고와 직접 decode 결과의 불일치는 남아 있지만 플랫폼별 PencilKit decode 실패를 재현한 것은 아니다. SwiftData 오류 분기 수정 뒤 iPadOS 27.0 전체 회귀 결과는 998 통과·4 expected failure·6 skip·unexpected failure 0이다. 다음은 iOS 18 marker 근거, iOS 17.0 직접 회귀, 실제 peer iPad 표시, App Store 배포 서명 Archive/export·Production entitlement·TestFlight 게이트다. first-login sample의 독립 read-only server inventory는 미수집이고, DrawingCodec의 앱-level 경고와 동일 표본 direct API 사이 불일치는 별도 검토가 필요하다. `-project CarveApp` generic 빌드의 모듈 해석 실패와 XCFramework read-only signature 이상은 workspace 빌드에서 재현되지 않은 `ProcessXCFramework` 실패의 원인으로 단정하지 않는다. Xcode 26.3 과거 통과는 현행 기준 통과로 바꾸어 쓰지 않는다. Device Hub 수동 스모크는 새 iPadOS 27.0 simulator reader 이동과 두 iPadOS 26.5 clone의 읽기 관찰을 자동 build/test와 별도로 기록한다. 후속 peer reader에서는 Page Down만으로 Genesis 1:31 sample 필기 한 줄을 확인했다. 물리 iPad mini (A17 Pro)는 iPadOS 27.2이며 TestFlight `2.0.0 (220)`이 설치돼 있다. 교체 승인은 받았지만 Release 앱의 CloudKit environment가 불명확하고 Debug device build 서명 검증은 `CSSMERR_TP_NOT_TRUSTED`로 실패해 설치·실행하지 않았다. 자동·기기 데이터는 변경하지 않았으며 서명 검증을 우회하지 않는 조건에서 물리 후보 smoke는 계속 미실행이다.

1. reader allowlist `[26]`을 유지한다. Xcode 27 iOS 18.6 no-account V3 local migration에서 synthetic 298B payload와 Preservation snapshot은 보존됐다. 최초 축소 Device Hub 화면에서 놓친 Genesis 1:1 획은 후속 read-only CanvasDisplayProbe와 확대 화면에서 확인돼, 최초 미표시 관찰은 철회했다. store의 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey` 의미는 여전히 미확인이고 live iOS 18 ownership proof도 미실행이다. Xcode 27 simulator SDK에서도 해당 정의를 찾지 못했다. 근거 없이 marker를 allowlist에 추가하지 않는다.
2. Xcode 27 iPadOS 26.5 ACC sandbox의 기존 private-store proof, 이미 계정에 연결된 historical 1.3.0 V3 store의 2.0.0 clone upgrade, 무계정 V3 Genesis 1:31 synthetic row의 first-login export·peer simulator 수신을 제한 범위에서 확인했다. 기존-store 경로는 `currentPrivateCloudRecords`, 20개 row/record-name hash, pending 0, payload multiset 일치와 focused tests 37/37을 확인했다. 무계정 sample은 로그인 전 peer 20행/1:31 부재, 로그인 뒤 peer 21행/같은 payload와 pending 0이었다. 새 sample의 직접 read-only server inventory hash와 physical iPad 수신은 미확인이다. `cktool query-records` 재시도는 서버 접근 전 keychain에서 사용자 token을 읽지 못해 `status: -50`으로 중단됐다. iCloud/Xcode 로그인과 cktool User token은 별도이므로, token 원문을 chat에 공유하지 않고 CloudKit Console token을 keychain에 저장한 뒤 Development private-zone query를 재개한다. 계정 전환 없이 진행했으며 Development sandbox 결과를 production CloudKit proof로 확대하지 않는다.
3. iOS 17.5 runtime과 iPad mini (6th generation)는 확보했고 migration 수정 후 전체 회귀가 0 failed로 통과했다. 다음은 iOS 17.0 직접 회귀와, 별도 증거가 있는 경우에만 ownership proof의 OS allowlist `[26]` 확장 여부 및 iOS 17 CloudKit proof를 검토하는 것이다. iOS 19~25는 아직 직접 시험하지 않았다.
4. 위젯 보관·이력 복원·N-Canvas의 별도 CloudKit 왕복, pending/local-only export를 동반한 update는 미검증이다. 무계정 first-login은 synthetic 단일 행의 simulator 2대 경로만 확인했다. 이때 쓴 historical 1.3.0 artifact는 Xcode 27에서 재빌드하지 않았다. imported Genesis 1:10–12 여덟 22B row는 이전 앱 로그에서 undecodable로 표시됐지만, 같은 보존 snapshot payload를 raw-PencilKit harness로 읽은 결과 macOS 27.2·iPadOS 26.5·27.0 모두 0획 빈 drawing이었다. 같은 보존 22B payload를 Xcode 27 iPadOS 17.5·18.6·26.5·27.0 `DrawingCodec.compose` focused suite에 전달한 결과 각 13/13 passed, row active 유지·output 0 strokes로 raw API뿐 아니라 코덱 decode 분기도 실패하지 않았다. 그러나 앱 warning 당시 repository snapshot bytes/hash와 보존 snapshot이 같았는지 관측하지 못해 앱 load/composition 입력 불일치와 사용자 화면 영향은 미확정이다. focused `SingleCanvasRollbackTesting` 9/9는 별도로 synthetic decode 실패 행을 덮지 않는 보호를 확인한다. 기존 C14 F44~F57 기록은 출시 완료 근거로 승격하지 않는다.
5. 사용자는 2026-09-25 ACC 데이터 변경을 명시적으로 승인했다. 복제본도 Development private DB를 공유한다. 기존 inventory proof에서는 두 완료 조회 사이 같은 20개 지문을 확인했다. 후속 first-login 검증에서는 synthetic Genesis 1:31 테스트 row 한 개를 의도적으로 업로드했고 CloudKit sandbox에 남아 있다. `Carve-ACC-B` 원본 simulator는 종료 상태로 보존했다. 향후 ACC 작업도 계정 전환이나 auto-review 우회 없이 진행한다. `Carve-Ownership-iOS18-6`의 계정 없는 synthetic 표본과 원본 Genesis 1:1·1:2 표본은 보존한다.

추가 로그·문서·프롬프트에 iCloud 계정 식별 원문, 이메일, 토큰 또는 비밀정보를 적지 않는다. 계정 로그인은 사용자가 같은 계정으로 복제본과 Xcode 27에 로그인해 이번 proof를 완료했다. 이후 별도 로그인이나 계정 전환이 필요한 작업은 진행 전에 사용자에게 단계와 예상 데이터 영향을 설명한다. 계정less iOS 18.6 sample은 현재 상태를 보존한다.

다른 컴퓨터에서 이어갈 때는 이 문서와 [출시 범위](./release-2.0.0-migration-sync-scope.md), [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md)을 읽고 현재 checkout·툴체인·시뮬레이터 상태를 다시 확인한다. 위의 보존 표본과 CloudKit 승인 제한을 그대로 적용한다.
