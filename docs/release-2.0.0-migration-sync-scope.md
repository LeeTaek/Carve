# 2.0.0 필사 이전·iCloud 출시 범위 (2026-09-23 결정)

이 문서는 2.0.0의 **필사 이전·동기화 작업**에 적용할 최신 제품 결정을 기록한다. [출시 로드맵](./release-2.0.0-roadmap.md)의 다른 기능·배포 조건까지 없애는 결정은 아니다. [C14 결정 2](./icloud-sync-and-backup-policy.md)의 분리·명시적 가져오기 설계와 실험 기록은 역사적 근거로 남기되, 이 문서의 출시 범위가 그 설계의 **2.0.0 필수 구현 범위**보다 우선한다. 현재 코드가 이미 이 범위를 만족한다는 뜻은 아니다.

> **구현·검증 갱신(2026-09-26):** 최신 코드 reader는 iPadOS 17·18·26을 판정하며, 17.5와 18.6의 Xcode 27 ownership/migration 회귀는 각각 46/46 통과했다. 앱은 proof가 끝날 때까지 private CloudKit 저장소를 열지 않는다. existing linked proof는 row에 정확히 매핑된 pending 작업을 허용하고 settled records만 server에서 조회한다. iOS 18.6 표본의 migrator marker 의미는 아직 불명이며, 소유 판정은 그 의미에 의존하지 않는다. 새 peer의 runtime 계정 상태가 `No account`여서 실제 서버/peer 수신은 아직 확인되지 않았고 출시 판정은 **NO-GO**다. 아래의 `## 2026-09-26 현재 판정 갱신`은 코드·증거 최신 세부이며, 본문 안에 날짜가 붙은 과거 관측은 당시 상태로 읽는다.

## 이번 출시에서 보장할 것

1. **1.3.0 → 2.0.0 업데이트 때 기존 필사를 잃지 않는다.** 실제 출시본 1.3.0(`49f2dc27`, V3)으로 만든 저장소를 사용한다. 로그인 상태와 무계정 상태를 각각 확인하고, `BibleDrawing`과 실제 표본에 있는 `BiblePageDrawing`의 행 수뿐 아니라 필기 내용·좌표·화면 표시를 업데이트 전후에 대조한다. 기존 데이터가 있는 사용자를 빈 새 설치로 잘못 취급하거나, 마이그레이션 실패 뒤 빈 저장소에서 편집하게 해서는 안 된다. 2026-09-25에는 Xcode 27 iPadOS 18.6의 새 계정 없는 simulator에서 F59 V3 synthetic 한 행을 로컬 migration해 298B payload와 raw Preservation snapshot을 보존했다. 최초 축소 화면에서는 작은 획을 놓쳤으나, 후속 read-only CanvasDisplayProbe에서 fetch 후 store와 canvas가 같은 한 획·bounds를 보이고 diff 0임을 확인했다. Device Hub 일시 오버레이를 닫고 확대하자 Genesis 1:1 획이 보였고 Genesis 1장→2장→1장 이동 뒤에도 표시됐다. 또한 같은 날 iPadOS 26.5 same-account clone에 historical 1.3.0(1) simulator bundle(이 bundle은 Xcode 27에서 재빌드되지 않음)을 설치·실행해 20개 CloudKit-backed V3 레코드를 가져온 뒤 Xcode 27 2.0.0 앱으로 업데이트했다. 무결성 `ok`, drawing·record metadata 각 20행, pending export 0, `currentPrivateCloudRecords` marker, payload·record-name set의 source clone 일치를 확인했다. Device Hub에는 기존 필기가 보였지만 첫 실행 안내와 AdMob 팝오버가 열린 화면을 조작 없이 관찰한 것이므로 pixel/좌표 전후 대조는 아니다. 이 두 확인은 한 개의 무계정 local-only migration과 한 개의 로그인된 cloud-backed upgrade에 한정되며, 미업로드 local-only row/pending export를 동반한 계정 전환과 legacy 좌표 기준 대조는 남아 있다. 실행·테스트 증거와 로그는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)의 2026-09-25 절에 있다.
2. **1.3.0에서 계정 없이 작성한 옛 필사는 2.0.0에서 iCloud 로그인 후 전송된다.** 업데이트 직후 로컬 표시가 유지되고, 첫 로그인 뒤 서버에 올라가며, 같은 계정의 다른 iPad에도 같은 내용이 나타나는지 확인한다. 서버 이벤트 성공·행 개수만으로 통과시키지 않는다. 로그인 전후 앱 실행 중과 재실행 경로를 모두 본다. 후보에는 strict metadata proof와 첫 로그인 분기가 구현됐다. strict profile 변경 뒤 Xcode 27 iPadOS 26.5 ACC sandbox clone의 기존 private-store proof에서는 20/20 record name hash 일치, pending 0, 동일 inventory 재조회를 확인했다. historical 1.3.0 로그인 store → 2.0.0 업그레이드 clone에서도 20개 cloud-backed row의 local 보존과 owner marker를 확인했다. **2026-09-25 추가 검증:** 새 iPadOS 26.5 simulator에서 historical 1.3.0(1) V3 synthetic Genesis 1:31 row를 2.0.0으로 업데이트한 뒤 사용자가 같은 ACC sandbox 계정으로 로그인했다. 앱 로그의 Core Data export 성공, local `firstLoginFromUnaccountedV3` marker와 pending 0을 확인했고, 별도 peer clone은 실행 전 20행·1:31 부재에서 실행 뒤 21행·동일 300B payload 수신으로 바뀌었다. 따라서 이 synthetic 단일 row의 first-login 업로드·다른 simulator 수신은 제한 범위에서 확인했다. Device Hub peer reader에서 Genesis 1:31 필기 한 줄도 Page Down 키로 수동 확인했고, 이는 자동화 결과와 분리했다. 앱 종료 뒤 읽기 전용 store의 integrity·payload·pending은 그대로였다. 독립 read-only remote inventory hash, physical iPad 수신, 1.3.0 artifact의 Xcode 27 재빌드 및 모든 데이터 모양의 UI 표시까지 증명한 것은 아니다. 함께 import된 기존 Genesis 1:10–12의 8개 22B row는 macOS 27.2 호스트 PencilKit에서 0획 drawing으로 decode되나 iPadOS 26.5 앱에서 decode 실패한다. `try?`가 구체 오류를 감추므로 손상·정상 빈 필기 어느 쪽도 단정하지 않았으며, 별도 표시·복구 점검이 필요하다. 계정 변경 없이 진행했고 의도한 synthetic row가 Development private DB에 남아 있다. iOS 18.6의 실제 1.3.0 표본에는 의미가 확인되지 않은 metadata marker가 있어 그 OS에서는 여전히 fail-closed다. 상세 evidence와 log path는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)을 따른다.

