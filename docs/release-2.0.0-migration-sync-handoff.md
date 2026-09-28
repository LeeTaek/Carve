# Carve 2.0.0 iCloud 동기화 인계

> **다른 컴퓨터에서 이어받을 때:** [2026-09-27 최신 인계](./release-2.0.0-cross-machine-handoff-2026-09-27.md)를 먼저 읽는다. 아래 첫머리의 9월 26일 미완료 목록과 본문의 날짜별 상태는 과거 관측이다. 27일 현재 실제 iPadOS 18.6 첫 로그인 Development 서버 전송·독립 peer 수신과 재연결 코드/CLI 검증이 추가됐지만, iPadOS 17.5 실제 표본과 실행 중 첫 로그인 live 검증이 남아 출시 **NO-GO**다.

작성: 2026-09-23 · 실험 기록 추가: 2026-09-26 · 당시 작업 브랜치: `codex/2-0-0-migration-sync-release` (현재 checkout은 별도 확인)

## 현재 판정

> **최신 상태(2026-09-26):** reader v5는 iPadOS major `[17, 18, 26]`을 판독한다. Xcode 27/macOS 27.2 `DomainTest` ownership/migration suites는 iPadOS 17.5·18.6에서 각각 46/46 통과했다. 앱은 ownership preflight 전에 `.private` store를 열지 않으며, metadata marker의 private 의미를 해석하지 않는다. 새 독립 iPadOS 18.6 peer 실행에서는 CloudKit runtime이 `No account`를 반환해 업로드·수신을 시도하지 않았다. 독립 서버 payload·peer 표시, existing linked same-account update, live mismatch 경로 및 Device Hub smoke는 미완료여서 출시 **NO-GO**다. 아래 9/25 수치와 이전 상태 문장은 날짜가 붙은 과거 관측이며, 최신 수정 세부는 [최신 ownership 핸드오프](#2026-09-26-최신-ownership-판정검증-핸드오프)를 따른다.

2026-09-26 코드 상태: `LegacyRowLinkageReader.version == 5`, `validatedOSMajors == [17, 18, 26]`. 다음 본문의 2026-09-25 당시 `[26]` 및 iOS 18 fail-closed 문장은 역사적 상태다. 실제 관측된 추가 migrator metadata key는 정확한 profile variant와 정수 boolean `true` 형식으로만 받아들이며, key의 의미를 완료·진행으로 해석하지 않는다. 소유권은 계속 행 대응·현재 계정 identity·private CloudKit record 확인으로 판정한다. 좁은 reader/proof/environment suites는 iPadOS 17.5·18.6에서 각각 51/51 통과했다. **후속 live 확인:** 사용자의 재로그인 뒤 iOS 18.6 target에 `firstLoginFromUnaccountedV3` proof가 생겼고 preserved V3 payload와 현행 row payload가 298B byte-for-byte 일치했다. local record metadata는 row를 pending 없이 export 완료한 상태로 보고했지만 독립 peer 수신은 실패했다. same-scope 기존 peer 앱 run 뒤 로컬 행 수가 21→2로 달라진 원인을 확인하지 못해 앱을 종료했다. 별도의 빈 iPadOS 18.6 peer를 설치했으며 사용자의 같은 계정 직접 로그인을 기다리고 있다. 실제 server record 존재·peer 수신·표시까지 확인하지 못했으므로 출시 gate는 계속 **NO-GO**다. 최신 증거는 호환성 시험 계획의 2026-09-26 항목을 참조한다.

출시 판정은 **NO-GO**다. production 저장소 소유 증명 공급자는 연결했고 증거가 맞지 않거나 읽히지 않으면 계속 fail-closed 한다. 현재 `LegacyRowLinkageReader.validatedOSMajors`는 `[26]`이다. **현행 주 검증·출시 후보 자격 확인 대상은 macOS 27.2 / Xcode 27.0이며, Device Hub는 기기 확인·수동 스모크에 사용한다.** Xcode 27에서 Tuist workspace Debug iPad simulator 빌드가 통과했고, iPadOS 17.5 전체 회귀는 **998 passed · 4 expected failures · 6 skips**, 18.6·26.2·26.4·26.5는 각각 **999 passed · 4 expected failures · 5 skips**, 27.0은 **998 passed · 4 expected failures · 6 skips**로 설치된 여섯 runtime 모두 총 1008건·예기치 않은 실패 0이다. 17.5 로그에는 임시 migration/store fixture 관련 SQLite 경고가 있으나 xcresult failure/runtime warning은 없고 정리 시점 원인은 미확정이다. 최초 F60의 XCFramework `ProcessXCFramework` 실패는 재현되지 않았다. iOS 27 SwiftData 네 실패는 새 `unknownDataStoreSchema` 오류를 확인된 1.0.x metadata shape에 한해 처리한 뒤 해결됐다. 첫 수정 후 전체 실행에서 reader fixture의 SQLite 잠금이 한 번 발생했으나 reader suite 단독 31/31과 후속 전체 회귀에서 재현되지 않았다. 개별 `-project CarveApp` 명령의 SwiftPM 모듈 의존성 오류와 읽기 전용 artifact 서명 이상은 확인했으나 서로의 인과관계는 미확정이다. Device Hub에서 새 iPadOS 27.0 simulator의 창세기 1장 reader 표시와 1장→2장→1장 수동 이동을 확인했지만, 앱 시작 때 iCloud 필사 수신 대기 상태를 표시했으므로 CloudKit 검증으로 세지 않는다. Xcode 26.3 결과는 비교 기준으로 보존하며 Xcode 27 검증으로 대신하지 않는다. iOS 19~25 runtime은 현재 목록에 없다.

2026-09-25 Xcode 27 iPadOS 26.5 기존 private store proof는 첫 계정 확인 실패 뒤 사용자가 같은 ACC sandbox account를 복제 simulator와 Xcode 27에 로그인해 재개했다. ACC-B 원본은 종료 상태로 보존하고 clone에서만 진행했다. 읽기 전용 private-zone inventory 20개와 로컬 record name hash 20개가 일치하고, 재조회 inventory 지문도 같았으며, pending 0·Genesis 1:1/1:2 payload 보존·`currentPrivateCloudRecords` ownership marker를 확인했다. 이어 same-account proof clone을 분리 복제해 historical 1.3.0(1) 앱 bundle을 설치·실행한 뒤 Xcode 27 Debug 2.0.0으로 업데이트했다. 20개 cloud-backed V3 row, 무결성 `ok`, pending export 0, payload·record-name hash set 일치와 새 `currentPrivateCloudRecords` marker를 확인했고 focused two-suite CLI 회귀는 37/37 통과했다. 이 앱 화면은 Device Hub에서 별도 관찰했으며 기존 필기 몇 개가 보였지만 첫 실행 안내·AdMob 팝오버를 남긴 읽기 관찰뿐이다. historical 1.3.0 bundle은 Xcode 27에서 새로 빌드한 것이 아니다. 별도로 Xcode 27 iPadOS 18.6의 새 계정 없는 simulator에서 synthetic 1.3.0 V3 한 행을 2.0.0으로 로컬 migration했고 298B payload와 원본 Preservation snapshot이 보존됐다. 최초 Device Hub 화면은 일시 오버레이가 열린 축소 화면에서 획을 놓쳤으나, 후속 read-only CanvasDisplayProbe에서 store와 canvas의 한 획·bounds가 같고 diff 0임을 확인했다. 오버레이를 닫고 Device Hub를 확대하자 Genesis 1:1 획이 보였고 1→2→1 이동 뒤에도 표시됐다. 이 단일 오프라인 표본의 화면 확인은 통과로 정정하되 2.0.0 store에 의미 미확인 migration marker가 추가돼 iOS 18은 계속 fail-closed다. 무계정 local-only row의 first-login 업로드·peer 수신은 아래의 제한된 Xcode 27 synthetic 결과로 보완했다. production CloudKit·iOS 17 및 배포 검증은 미완료다. 상세 명령·로그 경로와 첫 시도 경위는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)을 참조한다.

2026-09-25 후속으로 새 iPadOS 26.5 no-account simulator에서 historical 1.3.0 V3 Genesis 1:31 synthetic row 한 개를 Xcode 27 2.0.0으로 업데이트한 뒤 같은 ACC sandbox 계정에 로그인했다. 앱 로그의 Core Data export는 `success=1, madeChanges=1`이고, 로그인 후 store는 21 drawing/metadata row, sample payload 300B와 기존 SHA-256, pending 0, `firstLoginFromUnaccountedV3` marker를 보였다. 별도 peer clone은 실행 전 20 row이며 1:31 row가 없었고, 실행 후 21 row와 동일 payload·pending 0을 보였다. 이로써 해당 synthetic row의 첫 로그인 업로드와 peer simulator 수신을 확인했고, 후속 Device Hub manual reader에서 Genesis 1:31 필기 한 줄도 관찰했다. 키보드 Page Down만 사용했으며 이 UI 확인은 자동화 테스트와 분리했다. 앱 종료 뒤 읽기 전용 store integrity·payload·pending도 보존됐다. 그 historical no-account V3 sample의 독립적인 read-only CloudKit inventory는 수집하지 못했다. 첫 로그인 앱 로그는 기존 Genesis 1:10–12의 8개 22B row를 undecodable로 표시했다. 그러나 이후 보존된 동일 snapshot bytes를 격리한 harness에서 다시 읽은 결과 macOS 27.2·iPadOS 26.5·iPadOS 27.0 모두 `PKDrawing(data:)` decode 성공·0 strokes였다. 그러므로 현재 증거는 PencilKit 플랫폼 차이를 재현하지 않으며, 앱 로그와 직접 API 검사 사이의 불일치는 `DrawingCodec.compose` 시점의 입력·상태를 보지 못해 미해결이다. 행은 편집·덮어쓰기하지 않았다. CloudKit Development sandbox에는 synthetic Genesis 1:31 테스트 row가 남아 있으며 삭제하지 않았다. 상세 명령·로그와 snapshot은 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)을 따른다.