이 선택은 1.3.0 무계정 필사를 **처음 로그인한 iCloud 계정에 자동 귀속**시킨다. 본인이 아닌 계정으로 로그인하면 그 계정에 전송될 수 있다. 계정 변경·로그아웃 중 SwiftData/CloudKit이 로컬 저장소를 비우는 경로도 있어, 위 두 흐름에서 필사가 사라지지 않는지 확인해야 한다. 1.3.0 무계정 저장소를 이미 로그인된 시뮬레이터에 이식해 연결한 F40은 자동 귀속의 가능성을 보여 주지만, 실제 사용자 순서와 실제 PencilKit 필기 내용의 최종 검증은 아니다.

**구분:** 2.0.0에서 *새로* 계정 없이 쓴 필사는 현재 별도 로컬 초안 경로다. 이 결정은 그 초안까지 로그인 때 자동 업로드하라는 뜻이 아니다. 그 필사의 로컬 보존·안내는 유지하고, 자동 전송을 약속하는 문구를 쓰지 않는다.

## 2.0.0 출시 판정

| 판정 | 필요한 증거 |
|---|---|
| 필수 — 업데이트 무유실 | 실제 1.3.0 V3 필기 표본의 업데이트 전·후 내용/좌표/표시 대조. 로그인·무계정 각각, 실패·재실행 시 원본 보존 확인 |
| 필수 — 옛 무계정 필기의 첫 로그인 전송 | 같은 기기에서 1.3.0 무계정 작성 → 2.0.0 업데이트 → 로그인. 로컬·서버 레코드·다른 iPad의 내용 대조. 실행 중 로그인과 재실행 확인 |
| 필수 — 일반 순차 동기화 | 같은 계정의 iPad A에서 저장 → 전송 확인 → 시간차를 두고 iPad B에서 수신·표시, 반대 방향도 확인. 정상적인 저장·삭제 경로도 확인 |
| 필수 — 실패 시 보존 | 저장소 열기·마이그레이션·전송 실패를 성공으로 오표시하지 않고, 로컬 원본 또는 복구 가능한 사본을 잃지 않는지 확인 |
| 이번 출시의 필수 보장에서 제외 | 두 iPad에서 **같은 절을 서로 모르는 상태로 동시에** 편집한 경우의 양쪽 자동 보존, 1.3.0·2.0.0 혼용 편집의 완전한 충돌 해결, C14 분리본 표시·명시적 가져오기·행 삭제·중단 복구 전체 |

마지막 행은 안전하다는 판정이 아니다. 기존 실험은 동시 편집의 나중 쓰기 덮어쓰기(F15)와 구·신 버전 좌표 위험(R28)을 남긴다. 2.0.0에서는 시간차가 있는 통상적인 한 계정·두 iPad 사용을 우선 검증하고, **동시 같은 절 편집과 혼용 편집은 알려진 제한**으로 기록한다. 출시 안내가 실제 보장보다 넓게 읽히지 않게 한다. 실제 순차 사용에서도 유실이 재현되면 필수 조건 실패다.

지원 OS의 실제 출시 경로도 확인한다. 앱의 기본 배포 타깃은 iOS 17.0이다. **2026-09-26 코드 수정 후** legacy 저장소 판독기는 iPadOS 17·18·26에서만 strict profile을 읽는다(19~25는 미검증이라 허용하지 않음). 첫 로그인 V3 profile은 무계정 metadata 네 키 또는 실제 관측된 추가 migrator marker를 포함한 정확한 키 집합, 올바른 값 형식, migration 미요청, 행 대응 부재와 로컬 행 수 일치를 요구한다. 기존 로그인 저장소는 linked metadata profile, identity 확인 완료, 현재 계정과 일치, 로컬 행과 CloudKit 대응 일치 및 현재 private DB에서 모든 record name 조회 성공을 요구한다. pending export 자체는 정상 상태일 수 있어 소유 판정의 영구 차단 조건으로 사용하지 않지만, 아직 서버에 없는 레코드는 proof를 통과하지 않는다. 미지 키·누락·중복·값 형식 오류·불일치·손상·migration 미완료는 계속 거절한다. marker 의미는 미확정이며 판정 근거로 사용하지 않는다.