2026-09-25 Xcode 27 generic iOS Release Archive도 생성됐다. `xcodebuild archive`와 `codesign --verify --deep --strict`가 각각 exit 0이지만 Archive는 Apple Development identity와 `get-task-allow=true` Development profile을 사용했다. 현재 로컬에는 Apple Distribution identity와 이 bundle의 App Store profile이 없고 signed app entitlement에 CloudKit environment가 설정되지 않아, 이 산출물은 배포 서명·Production CloudKit 증거가 아니다. `xcodebuild -exportArchive`와 TestFlight 업로드는 실행하지 않았다. 전체 로그·Archive 경로와 정확한 CLI는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)의 Xcode 27 Release Archive 절을 따른다. 배포 Archive/export·Production entitlement·TestFlight 게이트는 계속 NO-GO다.

같은 날 Device Hub에서 물리 iPad mini (A17 Pro) iPadOS 27.2를 확인했다. 설치 앱은 TestFlight `2.0.0 (220)`이었다. 사용자는 교체를 승인했지만, 사전 점검에서 Release 구성의 signed app CloudKit environment가 불명확했고, 초기 Debug 기기 빌드는 `CSSMERR_TP_NOT_TRUSTED`로 실패했다. 이후 계정 상태 갱신으로 Apple Development identity가 유효해져 재빌드·strict codesign 검증은 통과했으나, signed app의 CloudKit environment entitlement가 없어 Development/Production을 한정하지 못해 앱은 설치·실행하지 않았다. TestFlight 앱과 기기 데이터는 그대로이고 물리 후보 smoke는 미실행이다. 상세 명령·로그 및 blocker는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#물리-ipad-후보-설치-사전-점검-후속-2026-09-25)에 있다. Device Hub 관찰은 자동 테스트 결과에 포함하지 않는다.

2026-09-25 Xcode 27의 Xcode Cloud Report Navigator에서 `DevelopBranch` build 220의 기존 결과를 읽기 전용으로 확인했다. 이 run은 Xcode `26.6 (17F113)` / macOS `26.3 (25D125)`이며 Build·Test·Archive는 완료, TestFlight Internal Testing 단계는 조회 시 `Running… / In Progress`로 표시됐다. 마지막 커밋은 `c466f8066b2a57900c6ea105500f8bd002419efd`이고 물리 기기에 실제 설치된 `2.0.0 (220)`은 사용자가 말한 기존 TestFlight 배포와 일치한다. workflow 편집 화면에서 TestFlight action이 있는 `DevelopBranch`는 Xcode 26.6, 배포용 `MAIN`은 Xcode 26.3이며 Build·Archive만 있고 TestFlight action이 없음을 확인했다. DevelopBranch에는 `FORCE_BUILD_RESET=1`이 설정돼 있다. 저장소 pre-xcodebuild script도 빈 `.last_version` 또는 이 변수가 있으면 build number `1`을 정하고 ASC 조회를 건너뛴다. 따라서 현재 workflow/script 상태로 Xcode 27 후보를 trigger하면 툴체인과 build number 모두 위험하다. 편집 화면에서 저장한 변경이나 build trigger는 없다. 기존 Xcode Cloud 배포 성공과 로컬 Xcode 27 Debug 서명 오류는 별개다. Xcode 27 후보 생성을 위한 최소 workflow/CI 수정안과 근거는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#xcode-cloud-testflight-build-220의-툴체인-확인-2026-09-25)에 있다. 후보의 배포 서명·Production entitlement·기기 smoke는 미완료다.

사용자는 iOS 17.5 update-probe의 Apple Account를 바꿀지 물었으나, 그 기기는 CloudKit `userToken`이 등록된 현재 계정으로 유지하는 편이 맞다. 앞서 확인한 20행 historical V3 보존 표본은 다른 identity에 이미 연결된 linked store다. 그 표본 계정으로 바꾸면 무계정 V3의 첫 로그인 경로를 검증하지 못하고 현재 등록된 token으로 서버 대조도 할 수 없다. 기기 계정은 바꾸지 않았고 대체 무계정 historical V3 표본 위치는 아직 받지 못했다.

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

Xcode 27 workspace build와 iPadOS 17.5·18.6·26.2·26.4·26.5·27.0 전체 자동 회귀는 통과했다. 26.5에서는 same-account existing-store proof, historical 1.3.0 cloud-backed V3 → Xcode 27 2.0.0 clone update, 그리고 별도 무계정 Genesis 1:31 synthetic row의 first-login export·peer simulator 수신을 확인했다. 좁은 ownership/migration 두 suite도 37/37 통과했고, 2026-09-25 `SingleCanvasRollbackTesting`은 iPadOS 26.5에서 9/9 통과해 synthetic decode 실패 행의 원본 비덮어쓰기 경로를 재확인했다. method-level filter가 0건을 선택한 첫 시도는 무효로 별도 보존했다. Genesis 1:10–12의 실제 22B 표본은 격리 raw-PencilKit harness에서 macOS 27.2·iPadOS 26.5·27.0 모두 0획 빈 drawing으로 decode됐다. 따라서 최초 앱 로그의 undecodable 경고와 직접 decode 결과의 불일치는 남아 있지만 플랫폼별 PencilKit decode 실패를 재현한 것은 아니다. SwiftData 오류 분기 수정 뒤 iPadOS 27.0 전체 회귀 결과는 998 통과·4 expected failure·6 skip·unexpected failure 0이다. 다음은 iOS 18 marker 근거, iOS 17.0 직접 회귀, 실제 peer iPad 표시, App Store 배포 서명 Archive/export·Production entitlement·TestFlight 게이트다. historical no-account V3 sample의 독립 read-only server inventory는 미수집이다. 별도 current-identity Genesis 1:31 sample은 Development server record/payload와 독립 peer simulator 수신까지 확인했다. DrawingCodec의 앱-level 경고와 동일 표본 direct API 사이 불일치는 별도 검토가 필요하다. `-project CarveApp` generic 빌드의 모듈 해석 실패와 XCFramework read-only signature 이상은 workspace 빌드에서 재현되지 않은 `ProcessXCFramework` 실패의 원인으로 단정하지 않는다. Xcode 26.3 과거 통과는 현행 기준 통과로 바꾸어 쓰지 않는다. Device Hub 수동 스모크는 새 iPadOS 27.0 simulator reader 이동과 두 iPadOS 26.5 clone의 읽기 관찰을 자동 build/test와 별도로 기록한다. 후속 peer reader에서는 Page Down만으로 Genesis 1:31 sample 필기 한 줄을 확인했다. 물리 iPad mini (A17 Pro)는 iPadOS 27.2이며 TestFlight `2.0.0 (220)`이 설치돼 있다. 교체 승인은 받았지만 Release 앱의 CloudKit environment가 불명확하고 초기 Debug device build는 `CSSMERR_TP_NOT_TRUSTED`였으나 후속 Xcode 27 계정 상태 갱신 후 빌드와 strict codesign 검증은 통과했다. CloudKit environment entitlement가 없어 설치·실행은 계속 보류했다. 자동·기기 데이터는 변경하지 않았으며 서명 검증을 우회하지 않는 조건에서 물리 후보 smoke는 계속 미실행이다.

1. reader allowlist `[26]`을 유지한다. Xcode 27 iOS 18.6 no-account V3 local migration에서 synthetic 298B payload와 Preservation snapshot은 보존됐다. 최초 축소 Device Hub 화면에서 놓친 Genesis 1:1 획은 후속 read-only CanvasDisplayProbe와 확대 화면에서 확인돼, 최초 미표시 관찰은 철회했다. store의 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey` 의미는 여전히 미확인이고 live iOS 18 ownership proof도 미실행이다. Xcode 27 simulator SDK에서도 해당 정의를 찾지 못했다. 근거 없이 marker를 allowlist에 추가하지 않는다.
2. Xcode 27 iPadOS 26.5 ACC sandbox의 기존 private-store proof, 이미 계정에 연결된 historical 1.3.0 V3 store의 2.0.0 clone upgrade, 무계정 V3 Genesis 1:31 synthetic row의 first-login export·peer simulator 수신을 제한 범위에서 확인했다. 기존-store 경로는 `currentPrivateCloudRecords`, 20개 row/record-name hash, pending 0, payload multiset 일치와 focused tests 37/37을 확인했다. 무계정 sample은 로그인 전 peer 20행/1:31 부재, 로그인 뒤 peer 21행/같은 payload와 pending 0이었다. 당시 기록한 historical no-account V3 sample의 직접 read-only server inventory hash와 physical iPad 수신은 미확인이다. 사용자가 처음 등록한 token은 App Store Connect Sandbox Apple Account 것이었으며, 앱 내 구입용 계정이라 CloudKit private DB identity가 아니다. 앞선 first-login upload 때 simulator의 실제 iCloud identity는 미확인이다. 사용자가 `Carve-X27-FirstLogin-20260925`에 iCloud 계정을 로그인하고 User token을 등록했다고 알린 뒤 read-only query를 재시도했다. 기본 CLI는 Keychain `status: -50`으로 멈췄고 권한 있는 CLI는 exit 0으로 끝났지만 지정한 Core Data zone과 `_defaultZone` 모두 `records: []`였다. 따라서 token은 CloudKit에 승인됐으나 해당 계정·Development container·두 zone·record type 조합에서 server row-name inventory는 비었다. Genesis 1:31 업로드 때 identity/environment/zone이 같았는지는 미확인이다. CloudKit 데이터 변경은 없었다. token 원문은 chat·로그에 저장하지 않는다. 다음에는 업로드를 수행한 실제 iCloud identity와 Development container/zone을 일치시키고 synthetic sample을 재확인해 독립 inventory를 다시 수집한다. 개발자용 CloudKit Development 결과를 production CloudKit proof로 확대하지 않는다. 상세 결과는 [호환성 시험 계획 §Genesis 1:31 Development CloudKit inventory](./icloud-sync-compatibility-test-plan.md)에 있다.
3. iOS 17.5 runtime과 iPad mini (6th generation)는 확보했고 migration 수정 후 전체 회귀가 0 failed로 통과했다. 다음은 iOS 17.0 직접 회귀와, 별도 증거가 있는 경우에만 ownership proof의 OS allowlist `[26]` 확장 여부 및 iOS 17 CloudKit proof를 검토하는 것이다. iOS 19~25는 아직 직접 시험하지 않았다.
4. 위젯 보관·이력 복원·N-Canvas의 별도 CloudKit 왕복, pending/local-only export를 동반한 update는 미검증이다. 무계정 first-login은 synthetic 단일 행의 simulator 2대 경로만 확인했다. 이때 쓴 historical 1.3.0 artifact는 Xcode 27에서 재빌드하지 않았다. imported Genesis 1:10–12 여덟 22B row는 이전 앱 로그에서 undecodable로 표시됐지만, 같은 보존 snapshot payload를 raw-PencilKit harness로 읽은 결과 macOS 27.2·iPadOS 26.5·27.0 모두 0획 빈 drawing이었다. 같은 보존 22B payload를 Xcode 27 iPadOS 17.5·18.6·26.5·27.0 `DrawingCodec.compose` focused suite에 전달한 결과 각 13/13 passed, row active 유지·output 0 strokes로 raw API뿐 아니라 코덱 decode 분기도 실패하지 않았다. 그러나 앱 warning 당시 repository snapshot bytes/hash와 보존 snapshot이 같았는지 관측하지 못해 앱 load/composition 입력 불일치와 사용자 화면 영향은 미확정이다. focused `SingleCanvasRollbackTesting` 9/9는 별도로 synthetic decode 실패 행을 덮지 않는 보호를 확인한다. 기존 C14 F44~F57 기록은 출시 완료 근거로 승격하지 않는다.
5. 사용자는 2026-09-25 ACC 데이터 변경을 명시적으로 승인했다. 복제본도 Development private DB를 공유한다. 기존 inventory proof에서는 두 완료 조회 사이 같은 20개 지문을 확인했다. 후속 first-login 검증에서는 synthetic Genesis 1:31 테스트 row 한 개를 의도적으로 업로드했고 CloudKit sandbox에 남아 있다. `Carve-ACC-B` 원본 simulator는 종료 상태로 보존했다. 향후 ACC 작업도 계정 전환이나 auto-review 우회 없이 진행한다. `Carve-Ownership-iOS18-6`의 계정 없는 synthetic 표본과 원본 Genesis 1:1·1:2 표본은 보존한다.

추가 로그·문서·프롬프트에 iCloud 계정 식별 원문, 이메일, 토큰 또는 비밀정보를 적지 않는다. 계정 로그인은 사용자가 같은 계정으로 복제본과 Xcode 27에 로그인해 이번 proof를 완료했다. 이후 별도 로그인이나 계정 전환이 필요한 작업은 진행 전에 사용자에게 단계와 예상 데이터 영향을 설명한다. 계정less iOS 18.6 sample은 현재 상태를 보존한다.

다른 컴퓨터에서 이어갈 때는 이 문서와 [출시 범위](./release-2.0.0-migration-sync-scope.md), [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md)을 읽고 현재 checkout·툴체인·시뮬레이터 상태를 다시 확인한다. 위의 보존 표본과 CloudKit 승인 제한을 그대로 적용한다.

## 2026-09-25 남은 게이트 재점검

기본 선택 Xcode는 여전히 `/Applications/Xcode.app/Contents/Developer`의 Xcode `27.0 (27A266a)`, Swift `6.4`, Tuist `4.208.0`이다. `simctl` runtime/device 목록은 성공했으며 iOS 17.0은 없다. iOS 17.5 결과는 17.0 결과로 대체할 수 없다. iOS 17.0 직접 simulator 회귀에는 iCloud 로그인이 필요하지 않지만, runtime이 제공되어 설치해야 한다. 같은 OS의 실제 ownership proof까지 할 때는 새 simulator에 기존 ACC와 같은 sandbox 계정으로 로그인하고 synthetic Development CloudKit 표본을 사용해야 한다.

초기 Xcode 27 계정 확인 당시 읽기 전용 서명 확인 결과 `security find-identity -v -p codesigning`은 `0 valid identities found`였고, 현재 Xcode profile store의 3개 CMS payload 중 Carve bundle App Store profile과 Production CloudKit entitlement는 0개였다. 예전 Development Archive는 현재 Distribution 배포 자격이 아니다. Xcode Cloud TestFlight build 220은 Xcode 26.6 결과이며, Xcode 27 후보를 만들려면 Xcode 27 환경을 실제로 선택한 Cloud workflow, 유효한 Apple Distribution 자격, Production CloudKit entitlement/environment가 따로 필요하다. workflow·signing 설정은 변경하지 않았다.

Genesis 1:10–12의 22B 행은 경고 전 `source-store`와 이후 `post-first-login-store`, 두 peer 전후 사본에서 모두 8행과 같은 payload SHA-256을 유지했다. 이는 저장된 표본이 전후에 바뀌지 않았다는 근거지만, warning 당시 앱 메모리의 compose 입력 및 화면 영향은 알 수 없어 결함 원인을 닫지 않는다. 이번 점검은 소스·DB·CloudKit을 변경하지 않고 빌드/테스트도 실행하지 않았다. 자세한 환경 표, 명령, 로그와 제한은 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#남은-게이트-사전-점검-및-22b-전후-snapshot-비교-2026-09-25)에 있다.

새 비밀번호 로그인은 필요하지 않다. Genesis 1:31의 독립 Development server inventory에는 ACC/Xcode 로그인과 별개인 CloudKit Console User token이 필요하다. 처음 등록한 token은 App Store Connect Sandbox Apple Account 것이므로 CloudKit private database identity가 아니었다. 이후 `Carve-X27-FirstLogin-20260925`에 계정 로그인·token 등록 후 권한 있는 read-only query는 exit 0이었으나 `records: []`였다. first-login upload 당시 실제 `Settings > Apple Account` iCloud identity 및 container/zone 정합성은 여전히 확인해야 한다. Development query 결과가 비어 있는 이유를 확인한 뒤 표본 inventory를 재개한다. token 원문은 대화·로그에 공유하지 않는다. iOS 18 marker의 무계정 synthetic lifecycle 비교 자체에는 CloudKit 로그인은 필요 없지만, 현재 simctl clone 경로가 원본 app store를 가리킨 이상 기존 simulator에서 clone 비교를 반복하지 않는다. 저장소 URL과 clone 경로 격리가 별도로 증명될 때까지 marker 결과를 보류한다.

## 2026-09-25 병렬 남은 게이트 점검

기본 선택 환경은 macOS `27.2`, Xcode `27.0 (27A266a)`, Swift `6.4`, Tuist `4.208.0`으로 재확인했다. `mise x -- tuist generate --no-open`과 read-only `xcodebuild -list -workspace Carve.xcworkspace`는 각각 exit 0이었다. 이번 turn에는 앱 build/test를 새로 실행하지 않았다.

두 iOS 27 runtime entry는 같은 identifier지만 build가 `24A5370g`·`24A434`로 나뉜다. 24A5370g root를 지정해 만든 simulator가 부팅 후 24A434로 보고해 정확한 런타임 검증이 아니므로 테스트는 시작하지 않았고 그 임시 simulator는 삭제했다. 상세 로그는 `/private/tmp/carve-x27-alt-runtime-20260925/`에 있다.

iOS 18.6 무계정 marker probe는 clone 실행 로그의 CoreData store URL이 원본 UDID의 app container를 가리켜 중단했다. 실행 뒤 원본 store에서 CloudKit setup 실패 event만 7→8로 늘었고, marker integer `1`, Genesis 1:1 298B payload/hash, row 개수와 DB integrity는 유지됐다. clone의 DB는 byte-identical이었으며 export operation·record metadata는 0이었다. simulator source·clone을 종료하고, 전체 원본 app container를 보존한 다음 원본을 clone 실행 전의 95-file snapshot과 byte-for-byte 복원했다. 복원 확인 `diff -qr` exit 0이다. 앱·문서는 바뀌지 않았다. clone 경로 이슈 원인은 미확정이며, 새로 clone 비교를 반복하거나 marker 통과로 기록하지 않는다. 상세 로그와 전후 snapshot은 `/private/tmp/carve-x27-ios18-marker-offline-20260925/`에 있다.

pending/local-only update gate는 아직 실행하지 않았다. 보존한 historical 1.3.0 (1) 앱은 ad-hoc signed이며 Team ID·profile·CloudKit entitlement가 없으므로 local migration 입력에만 쓸 수 있다. live pending export를 검증하려면 Development CloudKit entitlement가 확인된 old app artifact와 해당 simulator에만 적용되는 신뢰할 수 있는 네트워크 차단 수단이 필요하다. 2026-09-25 Xcode 27 Device Hub의 Controls·More Actions·inspector와 Simulator Developer 설정을 직접 확인했지만 선택 simulator의 네트워크 차단/Network Link Conditioner 제어는 찾지 못했다. 과거 Xcode의 Device Conditions 자료는 네트워크 shaping을 설명하지만, 현재 Xcode 27에서 100% 양방향 차단을 설정할 수 있다는 증거로 보지 않는다. Mac 전체 네트워크를 끊으면 다른 앱에도 영향이 있으므로 명시 승인을 받기 전에는 사용하지 않는다. 실행 시 새 전용 iPadOS 26.5 simulator에 같은 ACC sandbox 계정 로그인이 필요하고, Development server baseline/final 조회에는 별도의 CloudKit Console User token이 필요하다. 현재 artifact·네트워크 수단이 준비되지 않아 앱 실행이나 sample 생성은 하지 않았다. historical artifact 검사 로그는 `/private/tmp/carve-x27-historical-130-artifact-audit-20260925/read-only-audit-corrected.log`다.

따라서 iOS 18 marker/ownership, iOS 17.0 직접 회귀, 독립 Development server inventory, pending export update, Production CloudKit, Xcode 27 Distribution Archive/export·TestFlight 및 물리 후보 smoke는 계속 NO-GO다. 전체 명령, 제한과 snapshot 복구 기록은 [호환성 시험 계획의 2026-09-25 병렬 게이트 기록](./icloud-sync-compatibility-test-plan.md#병렬-남은-게이트-점검-및-ios-18-simulator-clone-격리-실패-2026-09-25)을 기준으로 한다.

## 2026-09-25 Xcode 27 직접 V3 migration suite

사용자의 요청에 따라 문서 점검만 반복하지 않고, Xcode 27에서 로컬 V3 migration 실행을 직접 검증했다. 시작 전 branch `codex/2-0-0-migration-sync-release`의 tracked 상태와 diff는 clean이었다. macOS `27.2`, Xcode `27.0 (27A266a)`, Swift `6.4 (6.4.0.34.1)`, Tuist `4.208.0`이며 iPad mini (A17 Pro), iOS `18.6 (22G86)` simulator에서 `Carve-Workspace` CLI 테스트를 수행했다.

앞선 fail-closed suites (`LegacyRowLinkageReaderTesting` 31/31, `DrawingStoreOwnershipProofTesting` 6/6, `MigrationSyncReleaseTesting` 5/5)에 이어 `LegacyStoreMigrationTesting` 3/3을 통과했다. 이 suite는 합성 V3 SQLite를 V4/V5로 열고 `SwiftDataDrawingRepository`에서 읽은 legacy 필기를 `DrawingCodec`으로 합성하며 편집·저장 후 기존 획 위치를 다시 확인한다. 그 결과 뒤에 실행한 `DrawingSchemaV4MigrationTesting` 11/11 및 `DrawingCodecLegacyMigrationTesting` 3/3도 통과했다. 이번 직접 실행 묶음은 **59/59 passed**, failed/skip/expected failure 0이다. 명령·xcresult·전체 로그는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#xcode-27-직접-v3-로컬-마이그레이션-회귀-2026-09-25)과 `/private/tmp/carve-x27-marker-focused-20260925/`, `/private/tmp/carve-x27-legacy-store-migration-20260925/`에 기록돼 있다.

이것은 임시 SQLite와 synthetic drawing만 사용한 unit-test 실행이며 ACC·CloudKit·Firebase app launch를 사용하지 않았다. 두 migration 로그에는 `NSManagedObjectModel` checksum 시점에 관한 CoreData `[error]` 진단이 있지만 xcresult runtimeWarnings는 0이다. 원인이나 실제 사용자 store 영향은 아직 조사하지 않았다. iOS 18 marker 의미, clone-based migration, iOS 17.0, live CloudKit/independent server inventory, Xcode 27 Distribution·TestFlight 및 물리 후보 smoke 결과로 확대하지 않는다.

다음 단계로 실제 1.3.0 앱에서 Xcode 27 2.0.0으로 전용 iOS 18.6 simulator update를 실행하려면 먼저 simulator 하나에만 적용되는 네트워크 차단을 확인해야 한다. 이번 Xcode 27 UI 확인에서는 해당 제어를 찾지 못했고 `simctl`에도 per-device network isolation 명령이 없다. 따라서 Mac 전체 네트워크 연결 해제는 다른 앱의 통신도 끊으므로 사용자의 명시 승인을 받기 전에는 수행하지 않고, 그동안 앱 install/launch는 보류한다. 별도 Development server inventory는 ACC/Xcode 로그인과 분리된 CloudKit Console User token이 계속 필요하다. Production CloudKit이나 signing/workflow 설정은 바꾸지 않았다.

### 2026-09-25 개발자 iCloud 계정 inventory 불일치 격리

사용자가 `Carve-X27-FirstLogin-20260925`에 개발자 iCloud 계정을 로그인하고 User token을 등록한 뒤 Development private DB의 `CD_BibleDrawing`을 `com.apple.coredata.cloudkit.zone` 및 `_defaultZone`에서 read-only 조회했다. 두 응답 모두 `records: []`이고 종료 코드는 0이다. 반면 해당 simulator의 로컬 `Carve.dev.sqlite`에는 drawing 21행과 CloudKit record metadata 21행이 있고 pending upload·export operation·exported object는 모두 0, DB integrity는 `ok`였다. 이 local/server 차이는 계정 또는 동기화 소유자 불일치 가능성을 남기지만 원인을 입증하지 않는다. 기존 앱을 다시 실행하거나 로컬 행을 변경하지 않았다. 세부 결과·로그 경로는 [호환성 시험 계획의 inventory 재확인](./icloud-sync-compatibility-test-plan.md#현재-개발자-icloud-계정의-cloudkit-inventory-재확인-및-격리-시뮬레이터-준비-2026-09-25)에 있다.

기존 21행을 현재 iCloud 계정에 섞지 않도록 새 빈 iPad mini (A17 Pro) iPadOS 26.5 simulator `Carve-X27-CloudKit-CurrentIdentity-20260925` (`D0E83844-A29A-4031-B174-9663A138CEEA`)를 준비했다. Xcode 27 Debug `2.0.0 (1)` 앱을 설치하고 Settings만 열었다. 앱은 아직 실행하지 않았고 CloudKit 데이터 변경은 없었다. 사용자가 이 전용 simulator에 동일 개발자 iCloud 계정으로 로그인하면 새 synthetic Genesis 1:31 한 행의 Development first-login upload와 독립 inventory를 진행한다. CloudKit schema export는 별도 management token이 없어 exit 64로 중단됐다. Server inventory, iOS 18 marker/ownership, offline update, Distribution Archive/export·TestFlight 및 물리 후보 smoke는 계속 미완료이며 출시 **NO-GO**다.

## 2026-09-25 current-identity Development inventory 후속

새 격리 simulator `Carve-X27-CloudKit-CurrentIdentity-20260925` (iPad mini, iPadOS 26.5)에서 Xcode 27 Debug `2.0.0 (1)`의 합성 Genesis 1:31 필기를 Development private CloudKit에 first-login export했다. CloudKit Console User token을 쓴 read-only `cktool` custom-zone inventory에서 local metadata와 같은 record name, `CD_verse=31`, `CD_drawingVersion=3`, `CD_isPresent=1`을 확인했다. 서버의 321-byte `CD_lineData`는 local `.externalStorage` SQLite raw blob의 첫 `0x01` byte를 제외한 321 bytes와 bytewise·SHA-256 일치 (`dba2e45b…e28496de`)한다. Core Data Export event는 success이고 local pending upload는 0이다. `_defaultZone`에는 record가 없다. 이는 Development private server proof이며 Production proof가 아니다. 전체 명령·로그는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#xcode-27-current-identity-development-first-login-및-server-payload-대조-2026-09-25)에 있다.

이번 peer import 뒤 Simulator UI에서 Genesis 1:31의 sample 표시를 수동 관찰했으며 자동 테스트 결과와 분리한다. Undo 뒤 남은 Genesis 1:5 빈 row는 Development server에 빈 record로 남아 있고 필기 payload 표본으로 세지 않는다. 기존 ACC peer에는 verse 31의 다른 record ID가 있어 새 표본의 peer 기준으로 쓰지 않았다. `simctl clone` 임시 장치가 원본 app container 경로를 가리켜 사용하지 않았다. 별도 iPadOS 26.5 peer `Carve-X27-CloudKit-Peer-CurrentIdentity-20260925` (`99987218-4E3C-471F-8000-7BFACC072452`)는 실행 전 store가 없었다. 사용자가 같은 개발자 iCloud 계정으로 로그인한 뒤 Xcode 27 Debug 앱의 CloudKit Setup과 Import가 성공했고, local DB integrity `ok`, Genesis 1:31 record name은 server와 같은 `7FA1F4D1-EBDE-4DD1-8687-5CD801914172`, normalized payload SHA-256은 `dba2e45b2762abd627907d43e6b1a53a6b678ba03d46a5f619b79a30e28496de`, pending upload 0이었다. peer 후속 server inventory도 custom zone에 같은 두 record ID만 반환했다. 앱 log, local store 검사, peer 전후 server query는 `/private/tmp/carve-x27-cloudkit-current-identity-20260925/`에 보존했다.

따라서 새 표본의 Development server inventory/payload 일치와 독립 peer simulator import는 확인했다. 기존 historical no-account 1.3.0 V3 sample의 독립 server hash는 여전히 미수집이다. 물리 iPad 수신, iOS 18 marker·ownership, iOS 17 ownership·17.0 직접 회귀, pending export update, Production CloudKit, App Store Distribution 서명 Archive/export·Xcode 27 TestFlight와 물리 후보 smoke는 계속 NO-GO다.

후속 focused CLI 회귀는 Xcode 27.0 / Swift 6.4, 별도 빈 iPad mini (A17 Pro) iPadOS 26.5 simulator에서 `DrawingStoreOwnershipProofTesting` + `MigrationSyncReleaseTesting` **11/11 passed**, failed·skip·runtime warning 0이었다. 첫 지정 simulator destination은 xcodebuild exit 70으로 테스트 전 거절되어 실행되지 않았고, 전체 시도 로그와 최종 xcresult는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#xcode-27-ownershipmigration-focused-cli-재실행-2026-09-25)에 기록했다. 이는 synthetic/local 회귀이며 live marker semantics나 물리·Production/Distribution gate를 닫지 않는다.

Xcode 27 계정 상태 갱신 후 물리 iPad 연결과 서명을 재확인했다. Apple Development identity 1개가 유효했고 iPadOS 27.2 실기기에 한정한 Debug build 및 `codesign --verify --deep --strict`가 모두 통과했다. 이전 `CSSMERR_TP_NOT_TRUSTED`는 해소됐다. 그러나 signed app의 `com.apple.developer.icloud-container-environment`가 빠져 있고 embedded Development profile은 Development·Production 모두를 허용하므로 CloudKit Development environment 한정은 증명되지 않았다. Info.plist의 container ID는 `.dev` 컨테이너지만 Apple 문서상 별도 environment entitlement가 런타임 환경을 고른다. 따라서 사용자의 TestFlight 교체 승인이 있어도 물리 iPad에는 설치하지 않았다. 기존 TestFlight `2.0.0 (220)`과 iPad data는 유지됐다. 전체 build/signing/profile/device read-only 로그는 `/private/tmp/carve-x27-physical-smoke-20260925/`에 있다. 다음 blocker는 코드 서명 검증이 아니라 Development-only CloudKit environment가 확인된 산출물이며, Distribution/TestFlight gate도 별도로 남는다.

## 2026-09-25 Xcode 27 iPadOS 18.6 앱 빌드 및 다음 차단점

현재 환경은 macOS `27.2 (26B5086k)`, Xcode `27.0 (27A266a)`, Swift `6.4.0.34.1`, Tuist `4.208.0`이다. 새 빈 iPad mini (A17 Pro) iOS `18.6 (22G86)` simulator에서 `DrawingStoreOwnershipProofTesting`과 `MigrationSyncReleaseTesting`을 CLI로 실행해 **11/11 통과**, 실패·skip·expected failure·xcresult runtime warning 0을 확인했다. 별도 iPad mini (A17 Pro) iOS 18.6 destination에서 Xcode 27 `CarveApp` Debug build도 **BUILD SUCCEEDED**, exit 0이다. 명령·경고·전체 로그 경로는 [호환성 시험 계획의 Xcode 27 iOS 18.6 기록](./icloud-sync-compatibility-test-plan.md#xcode-27-ipados-186-앱-컴파일-및-집중-회귀-2026-09-25)에 있다. 앱 설치·실행과 CloudKit/Firebase 데이터 변경은 하지 않았다. 이는 local focused test와 컴파일 근거이며 live ownership proof는 아니다.

서명 자격의 현재 read-only 상태는 앞선 physical Debug build 기록과 일치하지 않는다. `security find-identity -v -p codesigning`은 `0 valid identities found`를 반환했다. 두 표준 provisioning profile 저장 경로에서 찾은 프로파일 3개 중 정확한 Carve bundle profile 1개(Development/ad-hoc, `get-task-allow=true`, CloudKit environment `Development`·`Production`)만 확인했다. Apple Distribution identity와 App Store profile은 현재 로컬 상태에서 확인되지 않는다. 이전 물리 build 시점에 Apple Development identity 1개가 유효했다는 기록은 보존하되, 현재 조회에서 재현되지 않은 원인은 미확정으로 둔다. 인증서·profile·signing 설정을 만들거나 변경하지 않았다. Xcode 계정 로그인이 Distribution archive 자격으로 이어졌다고 추정하지 않는다.

오프라인 update blocker도 직접 다시 확인했다. `simctl` 도움말에 per-simulator network-off 명령이 없고, 계정 없는 임시 iOS 18.6 net-probe simulator의 Device Hub `Controls`에는 Home·Lock·Siri·App Switcher·회전·화면 캡처/녹화만 있었다. 네트워크와 Mac 연결은 변경하지 않았으므로 pending-export offline update는 실행하지 않았다. iOS 17.0 runtime도 설치돼 있지 않다. 따라서 iOS 18 marker/ownership, offline update, iOS 17.0 직접 회귀, Production CloudKit, Distribution Archive/export·TestFlight와 물리 후보 smoke는 계속 **NO-GO**다.

## 2026-09-25 출시 필수 게이트 재점검 — 현재 판정

사용자는 기존 1.3.0 → 2.0.0 지원 보장을 유지하고, iPadOS 17·18의 ownership proof에 근거가 생길 때까지 **NO-GO**를 선택했다. `LegacyRowLinkageReader.validatedOSMajors`는 여전히 `[26]`; iOS 18 V3에서 관찰한 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`는 의미가 확인되지 않았다. allowlist 확대·metadata 예외 추가·쓰기 안전장치 제거는 하지 않았다.