iOS 18.6 실제 V3 표본에서 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`와 정수 boolean `true`를 관측했다. private key의 완료·진행 의미는 현재 증거로 확정하지 않았다. 2026-09-26 보존 사본은 integrity `ok`, V3 local row 1, metadata 5개(관측 marker 포함), `NeedsMetadataMigration=false`, record metadata·export/import operation 0이었다. 별도 독립 simulator에 해당 payload 298B를 가진 합성 V3 표본을 준비해 2.0.0을 실행한 뒤, 현행 store integrity `ok`, Revelation 22:21 row 1·298B·present, marker true, record metadata·export/import operation 0을 확인했다. UI는 첫 실행 안내/광고에 가려진 상태였으며 앱 로그는 무계정 CloudKit 접근 불가를 기록했다. 이는 metadata reader가 저장소를 열고 로컬 마이그레이션/보존을 했다는 증거이지 사용자 로그인·전송 증거가 아니다. 별도 2026-09-25 source snapshot과 사고로 수정된 original simulator의 관측을 섞지 않는다. 이전의 exact-key fail-closed 결론과 allowlist `[26]`은 당시 코드의 역사 기록이며 현재 코드는 reader version 5, `[17,18,26]`, exact known profile variants다. 추가 marker는 완료 표식으로 해석하지 않는다.

**2026-09-26 로그인 후 갱신:** target simulator에서는 실제 first-login ownership ledger가 `firstLoginFromUnaccountedV3`로 기록됐고 V3 보존 payload와 V6 현재 payload byte-for-byte 일치, `ZNEEDSUPLOAD=0`, 마지막 export transaction `3`을 확인했다. 이는 소유 proof와 local export bookkeeping의 근거지만 독립 server inventory를 대신하지 않는다. same-scope peer에서는 표본 수신을 보지 못했고, 그 peer app 실행 뒤 로컬 행 수가 달라 원인을 미확정으로 남겼다. 신규 빈 iPadOS 18.6 peer는 준비했지만 같은 계정 로그인과 수신·화면 표시 확인 전이다. 1.3.0 실제 역사 bundle로 동일 로그인 순서 시험, 독립 CloudKit record 수신, 좌표·표시 대조 및 계정 불일치 live 시험은 여전히 필요하며 출시 gate **NO-GO**다. 상세 경로와 위험은 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)의 2026-09-26 후속 기록에 있다.

iOS 18.3.1·18.6의 앞선 집중 시험은 identity와 CloudKit 조회를 test double로 대체한 단위 검증이며 실제 소유 proof가 아니다. iOS 18.6·26.2에서 `CarveApp` 타깃 빌드는 성공했다. **2026-09-25 환경 확인:** 현재 Mac은 macOS 27.2 / Xcode 27.0을 기본 선택하고 Device Hub가 실행 중이다. 기본 Xcode 27에서 `simctl` 목록 조회가 가능하며 iOS 17.5·18.6·26.2·26.4·26.5·27.0 runtime이 있다. Xcode 26.3을 지정한 runtime 조회는 sandbox에서 실패했지만 권한을 높여 재실행하자 성공했다. migration 수정 후 iPad mini (6th generation) iOS 17.5 전체 회귀는 998 통과·0 실패·6 skip·4 expected failure였고, 미사용 prototype 이동 후 Xcode 26.3 파일 제외 없는 전체 회귀는 iPadOS 17.5에서 998 통과, iPadOS 18.6·26.2에서 각각 999 통과·실패 0을 얻었다(각 4 expected failure 포함, 새 결과 총 1008). V1 custom migration은 source context에서 destination model을 생성하던 문제를 DTO 전달로 고쳤고, 확인된 V2 이상 저장소는 iOS 17의 134504 회피를 위해 V2 시작 plan으로 연다. iOS 17.0은 직접 시험하지 않았고 iOS 19~25 runtime도 현재 목록에 없다. **Xcode 27 후속 검증**은 Tuist workspace를 재생성한 뒤 Debug iPad simulator build와 iPadOS 17.5(998 통과·4 expected failure·6 skip), iPadOS 18.6·26.2·26.4·26.5(각 999 통과·4 expected failure·5 skip), iPadOS 27.0(998 통과·4 expected failure·6 skip)의 전체 회귀를 모두 통과했다. 각 결과는 총 1008건이며 unexpected failure 0이다. 17.5 로그에만 임시 SQLite fixture unlink/open-FD 경고가 보였고 xcresult failure/runtime warning은 없었다. 최초 F60 generic-project의 XCFramework 서명 단계 실패는 workspace 빌드에서 재현되지 않았다. 개별 `-project CarveApp`의 SwiftPM 모듈 오류와 읽기 전용 artifact 서명 상태 이상은 별개 관측이며 인과관계는 미확정이다. **소유 proof 허용 OS는 여전히 iOS 26뿐이다. Xcode 27 iPadOS 26.5 ACC sandbox clone에서 strict profile 이후 기존 private-store proof 통과를 확인했지만, iOS 18 metadata marker·계정 왕복, 로그인 상태 1.3.0 업데이트, iOS 17 proof/직접 회귀가 미완료여서 전체 출시 판정은 NO-GO다.**

## 출시 게이트와 이번 후보의 결과

이번 후보는 C14 분리·삭제 동작을 실행하지 않고도 로그인 소유 쓰기를 여는 proof provider를 앱에 연결했다. proof 결과가 없으면 캔버스는 로컬 초안에만 쓰고, `SyncedWriteBlock`을 사용하는 즐겨찾기·위젯 보관·이력 복원·N-Canvas 직접 쓰기도 그대로 막힌다. 기존 server-work token, 삭제 기준점 K, 계정 변경 잠금과 원본 보존·마이그레이션 실패 차단을 유지한다. 자세한 코드·시험 기록은 [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md)를 본다.

즐겨찾기·위젯 보관·이력 복원·N-Canvas 경로는 공통 소유 차단과 자동 시험에서 확인했다. 실제 CloudKit 왕복은 즐겨찾기와 일반 필사에서 관측했으며, 위젯 보관·이력 복원·N-Canvas UI의 별도 라이브 서버 실행은 이번 시험에서 하지 않았다.

Xcode 26.3 / iPadOS 26.2 회귀는 Domain 452개(448 통과·선언된 expected failure 4개·실패 0), SettingsFeature 54개, CarveFeature 457개가 통과했다. 각 scheme의 `build-for-testing` 성공 후 같은 산출물로 `test-without-building`을 실행했다. iPadOS 18.3.1·18.6의 앞선 집중 시험 66개는 당시 reader가 허용한 규칙에 대한 결과다. 최신 strict-profile 소스의 지원 OS별 결과는 아래 추가 검증을 따른다. 앞선 test double 결과는 실제 private DB 로그인·왕복 증거가 아니다. `CarveApp` 시뮬레이터 타깃은 iPadOS 18.6·26.2에서 빌드됐다. 전체 build lint 단계의 다른 파일 경고 4건은 남았지만 변경 Swift 파일 lint는 통과했다. iPadOS 17.5 전체 회귀의 세 migration 실패는 수정 후 0 failed 전체 회귀와 OS별 집중 migration 회귀로 닫았다. iOS 18 metadata marker 의미와 실제 iOS 18 계정 왕복 미실행은 남은 출시 차단이다.

`Carve-ACC-dut`에는 사용자가 1.3.0에서 그린 창세기 1장 필기 두 행이 남아 있었다. 후보 덮어 설치 전·후·로그아웃 상태 실행에서도 내용 지문은 같았고, 실제 획·좌표·화면 표시가 유지됐다. 전후 사본은 `/private/tmp/carve-release-sync-evidence/snaps/dut-before-login`, `dut-after-candidate-install`, `dut-after-final-candidate-launch`에 있고 실행 화면은 `/private/tmp/carve-release-sync-evidence/dut-after-final-candidate.png`다. 로그인 직후 DUT 저장소는 2행·매핑 0건이었으나, 후보 앱 재실행 뒤 B 계정의 기존 레코드 15개를 수신하고 표본 두 행에 매핑이 생겨 총 17행·매핑 17건·업로드 대기 0건이 됐다. 시험 사본은 `dut-after-account-login-pre-probe`, `dut-after-account-login-relaunch`다.

이 실제 1.3.0 업데이트는 무계정 상태로 설치·실행한 뒤 첫 로그인했다. 따라서 무계정 업데이트 무유실과 첫 로그인 귀속은 확인했지만, **1.3.0에서 이미 계정에 연결된 상태로 업데이트하는 별도 분기는 이번 실측에 포함되지 않았다.** 출시 게이트 표의 해당 확인은 미완료로 남긴다.

`probe.sh`가 첫 실행에서 60초 안에 끝나지 않아 로그인 전 서버 기준선은 확정하지 못했다. 사용자가 B와 DUT를 같은 시험 계정으로 로그인시킨 뒤 DUT 서버 probe는 private DB의 `CD_BibleDrawing` 17개를 읽었다. Genesis 1:1의 654B payload / SHA-256 앞 16자리 `3a267e075d4d23e7`, 1:2의 794B / `4f38e8eb0d805fa2`가 DUT 표본과 각각 일치했다. B는 DUT export 뒤 앱 재실행·probe 후 15행에서 17행·매핑 17건으로 늘었으며 같은 두 payload를 받았다. 화면(`/private/tmp/carve-release-sync-evidence/b-after-dut-first-export.png`)에서도 1:1 지그재그와 1:2 고리가 표시됐다. 저장소 스냅숏·서버 로그는 `/private/tmp/carve-release-sync-evidence` 아래에 두었다. 계정 식별 원문이나 이메일은 보고하지 않았다.

따라서 **첫 로그인 전송·같은 계정 다른 iPad 수신 관문은 iOS 26.2 시뮬레이터에서 통과**했다. 후보 앱을 설정에서 돌아온 실행 중 경로와 앱 재실행 경로에서 확인했다.

일반 동기화는 DUT에서 별도 시험 절인 Genesis 1:7에 새 행을 만들었다. B는 18개 행·18개 매핑을 보유했고, DUT의 첫 표식 payload(840B, `d4b13df878550d24`)와 레이아웃 지문(`933cf04e6b43b1a7`)이 서버와 B에서 일치했다. B에 현재 후보를 앱 데이터 삭제 없이 덮어 설치한 뒤에도 18개 행·18개 매핑이 유지됐다. 후보가 발급한 소유 증명은 기존 계정의 private DB 레코드 전체 확인(`currentPrivateCloudRecords`)이었다.

B의 후보 설치 전 1:7 편집은 화면에 획이 보였지만 canonical 행의 payload는 바뀌지 않았다. 로컬에는 후보 설치 전 생성된 소유 증명 없는 초안이 있었고, 후보는 그 초안을 서버 행에 자동 채택하지 않았다. 이는 2.0.0의 미확인 로컬 초안을 새 계정 소유로 넓혀 자동 업로드하지 않는 정책과 맞는다. 이 편집은 역방향 수정 증거로 세지 않는다.

깨끗한 빈 절 Genesis 1:8에서 후보의 일반 생성·전송은 통과했다. B에 만든 행은 19번째 `BibleDrawing`이자 19번째 CloudKit 매핑이 됐고, 서버 private DB에는 `isPresent=1`, 965B payload / `261787e7b7ead104`로 저장됐다. 일정 시간 뒤 DUT 앱을 재실행하자 같은 행·payload가 수신되어 DUT도 19행·19매핑·업로드 대기 0건이 됐다. 전후 복사본은 `b-after-1-8-create-before-probe`, `b-after-1-8-server-export`, `dut-before-1-8-receive`, `dut-after-1-8-delayed-receive`이며 양 기기 화면은 `/private/tmp/carve-release-sync-evidence/b-after-1-8-export.png`, `/private/tmp/carve-release-sync-evidence/dut-after-1-8-delayed-receive-settled.png`다.

역방향 수정도 서버 저장·다른 기기 payload 수신까지 통과했다. DUT에서 B가 만든 1:8 행에 두 번째 획을 더하자 payload가 965B / `261787e7b7ead104`에서 1802B / `de5df55aa6147ab5`로 바뀌고, layout metadata 지문은 `2bfaf8b7d683127c`가 됐다. DUT 재실행 probe의 private DB에서 같은 1802B payload, 같은 layout metadata, `isPresent=1`을 확인했다. 30초 이상 열린 B의 로컬 행은 이전 payload였고, 그 뒤 앱 재실행 fetch 후 B도 같은 1802B payload를 받았다. B 로컬 layout metadata 지문은 `2cd2d9d9c1ba25ca`로 남아 서버·DUT와 달랐지만, 사용자는 B에서 Genesis 1:8을 열어 두 획과 좌표가 맞게 표시됨을 확인했다. 화면 증거는 `/private/tmp/carve-release-sync-evidence/b-1-8-after-reverse-receive-visible.png`다.

기존 C14 F44~F57은 분리·삭제의 실험 기록으로 보존하며 이번 출시 범위의 완료 증거로 쓰지 않는다. **동시 같은 절 편집의 완전한 충돌 보존과 1.3.0·2.0.0 혼용 편집 대응은 알려진 제한**이다. B의 수정 표시·좌표, 즐겨찾기 추가·해제 왕복, 일반 필사 지우기와 DUT 수신·빈 화면 확인은 통과했다. iOS 17 런타임의 소유 proof와 iOS 18 실제 계정 proof 왕복, 로그인 상태의 1.3.0 덮어쓰기 분기가 남아 있어 후보를 전체 출시 통과로 판정하지 않는다.

## 2026-09-23 후보 상태

소유 proof의 규칙, 전체 회귀, 표본·서버 관측 상태는 위 최신 게이트 기록과 호환성 시험 계획 §5-2를 따른다. 첫 로그인 전송, 같은 계정 다른 iPad 수신, 일반 1:8 생성·수정·지우기의 서버 저장과 양방향 수신, B의 표시·좌표 확인, 즐겨찾기 추가·해제 동기화는 iOS 26.2에서 과거 후보 기준으로 통과했다. metadata 값 형식까지 엄격히 보는 reader/proof 변경 뒤 Xcode 27 iPadOS 26.5 ACC sandbox clone에서 기존 private-store proof를 재실행해 20개 로컬 record name hash와 private DB inventory가 일치하고 두 inventory 지문이 같은 것을 확인했다. iOS 17.5 자동 회귀는 migration 수정 뒤 실패 0으로 통과했지만, iOS 17.0 및 OS 17의 소유 proof·실제 CloudKit 경로, iOS 18의 migration marker 의미와 계정 왕복, 로그인 상태의 1.3.0 덮어쓰기 분기는 남아 있다.

즐겨찾기 추가 경로는 2026-09-23 B에서 Genesis 1:8을 선택해 확인했다. B 사본은 필사 19행·즐겨찾기 1건·매핑 20건·대기 0건이었고, private DB probe는 전체 20레코드 중 Genesis 1:8 `CD_FavoriteVerse`를 확인했다. 30초 뒤 DUT는 같은 장·절의 즐겨찾기 1건을 받아 필사 19행·매핑 20건·대기 0건이었다. 사본 `b-after-favorite-add-before-probe`, `dut-after-favorite-add-delayed-receive`; probe 결과 `logs/probe-favorite-add-after-export-run.txt`.

이어 B에서 1:8 즐겨찾기를 해제했다. B 사본은 필사 19행·즐겨찾기 0건·매핑 19건·대기 0건이었고, 서버 probe에서 해당 `CD_FavoriteVerse` 삭제 tombstone을 확인해 활성 레코드는 19건으로 돌아왔다. 30초 뒤 DUT도 즐겨찾기 0건·필사 19행·매핑 19건·대기 0건을 받았으며 1:8 필사 payload는 1802B / `de5df55aa6147ab5`로 유지됐다. 사본 `b-after-favorite-remove-before-probe`, `dut-after-favorite-remove-delayed-receive`; probe `logs/probe-favorite-remove-after-export-run.txt`.

일반 삭제도 B에서 Genesis 1:8의 표준 「지우기」 경로로 실행했다. 지우기 직전 1:8 현재 행은 `isPresent=1`, 1802B / `de5df55aa6147ab5`였다. 이후 로컬·서버에는 현재 행(`isPresent=1`, 필기 payload 없음)과 이전 1802B 행(`isPresent=0`)이 각각 남았다. B는 필사 20행·매핑 20건·업로드 대기 0건, probe의 활성 서버 레코드는 20건이었다. 30초 뒤 DUT에도 같은 두 1:8 상태가 매핑 20건·대기 0건으로 수신됐다. 사용자는 DUT에서 1:8 필기 영역이 비었음을 확인했고, 상단 캡처에서는 원래 1:1·1:2 표본이 유지됐다(`/private/tmp/carve-release-sync-evidence/dut-after-1-8-erase-delayed-receive.png`). 사본 `b-after-1-8-erase-before-probe`, `dut-after-1-8-erase-delayed-receive`; probe `logs/probe-erase-1-8-server-export-run.txt`와 `logs/probe-erase-1-8-delayed-receive-run.txt`.

## 2026-09-23~24 출시 기준 재검증

Xcode 26.3에서 전체 `Carve-Workspace` 회귀를 iPad mini (A17 Pro) iPadOS 18.6, iPad mini iPadOS 26.2, iPad Air 11-inch (M3) iPadOS 26.2로 실행했다. 각 결과는 **997 passed · 4 expected failures · 5 skipped · 0 failed (총 1006)**다. 건너뛴 5개는 실기기 전용 UI 테스트다. iPadOS 18.6·26.2의 strict migration/ownership 집중 suite는 각각 67/67 통과했다. 새로운 blank/no-account simulator에서 18.6 mini와 26.2 Air가 앱을 크래시 없이 FirstRunGuide까지 표시하는 것도 확인했다. 시작 버튼 이후의 실제 필사 편집·저장은 확인하지 않았다.

`CarveApp` Release configuration은 iPad simulator 대상으로 컴파일됐고 앱 메타데이터는 2.0.0 (build 1)이었다. `CODE_SIGNING_ALLOWED=NO`인 compile이므로 archive, 배포 서명·entitlement, TestFlight 증거가 아니다. 이 작업 디렉터리의 미추적 `LegacyRowCorrespondence.swift`는 `LegacyJudgementDoubt: Error` 미준수와 `Int64`/`Int` 타입 불일치로 컴파일되지 않아 파일 자체를 보존하고 모든 검증 빌드에서만 제외했다. 그 파일을 release 변경에 포함한다면 오류를 고친 뒤 제외 없이 다시 검증해야 한다.

**2026-09-24 이전 후보 재실행:** 같은 Xcode 26.3 기준으로 iPad mini (A17 Pro) iPadOS 18.6·26.2에서 전체 `Carve-Workspace` 회귀를 다시 빌드·실행해 각각 **997 passed · 4 expected failures · 5 skipped · 0 failed (총 1006)**를 얻었다. 26.2 mini의 migration/ownership 관련 집중 다섯 suite도 67/67 통과했다. Air 결과와 blank/no-account 시작 smoke는 9/23의 기록이며 9/24에 다시 실행하지 않았다. 이 실행에서는 미완성 미추적 `LegacyRowCorrespondence.swift`를 제외했다. 다음의 최신 후보 재검증과 혼동하지 않도록 이 결과는 당시 상태로 보존한다.

strict-profile 변경 뒤의 live CloudKit proof는 아직 미실행이다. 기존 ACC simulator를 복제해 앱 실행을 시도하려 했지만, 자동 승인 검토가 기존 필기의 Development private CloudKit DB 전송 및 서버 상태 변경 가능성을 이유로 clone 실행을 거절했다. 앱은 실행하지 않았고 원본 ACC 기기는 수정하지 않았으며 임시 clone은 제거했다. 다른 실행 경로로 우회하지 않았다. 현재 전체 판정은 **NO-GO**이며, live proof를 재개하려면 기존 필기 표본·시험 계정·Development private DB를 대상으로 보내고 변경할 수 있다는 명시적 승인이 필요하다. 별도 synthetic 표본과 시험 계정으로 재설계하는 선택지도 있다.

## 2026-09-23 후속 strict-profile 검증

첫 후속 검증 환경은 macOS 27.2에서 Xcode 26.3 (17C529)을 선택했으며, 그때의 runtime 목록에는 iPadOS 26.2·26.4·26.5·27.0만 있어 iOS 18.6은 사용할 수 없었다. 일반 iPad mini (A17 Pro) · iPadOS 26.2에서 reader·ownership proof·edit environment·snapshot·migration-release 다섯 Domain suite의 `build-for-testing` 후 동일 DerivedData로 67/67 통과(실패·건너뜀 0), `CarveApp` iPad simulator 빌드도 성공했다.

이 당시 검증에서는 `Carve-ACC-dut`·`Carve-ACC-B`와 실제 CloudKit 계정을 사용하지 않았다. 첫 빌드에서 당시 checkout의 미추적 `LegacyRowCorrespondence.swift` 컴파일 오류가 발견되어 파일을 보존하고 빌드에서만 제외했다. fixture의 raw SQLite 작업에서 서로 다른 테스트가 일시 잠금을 보인 뒤 `LinkageFixture.exec`에 5초 busy timeout을 둔 최종 실행은 통과했다. 자세한 로그·결과 경로와 iOS 18.6 미실행 사유는 [호환성 시험 계획 §5-2 지원 OS 판독 후속](./icloud-sync-compatibility-test-plan.md#지원-os-판독-후속-2026-09-23)을 따른다.

### iPadOS 18.6 후속 검증

사용자가 iOS 18.6 runtime을 설치한 뒤 Xcode 26.3 (17C529), macOS 27.2, iPad mini (A17 Pro), build 22G86에서 최신 소스를 검증했다. 집중 다섯 suite를 새 `build-for-testing` 후 같은 DerivedData로 실행해 67/67 통과(실패·건너뜀 0)했다. Domain 전체는 449 통과·4 expected failure·실패 0·건너뜀 0, SettingsFeature 54/54, CarveFeature 457/457도 각각 빌드 성공 뒤 같은 산출물 실행으로 통과했다. `Carve-Workspace` 앱 simulator 빌드도 성공했다.

최초 iOS 18.6 실행의 다섯 assertion 실패는 테스트가 검증 OS 제한 없이 성공 경로를 기대한 탓이었다. iOS 18에서 reader가 unknown을 반환하고 소유 표식을 만들지 않는 것은 현재 production allowlist `[26]`의 의도된 fail-closed 동작이다. 테스트를 OS-aware로 바꿔 검증 OS의 V3 성공 경로와 범위 밖 OS의 거부 경로를 각각 확인했다. product allowlist는 바꾸지 않았다. 실제 1.3.0 표본의 `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey` 의미는 여전히 미확인이며 허용하지 않았다.

실행은 일반 iOS 18.6 iPad mini simulator에서 했다. `Carve-Ownership-iOS18-6`, `Carve-ACC-dut`, `Carve-ACC-B`와 CloudKit 계정은 사용하지 않았다. 이 당시 빌드에서만 checkout에 있던 미추적 `LegacyRowCorrespondence.swift`를 제외했다. 결과 경로는 호환성 시험 계획 §5-2에 기록했다.

**2026-09-24 후보 소스 후속:** 역할이 겹치고 호출되지 않는 미완성 `LegacyRowCorrespondence.swift` 초안을 `/private/tmp/carve-legacy-row-correspondence-draft-20260924.swift`로 옮겨 source 경로에서 제외했다. 새 DerivedData에서 `EXCLUDED_SOURCE_FILE_NAMES` 없이 전체 회귀를 실행해 iPadOS 17.5는 998 통과·실패 0·6 skip·4 expected failure, 18.6·26.2는 각각 999 통과·실패 0·5 skip·4 expected failure (각 총 1008)를 확인했다. 세 xcresult 경로와 범위는 [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md#미완성-초안-이동-후-파일-제외-없는-회귀-2026-09-24)에 있다. Apple 공개 문서와 Xcode 26.3 SDK headers에서 iOS 18 private metadata migration marker의 의미를 확인할 근거를 찾지 못해 reader allowlist `[26]`을 그대로 유지한다.

남은 출시 차단은 iOS 17.0 직접 시험과 소유 proof, iOS 18의 migration marker 의미와 계정 동기화 proof, iOS 19~25 profile, strict-profile 변경 뒤의 live CloudKit proof, 로그인 상태 1.3.0 업데이트 분기다. 이들 게이트가 해소되지 않아 2.0.0 출시 판정은 계속 **NO-GO**다.


## 2026-09-26 ownership 판정 후속 — 연결 전 차단 미해결

위 reader/proof 코드 수정과 17.5·18.6 focused CLI 회귀는 앱의 write gate 조건을 보강한 것이다. 실제 startup은 `App.swift`에서 proof provider를 만들기 전에 `.private` `ModelContainer`를 연다. 따라서 metadata/ownership proof가 nil이어도 그 proof는 앱의 직접 쓰기만 차단하며 Core Data의 background CloudKit mirroring을 차단하지 않는다.

같은-scope peer 시험 로그에는 실행 시작 직후 persisted iCloud identity 변경 진단, Core Data `AccountChange` reset, 로컬 모델 및 mirroring metadata purge가 있고, 뒤이어 현재 계정의 import가 성공했다. 오계정 export나 server loss는 확인하지 못했고, 해당 peer의 21행 consistent 사전 백업도 없어 원본 변화량은 모른다. raw Preservation은 남지만 앱이 그 snapshot을 화면에 열람하는 코드는 찾지 못했다. 따라서 소유권 불명확·계정 mismatch에서 원본 열람과 안전한 재시도가 확보됐다고 판정하지 않는다.

가장 좁은 추가 출시 차단은 `.private` attach 전에 ownership proof를 끝내는 startup gate와 비동기 재시도/컨테이너 수명 처리다. 제품 정책(무계정 1.3 V3 first-login 귀속, 새 2.0 초안 분리, mismatch시 업로드 금지)은 바꾸지 않는다. 이 gate와 실제 iPadOS 18 first-login server/independent peer receive가 검증되기 전까지 판정은 **NO-GO**다. 검증·로그 범위는 [호환성 시험 계획의 2026-09-26 후속 조사](./icloud-sync-compatibility-test-plan.md#같은-scope-peer-account-change-purge-후속-조사-2026-09-26)를 따른다.

### 2026-09-26 구현 후 갱신

위 항목의 “미해결”은 조사 직후 상태다. `CarveApp`은 이제 앱 Store 생성 전 `ReleaseStoreBootstrapper`를 기다린다. Domain은 snapshot/migration을 `.none`으로 수행하고, 계정 및 저장소 소유 proof가 같은 범위를 반환한 경우에만 `.private`를 만든다. 계정 미확인·불일치·proof 실패는 local-only ModelContainer + connection hold로 들어가 읽기를 유지하고 synced write/전체 삭제를 막으며 캔버스 필기는 별도 draft로 저장한다. 다음 실행에서 재판정하도록 Settings가 안내한다. 기존 metadata 판정의 exact observed profile, V3 first-login 제약은 그대로 두었고 iOS 18.6 private migrator key의 의미는 미확정으로 유지한다.

Xcode 27.0/macOS 27.2 Domain focused suites는 iPadOS 17.5와 18.6에서 각각 44/44 통과했고, CarveApp iPadOS 18.6 CLI build는 exit 0이다. 자동 검증 로그·xcresult 경로, CLI/live/manual 구분 및 남은 증거 제한은 [호환성 시험 계획의 ownership gate 후속](./icloud-sync-compatibility-test-plan.md#연결-전-ownership-gate-구현-후속-2026-09-26)에 있다.

이 구현은 기존 표본의 21→2 account-change purge를 복구하지 않으며 그 표본의 consistent 사전 사본이 없어 손실 여부도 확인하지 못했다. target V3 first-login은 local ownership ledger와 export bookkeeping까지 관측했지만 실제 server inventory는 아직 없다. fresh peer 수신, 실제 기존 same-account linked 1.3 V3 업데이트, live mismatch/확인 불가에서 upload 차단 및 사용자 열람·draft 확인은 미검증이다. 따라서 출시 판정은 아직 **NO-GO**이며 이 출시 gate를 완료로 추정하지 않는다.

## 2026-09-26 현재 판정 갱신 — metadata 및 ownership 수정 후

이 최신 항목이 과거의 `[26]` allowlist, metadata marker 거절, 수정 보류 및 과거 테스트 수를 갱신한다. 지원 최소 OS 정책은 그대로다. 현재 `LegacyRowLinkageReader`는 iPadOS major 17·18·26에서만 판정하고, 보존 V3와 실제 migrated V3/V6의 콘텐츠·좌표·표시를 비교하는 독립 proof를 first-login 전제에 추가했다. `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`의 migration 의미는 여전히 확인되지 않았다. parser는 관측된 key set 및 SQLite boolean structure를 확인할 뿐 완료 표식으로 사용하지 않는다.

앱 startup은 private CloudKit ModelContainer 연결 전에 소유권 preflight를 수행한다. 동일 계정 linked 자료는 persisted identity 및 정착된 private record 조회로 대조한다. 행에 정확히 연결된 정상 pending work는 영구 차단 조건에서 제외한다. 계정 없음·불일치·판정 실패 시 local-only 열람, 별도 초안, 안내/재시도를 유지하고 synced writes와 전체 삭제를 보류한다. 이것은 코드 및 synthetic regression 근거다.

Xcode 27.0/macOS 27.2 CLI에서 `DomainTest` ownership/migration 46/46이 iPadOS 17.5와 18.6 각각 통과했다. CarveApp Debug build도 exit 0이며 `iCloud.Carve.SwiftData.iCloud.dev` Development container를 사용한다. 자세한 xcresult/log 경로는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#2026-09-26-ownership-판정콘텐츠-대조-후속)과 [핸드오프](./release-2.0.0-migration-sync-handoff.md#2026-09-26-최신-ownership-판정검증-핸드오프)에 기록했다.

실제 cloud release gate는 여전히 **NO-GO**다. 기존 target의 local first-login ledger·payload 보존·export bookkeeping은 independent server inventory/peer receipt가 아니다. 새 독립 iPadOS 18.6 peer의 CloudKit runtime은 실행 시 `No account`를 반환해 Development peer receive를 진행하지 않았다. target과 같은 계정 확인 후 server payload/hash, 독립 peer 수신/화면 표시, existing linked same-account V3 update, mismatch/unavailable no-upload를 별도로 실증해야 한다. Device Hub manual smoke도 미완료다. Production 데이터 변경은 없다.

### Peer 로그인 후 계정 재검사 (2026-09-26)

사용자는 target과 peer의 Gmail(b) 계정이 같다고 확인했다. Hanpass(a)와 user token이 등록된 original account `never`는 별도 계정이다. 원문 주소는 기록하지 않았다. 전용 peer만 재부팅하고 앱을 다시 실행해도 CloudKit runtime은 `No account`였다. 앱은 `.none` hold였고 upload/import가 없었다. 이 증거는 user가 말한 로그인 사실과 iPadOS CloudKit runtime 상태가 아직 일치하지 않음을 보여 준다. Settings > Apple Account > iCloud 상태의 수동 확인이 끝날 때까지 실제 receive gate는 닫혀 있다.

### Peer 전환 전 보존 상태 (2026-09-26)

peer Settings에는 target `b`가 아니라 original/`never`가 표시됐다고 사용자가 확인했다. 앱 종료 후 전체 peer app container를 `/private/tmp/carve-x27-ownership-peer-pre-account-switch-20260926/AppContainer`에 보존했다. 사본 SQLite integrity `ok`, 필기 행 0, CloudKit record metadata table 없음이다. 전용 peer에서 계정 변경 시 empty local mirror reset 영향은 있을 수 있으나 handwritten payload는 확인되지 않았고 사본이 남아 있다. 계정 전환은 peer에만 적용하고 original/target은 그대로 둔다.

사용자가 peer에 `b` 로그인 완료를 알린 뒤 앱을 재실행했지만 KVS는 `No account`, startup ownership proof는 local-only hold를 기록했다. 현재 log에 CloudKit `account-status`의 반환값이 없어 exact API result는 미확정이다. Development 수신이나 export는 관측되지 않았고 Device Hub 설정 화면은 확인하지 못했다. 사용자 보고만으로 peer 로그인 경로를 통과 처리하지 않는다. 정확한 peer Settings > Apple Account > iCloud 확인과 별도 peer receive/payload/render 검증 전까지 release는 **NO-GO**다. 로그·검증 한계는 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md#b-로그인-후-peer-재검사-2026-09-26)에 있다.

Simulator CLI Settings 캡처에서 이 peer Apple Account 카드가 로그인 화면을 표시했다. 앱 종료 후 사본은 SQLite 무결성 `ok`, 필기 row 0 및 CloudKit record metadata 없음으로 확인했다. 전체 사본 경로와 캡처·로그 한계는 호환성 시험 계획에 있다. 사용자가 정확한 peer에서 b 로그인 완료를 다시 알려 줄 때까지 실제 receive 시험은 보류한다.