사용자가 Carve Development 시험 계정을 로그인한 전용 iPadOS 17.5 simulator에서 기존 1.3.0 앱을 실행해 첫 CloudKit import를 관찰했다. CloudKit setup과 importer 작업 로그는 성공했지만 로컬 V3 drawing row와 record metadata는 모두 0이고 창세기 1장 화면에도 필기가 없었다. 따라서 이는 실제 historical V3 사용자 표본을 받거나 표시한 증거가 아니며, 비어 있는 저장소를 업데이트해 성공으로 세지 않았다. 로그·화면·저장소 검사와 제한은 [호환성 시험 계획의 iOS 17.5 로그인 import 확인](./icloud-sync-compatibility-test-plan.md#2026-09-25-ipados-175-130-로그인-후-실제-cloudkit-가져오기-확인)에 있다.

필수 게이트 상태:

- **기존 필기 무유실 및 ownership proof (iPadOS 17·18): BLOCKED / 출시 NO-GO.** 실제 historical V3 행이 든 1.3.0 표본의 내용·좌표·화면 표시·재실행 보존을 확인하지 못했다. iOS 18 metadata marker도 미해결이다. 사용자는 지원 범위를 유지한 채 증거 확보 전 NO-GO를 선택했다.
- **옛 무계정 필기의 첫 로그인 전송: BLOCKED.** 기존 synthetic historical-V3 local/peer payload는 서로 일치하지만 같은 record의 독립 서버 payload 대조가 없다. Development 서버에서 검증한 321-byte 표본은 새 2.0.0 앱이 만든 표본이며 historical 1.3.0 필기가 아니다.
- **새 앱의 일반 동기화: PARTIAL.** 2.0.0 synthetic 표본은 Development 서버의 필드·payload와 일치하고 독립 peer import도 확인했다. 두 iPad에서 시간차 저장·수정·삭제를 양 방향 수신하는 최종 코드 증거는 아직 없다.
- **실패 시 원본/복구본 보존: PARTIAL.** 저장소 열기 전에 검증된 raw snapshot을 만드는 코드와 migration·snapshot 실패 테스트가 있다. 실제 pending CloudKit export 상태로 업데이트·실패를 주입한 앱 동작 증거는 없다. 현재 확인된 simulator 단독 네트워크 차단 수단이 없으므로 Mac 전체 네트워크를 끊지 않았다.
- **최종 Xcode Cloud/TestFlight 후보와 물리 iPad 핵심 smoke: BLOCKED.** 기존 TestFlight 2.0.0 (220)은 Xcode 26.6 산출물이다. 확인된 Xcode Cloud 보고서에도 Xcode 27 후보는 없다. Xcode 27 Distribution·Production CloudKit environment 서명이 확인된 후보, Production schema 비교, TestFlight 후보의 필기·필사 저장·재실행·동기화 smoke는 미완료다. 로컬 Apple Distribution identity 부재를 Cloud 배포의 별도 차단 근거로 삼지 않았다.

이번 직접 실기능 확인으로 소유 proof 차단이나 새 metadata 프로필을 해결하지 못했다. 새로 수행한 작업은 iOS 17.5 simulator 로그인 import 상태 관찰과 기록이며, 코드·dependency·CI·signing·build setting·Production schema는 변경하지 않았다. 앱은 계정이 로그인된 해당 simulator에 1.3.0 상태로 남아 있다. 사용자에게 이 Development 계정에 historical V3 표본이 있어야 하는지, 아니면 표본이 있는 다른 정확한 simulator/기기를 제공할 수 있는지 확인을 요청했다. 현재 전체 배포 판정은 **NO-GO**다.

### Xcode Cloud 후보 실행 전 build number 확인 필요 (2026-09-25)

확인된 기존 Cloud 보고서는 `DevelopBranch` build `220`, Xcode `26.6 (17F113)`, macOS `26.3 (25D125)`, 앱 `2.0.0 (220)`이다. Build/Test/Archive 완료 후 TestFlight internal testing 중인 상태였다. 보고서에 commit SHA, Cloud 서명 identity/profile, signed CloudKit container/environment 또는 Production schema inventory는 없어 검증되지 않았다. 현재 workflow의 Xcode selector와 automatic build increment도 확인되지 않았으며 저장소에는 workflow 설정 파일이 없다. 세부 보고서 UI를 읽기 위한 시도는 시간 초과로 완료되지 않았고 report export/log도 없다.

저장소 pre-xcodebuild script는 `.last_version`이 없으면 current `MARKETING_VERSION=2.0.0`을 빈 값과 다른 새 버전으로 판정하고 `TARGET_BUILD_NUMBER=1`로 설정한 후 App Store Connect 조회를 생략한다. `.last_version`은 `.gitignore`에서 제외되고 `ci_post_clone.sh`에도 복구 로직이 없다. 따라서 Cloud workflow의 auto-increment가 보정하는지 모르는 현재 상태에서 build를 trigger하면 기존 220 뒤에 1을 업로드할 위험이 있다. 이 위험은 로컬 Apple Distribution certificate 부재와 별개다.

현재 workflow의 Xcode 27 선택 여부와 자동 build number 증분·실제 pre-xcodebuild 로그를 read-only로 확인하기 전까지 push/trigger를 하지 않는다. 이 상태에서 최소 변경은 승인하지 않았고 CI/script, signing, build setting을 수정하지 않았다. command/script evidence 및 기존 report의 확인·미확인 항목은 [호환성 시험 계획의 Cloud build 220 audit](./icloud-sync-compatibility-test-plan.md#2026-09-25-xcode-cloud-build-220-및-후보-생성-경로-read-only-확인)에 있다.

### Historical V3 snapshot 재사용 조건 및 pending-export 중단 권한 (2026-09-25)

기존 historical 1.3.0 cloud-backed V3 보존 snapshot을 찾았다. 별도 `Carve-X27-ACC-Xcode27-LoginUpdate-20260925`의 Preservation 원본은 무결성 `ok`, drawing 20행·표시 대상 14행·CloudKit record metadata 20행이다. 이 snapshot의 private CloudKit identity와 사용자가 로그인한 iOS 17.5 target의 identity는 값을 노출하지 않은 내부 비교에서 달랐다. 현재 계정에 섞으면 안 되므로 복사·업로드하지 않았다. 정확히 같은 Development identity를 iOS 17.5 전용 target에서 사용하거나 다른 historical source를 지정해야 계정 소유·첫 로그인 분기를 시험할 수 있다. 경로와 read-only 검사 결과는 [시험 계획의 표본 identity 대조](./icloud-sync-compatibility-test-plan.md#2026-09-25-보존된-historical-v3-표본과-시험-계정-identity-대조)에 있다.

사용자는 pending export 업데이트 재현을 위해 약 5분 Mac 전체 네트워크 중단을 승인했다. 다만 네트워크 변경은 수행하지 않았다. 읽기 전용 확인에서 기본 경로는 Wi-Fi였고, `sudo -n -l`은 관리자 암호를 요구했다. secure system authorization 또는 사용자의 수동 Wi-Fi 조작 없이 자동으로 끊었다 복구하는 권한은 현재 사용할 수 없다. 따라서 pending export/update는 아직 BLOCKED이며 비밀번호를 채팅으로 요청하지 않는다. 네트워크 복구·사용자 작업은 시험 sample과 권한 방식이 정해진 뒤 정확히 안내한다.


## 2026-09-26 후속: account-change purge가 ownership write gate보다 먼저 돈다

재개 시 제일 먼저 해결할 blocker다. 앱 startup은 `.private` ModelContainer를 열고 나서 LiveDrawingEditEnvironment와 ownership proof를 시작한다. proof 실패는 앱이 호출하는 synced writes만 막고 Core Data mirroring/import/export는 막지 않는다. 실제 peer log `/private/tmp/carve-x27-ownership-v5-ios18.6-live-20260926/postlogin/peer-full.log:231-249`는 stored/current iCloud identity 차이, `AccountChange` purge, 모델 행·CloudKit metadata 제거를 기록한다. 이후 Development import/export 성공도 있으나 wrong-account upload 또는 server loss를 증명하지 않는다.

그 peer의 21-row consistent prelaunch backup은 없다. 보존된 `peer-before-import.sqlite`는 사후 2행이고 별도 V3 preservation copy는 1행이라 baseline으로 쓸 수 없다. peer를 재실행하거나 복구하지 않았다. RawStoreSnapshot 파일은 저장되지만 이를 앱에서 읽어 보여 주는 경로가 없어 사용자 접근성 보장으로 보지 않는다. 안전한 다음 수정은 first-login unaccounted V3 또는 same-account linked proof를 `.private` attach 전에 끝내고, failure/mismatch에는 `.none`으로 남아 existing data를 읽고 초안은 별도 보존하며 상태와 재시도를 제공하는 것이다. retry 시 ModelContainer 교체/재수명화 설계와 pending upload proof가 필요하므로 현재는 미구현, release **NO-GO**.

수신기 `Carve-2.0.0-Ownership-Peer-iOS18.6-20260926` (iPad mini A17 Pro, iPadOS 18.6, UDID `DC7D72AB-1CD2-4852-B459-0CCD45FE7862`)는 Device Hub Settings에서 Apple Account 미로그인 상태다. 앱은 실행하지 않았다. 사용자가 source와 같은 계정으로 직접 로그인하기 전에는 이 peer의 CloudKit receive를 확인하지 않는다. 조사·로그 경로 및 정확한 제한은 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#같은-scope-peer-account-change-purge-후속-조사-2026-09-26)에 있다.

## 2026-09-26 코드 후속: ownership preflight가 private attach보다 먼저 실행

위 절의 startup-order blocker는 수정했다. 앱은 async `AppStartupView`에서 `ReleaseStoreBootstrapper.load()`가 끝나기 전 Store와 `AppCoordinatorView`를 만들지 않는다. 로컬 raw snapshot 및 `.none` migration 후 CloudKit identity와 store ownership proof를 확인한다. exact same account proof만 private store에 연결한다. no-account·identity unavailable·different scope·unproven metadata는 `.none` local store를 열고 `ownershipUnverified` hold를 둔다. 설정에 원인과 앱 재실행 재시도를 알리며, 읽을 수 있는 기존 필사는 남고 새로운 캔버스 필기는 기존 별도 draft 경로에 저장된다. 같은-scope direct synced writes 및 전체 삭제는 hold 중 차단한다. synchronous `ModelContainer.liveValue`는 연결 전에 proof를 수행할 수 없으므로 `.private`를 열지 않게도 바꿨다.

같은 계정 linked store proof에서 pending은 더는 전체 store를 고정 조건으로 쓰지 않는다. 각 Core Data mirrored record의 upload/cloud-delete/local-delete pending flag/name mapping을 엄격히 검증하고 settled records만 current private database에서 확인한다. pending record가 없는 경우 server query를 생략할 수 있으며 이름 mapping/count/uniqueness 모순이면 거절한다. iPadOS 18.6 historical V3의 private marker는 true integer boolean profile로만 인식하며 의미는 여전히 미확정이다.

회귀: Xcode 27.0 / Swift 6.4 / macOS 27.2, iPadOS 17.5 44/44와 18.6 44/44. app target CarveApp simulator build iPadOS 18.6 성공(exit 0). 명령은 `xcodebuild test -quiet -workspace Carve.xcworkspace -scheme DomainTest -destination 'platform=iOS Simulator,id=<iPad UDID>' -only-testing:DomainTest/DrawingStoreOwnershipProofTesting -only-testing:DomainTest/LegacyRowLinkageReaderTesting -only-testing:DomainTest/MigrationSyncReleaseTesting`; 결과는 `/private/tmp/carve-x27-ownership-preflight-ios17.5-r2-20260926.xcresult`, `/private/tmp/carve-x27-ownership-preflight-ios18.6-r4-20260926.xcresult`. CarveApp build log `/private/tmp/carve-x27-ownership-app-build-ios18.6-r1-20260926.log`. Tuist 4.208.0은 `mise x -- tuist version`으로 확인했다. 초기 plain sandbox Tuist/simctl 조회는 세션/CoreSimulator 권한 제한으로 실패해 escalated read-only 확인에서 같은 기본 Xcode 27/runtime를 확인했다. 자동 검증용 simulator는 기존 CloudKit specimen/로그인 peer와 분리해 신규 생성했다.

이 결과는 fixture/release code의 자동 검증이다. Device Hub/manual smoke 및 Development CloudKit live proof와는 별개다. 이전 target V3 first-login은 Core Data 성공 export event, ledger 및 payload hash를 관측했지만 독립 server inventory가 없었다. 기존 account-change peer의 prelaunch full snapshot도 없어서 21→2 행 변화는 복구/손실 판단을 할 수 없다. 새 blank peer는 사용자의 같은 계정 로그인/앱 미실행 상태 확인을 기다린다. 실제 peer receive와 기존 로그인 historical 1.3 V3 업데이트, live mismatch/unavailable no-upload proof는 미완료이므로 release **NO-GO**를 유지한다. 계속 진행할 때는 이 새 peer를 먼저 확인하고, target/peer의 identity를 로컬 hash 비교로만 대조한 뒤 Development container에서만 시험한다. Production은 변경하지 않는다.

## 2026-09-26 최신 ownership 판정·검증 핸드오프

앞 절의 44/44 회귀, `[26]` 상태, 사용 전 blank peer 로그인 대기는 당시 결과다. 현재 checkout 코드는 startup을 변경했다. `AppStartupView`가 `ReleaseStoreBootstrapper`를 기다리고, raw snapshot 및 `.none` migration 뒤 identity/store proof가 일치할 때만 `.private`를 연다. 실패 시 기존 필기는 읽을 수 있고 hold 안내/다음 실행 재시도와 별도 local draft를 제공하며 동기 쓰기와 전체 삭제를 막는다.

Reader는 지원 OS major `[17, 18, 26]`에서 observed metadata shape를 검사한다. iPadOS 18.6 실제 historical V3의 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey=true`는 key name이나 true 값만으로 migration 의미를 결정하지 않는다. boolean의 구조만 인정하며 first-login ownership은 unlinked V3 판정과 보존 source V3↔현재 V3/V6 전체 필기·좌표·표시·page payload 일치로 입증한다. linked store는 저장된 identity와 현재 계정 일치, metadata/row mapping, settled server records로 확인한다. 정상 pending row는 연결 관계가 정확할 때만 settled lookup에서 제외된다.

Xcode 27.0 (`27A266a`), macOS 27.2, Swift 6.4.0.34.1, Tuist 4.208.0에서 `mise x -- tuist generate --no-open`을 실행했다. `DomainTest` 세 ownership/migration suites는 iPadOS 17.5와 18.6에서 각각 46/46, failure 0, skip 0, runtime warning 0이다. 결과는 `/private/tmp/carve-x27-ownership-final-ios17.5-r1-20260926.xcresult` 및 `/private/tmp/carve-x27-ownership-final-ios18.6-r2-20260926.xcresult`; 로그는 같은 basename의 `.log`다. `CarveApp` Debug build는 exit 0, 로그 `/private/tmp/carve-x27-ownership-release-app-build-20260926.log`. 산출물의 container는 `iCloud.Carve.SwiftData.iCloud.dev`, runtime environment Sandbox이며 Production은 건드리지 않았다. 전체 표본·판정·명령 경로는 [호환성 시험 계획의 최신 후속](./icloud-sync-compatibility-test-plan.md#2026-09-26-ownership-판정콘텐츠-대조-후속)에 있다.

실제 CloudKit은 아직 완료되지 않았다. 기존 target은 first-login ledger, preserved V3/current payload 298 bytes 동일성과 local export success bookkeeping을 남겼지만 독립 server inventory가 없다. 새 independent peer `Carve-2.0.0-Ownership-Peer-iOS18.6-TargetAccount-20260926` (`1FAEBEDC-A397-477D-A83A-6362D2C4BEB3`) 앱 실행 때 CloudKit runtime은 `No account` / `hasValidCredentials=false`였다. 그래서 no-account ownership hold가 선택됐고 upload/import는 수행되지 않았다. 로그 `/private/tmp/carve-x27-ownership-target-account-peer-app-20260926.log`. 사용자는 target과 같은 계정으로 로그인할 주소를 확인 중이다. 이 peer는 그대로 보존한다.

Device Hub 수동 UI smoke, no-account V3의 independent server payload와 peer/render, 기존 linked same-account historical 1.3 V3 update, live mismatch/unavailable no-upload는 미검증이다. 시험하지 않은 경로를 통과로 간주하지 않는다. 출시 **NO-GO**를 유지한다. 다음 작업은 사용자가 target과 같은 계정임을 확인하고 peer runtime `.available`을 확인한 뒤 Development container에서만 독립 receive를 검증하는 것이다. Production은 변경하지 않는다.

### 2026-09-26 peer 로그인 후 재시도 상태

사용자는 전용 iPadOS 18.6 peer에 b 로그인 완료를 알렸다. 해당 simulator에서 앱을 다시 실행했지만 CloudKit `account-status` 응답 값은 현재 로그에 없고, KVS는 `No account`, `LocalStoreLoader`는 ownership proof 미확인 local-only 경로를 기록했다. Development private import/export 및 row 수신은 관측되지 않았고, Device Hub Settings 화면도 CUA 시간 초과로 확인하지 못했다. 따라서 live 수신은 여전히 **미검증 / NO-GO**다. 정확한 peer Settings의 Apple Account > iCloud에 b가 표시되는지 사용자 확인을 기다린다. 시도와 로그 한계는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#b-로그인-후-peer-재검사-2026-09-26)에 있다.

후속 Simulator CLI Settings 캡처(`/private/tmp/carve-x27-ownership-peer-b-settings-check-20260926.png`)에서 Apple Account 카드가 로그인을 요구했다. 이것은 사용자의 완료 보고와 다른 직접 기기 상태다. Carve 종료 후 별도 컨테이너 사본은 무결성 `ok`, 필기·페이지·즐겨찾기 0행, CloudKit record metadata table 없음이었다. Settings는 해당 peer에 열어 두었으며 사용자가 b 계정 로그인을 직접 완료할 때까지 live receive를 재개하지 않는다. 캡처는 Device Hub smoke로 세지 않는다.

## 2026-09-26 peer 계정 상태 재확인

사용자는 기준 target과 peer 계정을 Gmail(b)이라고 확인했고, Hanpass(a) 및 user token이 등록된 원본 계정 `never`와 구분했다(주소 원문은 기록하지 않음). Gmail(b) peer만 재부팅한 뒤 Debug 앱을 다시 실행했으나 CloudKit은 여전히 `No account`를 보고했다. 앱은 `ownershipUnverified` local-only hold에 머물렀고 Development upload/import는 실행되지 않았다. 재부팅 후 로그는 `/private/tmp/carve-x27-ownership-peer-gmail-after-reboot-20260926.log`다. Device Hub 화면 확인은 CUA 요청 시간 초과로 완료되지 않았다. 다음에는 이 정확한 peer Simulator Settings에서 Apple Account > iCloud 상태를 확인한 뒤에만 receive를 재시도한다. 다른 계정이나 원본 기기는 바꾸지 않는다.

### peer 계정 전환 전 보존 기록 (2026-09-26)

사용자가 peer Settings의 현재 계정이 original/`never`, target 계정이 `b`라고 확인했다. peer 앱은 종료했고 전체 app data container 사본을 `/private/tmp/carve-x27-ownership-peer-pre-account-switch-20260926/AppContainer`에 남겼다. copy의 DB integrity `ok`, verse drawing/page drawing 각 0행, CloudKit record metadata table 없음이다. AccountChange reset이 발생해도 확인된 필기 payload는 없고 전체 peer app container는 복구용으로 보존돼 있다. 사용자는 peer만 target과 같은 `b`로 로그인하고 앱을 닫아 두기로 안내받았다. 원본/target 계정은 바꾸지 않는다.


## 2026-09-27 최신 재개 지점

26일 실제 iPadOS18.6 1.3.0 V3→후보 업데이트에서 b 소유 proof/private attach와 22행 필드·payload 보존을 확인했다. 별도 독립 DC peer의 빈 시험 저장소는 같은 서버22행을 받았다. target/peer의 기존 Application Support는 시험 후 모두 복원하고 앱을 종료했다. clone은 원본 컨테이너 경로를 반환해 사용하지 않았다. 자세한 실험 구분·경로·한계는 [시험 계획 최신 기록](./icloud-sync-compatibility-test-plan.md#2026-09-27-재개--실제-186-v3-업데이트와-독립-수신-증거)을 따른다.

현재 `1FAEBEDC-A397-477D-A83A-6362D2C4BEB3` (`Carve-2.0.0-Ownership-Peer-iOS18.6-TargetAccount-20260926`)에는 **실제 1.3.0에서 손가락 입력한 창세기22:1 두 획**이 2.0.0으로 업데이트돼 있다. 469B payload와 모든 비교 필드 동일, 화면 표시 확인. Settings를 열고 사용자 b 로그인을 기다린다. 27일 재개 때 아직 로그인 안내였다. 기존 이름에 TargetAccount가 없는 DC peer는 b 로그인이 이미 정상이며 계정 전환을 요구하지 않는다.

증거 루트 `/private/tmp/carve-peer-correct-20260926`: `actual-noaccount-v3-before`, `actual-noaccount-after-update`, `actual-noaccount-update.log`와 화면. 시험 기기 원래 빈2.0 지원 디렉터리는 Documents/ActualLegacyTrial-20260926/empty-previous-support에 남아 있다. 현재 실제 V3 이관 표본을 지우거나 과거 빈 상태로 되돌리지 않는다.

새 수정은 proof가 끝난 뒤 계정을 재확인해 대기 중 전환·확인 실패를 hold하는 것이다. iPadOS17.5·18.6 ownership 각각9/9 통과. 실행 중 첫 로그인 후 `.none` runtime 교체는 아직 구현하지 않았으므로 재실행 안내만으로 정상 흐름 통과라 기록하지 않는다. 서버 직접 payload 대조 도구의 과거 경로는 사라졌고, 독립 receive와 직접 inventory를 구분한다. 실제17 정상 경로, pending export 업데이트 및 최종 표시/로그인 검증이 남아 **NO-GO**다.


### 2026-09-27 첫 로그인 후속 — 원시 사본 shm 변경 수정

사용자 b 로그인은 완료됐다. 첫 소유 판정은 성공했으나 보존 V3를 직접 읽으며 shm을 변경해 다음 실행의 manifest 검증에 실패하는 결함을 재현했다. 검증된 원시 디렉터리를 임시 복제하여 판독하도록 수정했고, iPadOS17.5/18.6 각각9 cases(10 parameter runs), 실패·skip·runtime warning0이다. 실제 1FA 표본의 Development 서버23행 중 창세기22:1 필기468B가 원본과 일치하고 반복 실행 뒤 원시 사본 모든 지문이 유지된다. 시험 복원 절차·명령·실패 이력은 시험 계획 최신 절에 있다.

아직 실행 중 로그인 runtime 재연결, 새 실제 표본의 독립 peer 수신/표시, 실제17 정상 로그인 경로를 통과로 기록하지 않는다. 재연결 관련 App/Feature/Settings 변경은 미커밋 작업 중이다. UI 최초 실패는 첫 실행 안내가 탭을 가로챘으며 처리 추가 후 재시험 준비 중이다. Mac 잠금으로 Device Hub 수동 확인은 대기 중이다. DC peer는 현재 b 시험 지원 디렉터리로 실행 중이며 원래 자료는 Documents/OwnershipReceiveTrial-20260926/original-before-actual-receive-20260927에 보존되어 있다. 시험 종료 후 원래 자료를 복구하고 앱을 종료한다. 출시 NO-GO 유지.


### 2026-09-27 최신 수신/재연결 상태

18.6 실제 무계정1.3.0 V3 필기는 b 서버 전송과 독립 DC peer 수신·표시까지 완료했다(23행, 원본469B SQLite blob/468B 서버 필드 일치). DC의 암호 재확인 창이 해소된 후 빈 시험 저장소에서 수신했으며 원래 자료는 여전히 Documents/OwnershipReceiveTrial-20260926/original-before-actual-receive-20260927에 보존돼 있다. 현재 DC 앱은 종료 상태다. 수신 성공 자료도 `actual-independent-receive-success-store`에 보존했다.

재연결 UI와 마지막 획/초안 인계 코드를 구현했다. 18.6 인계 집중16 runs 및 관련59 runs 통과, 17.5 동일 프로세스 재시도 UI1/1 경고0 통과. 이 결과는 live 계정 전환 성공과 구분한다. 17.5 실제 필기 입력 전용 B60 기기는 역사적1.3.0 창세기23장 무계정으로 열려 있으며 자동 드래그가 저장되지 않아 사용자의 직접 입력을 기다린다. 사용자 b 계정 로그인 수행 허용이 추가됐으나 인증정보는 파일·로그·문서에 저장하지 않는다. 실제17 업데이트/첫 로그인·재연결 live 검증은 아직 남아 NO-GO다.


DC peer의 원래 Application Support 복원 완료, 앱 종료. 성공한23행 수신 지원 자료는 `Documents/OwnershipReceiveTrial-20260926/actual23-success-support-20260927`에 남겼다. 18.6 재연결 CLI UI도1/1 경고0으로 통과했다. 보존 파일 경로를 사용할 때 원래 자료와 수신 시험 자료를 구분한다.


## 2026-09-28 다른 Mac 재개 — 요약

macOS 26.3 / Xcode 26.3 (17C529) / Swift 6.2.4 Mac에서 이어받았다(Xcode 27 없음, 별도 툴체인 결과). 상세는 [시험 계획 09-28 절](./icloud-sync-compatibility-test-plan.md#2026-09-28-다른-mac-재개--xcode-263-빌드-복구와-ipados-186-실행-중-첫-로그인-live)을 따른다.

- HEAD `c9f6c399`는 Xcode 26.3에서 **컴파일되지 않았다**(`aebb5e63`의 iOS 27 전용 `SwiftDataError.unknownDataStoreSchema`). `#if compiler(>=6.4)`로 감쌌다. Xcode Cloud `MAIN`(26.3)·`DevelopBranch`(26.6)도 같은 오류 가능성이 크므로 Cloud 후보 전에 확인한다.
- 수정 뒤 전체 회귀: iPadOS 26.2·18.6 각각 1013 passed, 17.5 1012 passed(실패 0, 총 1023). 재연결 수정까지 적용한 뒤 26.2·18.6 1015, 17.5 1014(실패 0, 총 1025). 재실행 결정을 반영한 최종 코드에서 26.2·18.6 1018, 17.5 1017(실패 0, 총 1028), 재실행 안내 UI 시험 17.5·18.6 각 1/1.
- iPadOS 18.6 live(깨끗한 1.3.0 `49f2dc27` 빌드 `dc0eef22…` → 2.0.0): 무계정 24:1 두 획 1151B가 업데이트 뒤 바이트 동일·표시 일치. **실행 중 첫 로그인 뒤 자동 재연결과 설정 「다시 시도」 모두 실패**했고(필기 보존·업로드 0), **앱 재실행 경로는** 첫 로그인 전송 → Development 서버 payload 일치 → 독립 peer 수신·표시까지 통과했다.
- 실행 중 재연결 결함: ① 로그인 재적재 중 준비 요청 즉시 거절(수정·시험 추가), ② 이전 ModelContainer 미해제 — `CodableAppStorageKey`의 `@Dependency` 캡처와 `static` 기본값(actor·저장소)이 첫 runtime 컨테이너를 전역에 남김(부분 수정), ③ UI 시험 66행 문구 불일치로 가짜 통과(교정 → 이제 실패로 잡힘). 남은 보유 경로(`AppCoordinatorFeature.State.initialState`, task-local 문맥을 물려받은 Task 등)가 있어 실행 중 재연결은 **여전히 미동작**이다.
- 다음 결정: 보유 경로 제거를 계속할지, 2.0.0은 로그인 뒤 재실행 안내를 지원 경로로 삼을지. iPadOS 17.5 실제 표본은 런타임(21F79)을 확보했고 재실행 경로로 진행할 수 있다. 출시 **NO-GO** 유지.
- 이 Mac의 live 기기: target `35FF5450-0BD9-4815-B160-BE35D80CCC14`(b 로그인, 24행 연결), peer `8FA7976C-BEE0-4ECC-AD2A-26AFB9DCDEF2`(b 로그인, 24행 수신). 원래 Mac의 기기·경로와 섞지 않는다.
- **결정(2026-09-28): 2.0.0 은 로그인 뒤 앱 재실행으로 연결한다.** 실행 중 자동 재연결과 설정 「다시 시도」를 없앴고, 보류 중 로그인과 저장소 소유가 확인되면 로딩 없이 「연결을 완료하려면 앱을 완전히 종료한 뒤 다시 열어 주세요.」 를 안내한다. 설정 iCloud 화면은 로그인 상태와 연결 상태를 따로 적는다. 상세는 시험 계획 09-28 절의 「결정 반영」.
- **iPadOS 17.5 live(2026-09-28):** 실제 1.3.0이 17.5에서 만든 무계정 저장소(5-key metadata, migrator marker 1)에 18.6 실제 필기 payload를 합성 행으로 넣어(사용자 승인 — 17.5 시뮬레이터에서는 손가락 · 마우스 필기가 PencilKit 제스처 실패로 저장되지 않음) 2.0.0 업데이트 → 실행 중 로그인 → **재실행 안내(로딩 없음)** → 재실행 연결 → Development 서버 payload 일치 → 독립 peer 수신 · 표시까지 통과했다. 실제 iPadOS 17 기기의 필기 입력은 미확인이다.
- **iPadOS 27 실기기 · 재실행 소유 판정(2026-09-28):** 이 Mac의 Xcode 26.3 Debug 빌드를 iPadOS 27.2 실기기(dev 저장소 · 사용자 본인 계정 Development)에 설치해 확인했다. 최종 코드는 서버와 모두 대응된 실제 Apple Pencil 필기 저장소도 **매 실행 보류**했다(검증 OS에 27 없음). 27만 더한 시험 빌드에서는 연결 · 재실행이 통과했고 보류됐던 저장소도 다시 연결됐다(시험 변경은 되돌림). 같은 시험 빌드에서 **빈 연결 저장소(전체 삭제 뒤 모양)는 계속 보류**됐고, 18.6 최종 빌드에서 **필기 저장 1초 뒤 종료한 저장소도 재실행마다 보류**됐다. 오프라인 실행은 그 실행 동안 보류되고, 오프라인 · 보류 중 필기는 초안으로만 남아 다시 연결돼도(같은 절을 다시 그려도) 동기화되지 않았다. 원인은 매 실행 `existingPrivateStore`가 검증 OS · 모든 행 대응 · 행 1개 이상 · 서버 조회를 요구하는 것이다. 필기 유실은 없었다. 같은 날 18.6 최종 빌드 양방향 저장 · 지우기와 17.5 로그인 상태 1.3.0 → 2.0.0 업데이트(28행 보존 · `currentPrivateCloudRecords` · 재실행 연결)는 통과했다. **출시 NO-GO.** 수정 방향 제안은 [시험 계획 09-28 판정 절](./icloud-sync-compatibility-test-plan.md)에 있다. 18.6 peer `8FA7976C…`는 수정 검증용으로 보류 상태 그대로 두었다.
