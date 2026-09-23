# 2.0.0 필사 이전·iCloud 출시 범위 (2026-09-23 결정)

이 문서는 2.0.0의 **필사 이전·동기화 작업**에 적용할 최신 제품 결정을 기록한다. [출시 로드맵](./release-2.0.0-roadmap.md)의 다른 기능·배포 조건까지 없애는 결정은 아니다. [C14 결정 2](./icloud-sync-and-backup-policy.md)의 분리·명시적 가져오기 설계와 실험 기록은 역사적 근거로 남기되, 이 문서의 출시 범위가 그 설계의 **2.0.0 필수 구현 범위**보다 우선한다. 현재 코드가 이미 이 범위를 만족한다는 뜻은 아니다.

## 이번 출시에서 보장할 것

1. **1.3.0 → 2.0.0 업데이트 때 기존 필사를 잃지 않는다.** 실제 출시본 1.3.0(`49f2dc27`, V3)으로 만든 저장소를 사용한다. 로그인 상태와 무계정 상태를 각각 확인하고, `BibleDrawing`과 실제 표본에 있는 `BiblePageDrawing`의 행 수뿐 아니라 필기 내용·좌표·화면 표시를 업데이트 전후에 대조한다. 기존 데이터가 있는 사용자를 빈 새 설치로 잘못 취급하거나, 마이그레이션 실패 뒤 빈 저장소에서 편집하게 해서는 안 된다.
2. **1.3.0에서 계정 없이 작성한 옛 필사는 2.0.0에서 iCloud 로그인 후 전송된다.** 업데이트 직후 로컬 표시가 유지되고, 첫 로그인 뒤 서버에 올라가며, 같은 계정의 다른 iPad에도 같은 내용이 나타나는지 확인한다. 서버 이벤트 성공·행 개수만으로 통과시키지 않는다. 로그인 전후 앱 실행 중과 재실행 경로를 모두 본다. 현재 C14 게이트는 이 경로에서 연결을 보류하므로 **구현 변경과 재검증이 필요하다**.

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

지원 OS의 실제 출시 경로도 확인한다. 앱의 기본 배포 타깃은 iOS 17.0이지만 legacy 저장소 소유 proof의 허용 OS는 현재 iOS 26뿐이다. 첫 로그인 예외는 보존된 V3 사본의 매니페스트·파일 지문, 정확한 무계정 metadata key 네 개와 올바른 값 형식, migration 미요청, 계정 식별·CloudKit 대응·대기 작업 부재, 로컬 행 수 일치를 모두 요구한다. 기존 로그인 저장소는 iOS 26.2에서 관측한 정확한 private metadata key 집합·값 형식, migration 미요청, identity 확인 완료, 계정 일치와 private DB 전체 레코드 조회를 요구한다. 미지 키·누락·중복·값 형식 오류는 모두 거절한다.

iOS 18.6의 실제 1.3.0 V3 표본은 첫 저장 뒤 추가 metadata key `PFCloudKitMetadataModelMigratorMigrationBeganCommitKey`를 만들고, 해당 값의 SQLite 형식은 정수 boolean `true`였다. 이 private key의 완료·진행 의미는 공개 문서나 현재 증거로 확인되지 않았다. 첫 로그인 profile의 정확한 네 키 조건은 이 표본을 거절하며, 기존 private profile도 미지 키를 거절한다. 따라서 iOS 18은 허용하지 않고 fail-closed로 유지한다. 시험용 `Carve-Ownership-iOS18-6`에는 synthetic Genesis 1:3 V3 행만 두었고 iCloud 로그인을 하지 않았다. Genesis 1:1·1:2의 기존 `Carve-ACC-dut`·`Carve-ACC-B` 표본은 읽기 전후 보존됐고 변경하지 않았다.

iOS 18.3.1·18.6의 앞선 집중 시험은 identity와 CloudKit 조회를 test double로 대체한 단위 검증이며 실제 소유 proof가 아니다. iOS 18.6·26.2에서 `CarveApp` 타깃 빌드는 성공했다. iOS 17 runtime과 iOS 19~25 runtime은 이 머신에서 사용할 수 없었고, iOS 17 최소 지원 경로는 검증하지 못했다. **소유 proof를 iOS 17~25에서 안전하게 열 근거가 없고 iOS 17 로그인 동기화가 미검증이므로 전체 출시 판정은 NO-GO다.**

## 출시 게이트와 이번 후보의 결과

이번 후보는 C14 분리·삭제 동작을 실행하지 않고도 로그인 소유 쓰기를 여는 proof provider를 앱에 연결했다. proof 결과가 없으면 캔버스는 로컬 초안에만 쓰고, `SyncedWriteBlock`을 사용하는 즐겨찾기·위젯 보관·이력 복원·N-Canvas 직접 쓰기도 그대로 막힌다. 기존 server-work token, 삭제 기준점 K, 계정 변경 잠금과 원본 보존·마이그레이션 실패 차단을 유지한다. 자세한 코드·시험 기록은 [호환성 시험 계획 §5-2](./icloud-sync-compatibility-test-plan.md)를 본다.

즐겨찾기·위젯 보관·이력 복원·N-Canvas 경로는 공통 소유 차단과 자동 시험에서 확인했다. 실제 CloudKit 왕복은 즐겨찾기와 일반 필사에서 관측했으며, 위젯 보관·이력 복원·N-Canvas UI의 별도 라이브 서버 실행은 이번 시험에서 하지 않았다.

Xcode 26.3 / iPadOS 26.2 회귀는 Domain 452개(448 통과·선언된 expected failure 4개·실패 0), SettingsFeature 54개, CarveFeature 457개가 통과했다. 각 scheme의 `build-for-testing` 성공 후 같은 산출물로 `test-without-building`을 실행했다. iPadOS 18.3.1·18.6의 앞선 집중 시험 66개는 당시 reader가 허용한 규칙에 대한 결과로, 이번 fail-closed 변경 뒤 재실행 결과와 구분한다. 그 시험의 계정 identity와 CloudKit record lookup은 test double이므로 실제 private DB 로그인·왕복 증거가 아니다. `CarveApp` 시뮬레이터 타깃은 iPadOS 18.6·26.2에서 빌드됐다. 전체 build lint 단계의 다른 파일 경고 4건은 남았지만 변경 Swift 파일 lint는 통과했다. iOS 17 런타임 부재와 iOS 18 metadata marker 의미 미확인, 실제 iOS 18 계정 왕복 미실행은 남은 출시 차단이다.

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

소유 proof의 규칙, 전체 회귀, 표본·서버 관측 상태는 위 최신 게이트 기록과 호환성 시험 계획 §5-2를 따른다. 첫 로그인 전송, 같은 계정 다른 iPad 수신, 일반 1:8 생성·수정·지우기의 서버 저장과 양방향 수신, B의 표시·좌표 확인, 즐겨찾기 추가·해제 동기화는 iOS 26.2에서 과거 후보 기준으로 통과했다. metadata 값 형식까지 엄격히 보는 reader/proof 변경 뒤에는 live CloudKit 소유 판정을 재실행하지 않았다. iOS 17.0의 실제 경로, iOS 18의 migration marker 의미와 계정 왕복, 로그인 상태의 1.3.0 덮어쓰기 분기는 남아 있다.

즐겨찾기 추가 경로는 2026-09-23 B에서 Genesis 1:8을 선택해 확인했다. B 사본은 필사 19행·즐겨찾기 1건·매핑 20건·대기 0건이었고, private DB probe는 전체 20레코드 중 Genesis 1:8 `CD_FavoriteVerse`를 확인했다. 30초 뒤 DUT는 같은 장·절의 즐겨찾기 1건을 받아 필사 19행·매핑 20건·대기 0건이었다. 사본 `b-after-favorite-add-before-probe`, `dut-after-favorite-add-delayed-receive`; probe 결과 `logs/probe-favorite-add-after-export-run.txt`.

이어 B에서 1:8 즐겨찾기를 해제했다. B 사본은 필사 19행·즐겨찾기 0건·매핑 19건·대기 0건이었고, 서버 probe에서 해당 `CD_FavoriteVerse` 삭제 tombstone을 확인해 활성 레코드는 19건으로 돌아왔다. 30초 뒤 DUT도 즐겨찾기 0건·필사 19행·매핑 19건·대기 0건을 받았으며 1:8 필사 payload는 1802B / `de5df55aa6147ab5`로 유지됐다. 사본 `b-after-favorite-remove-before-probe`, `dut-after-favorite-remove-delayed-receive`; probe `logs/probe-favorite-remove-after-export-run.txt`.

일반 삭제도 B에서 Genesis 1:8의 표준 「지우기」 경로로 실행했다. 지우기 직전 1:8 현재 행은 `isPresent=1`, 1802B / `de5df55aa6147ab5`였다. 이후 로컬·서버에는 현재 행(`isPresent=1`, 필기 payload 없음)과 이전 1802B 행(`isPresent=0`)이 각각 남았다. B는 필사 20행·매핑 20건·업로드 대기 0건, probe의 활성 서버 레코드는 20건이었다. 30초 뒤 DUT에도 같은 두 1:8 상태가 매핑 20건·대기 0건으로 수신됐다. 사용자는 DUT에서 1:8 필기 영역이 비었음을 확인했고, 상단 캡처에서는 원래 1:1·1:2 표본이 유지됐다(`/private/tmp/carve-release-sync-evidence/dut-after-1-8-erase-delayed-receive.png`). 사본 `b-after-1-8-erase-before-probe`, `dut-after-1-8-erase-delayed-receive`; probe `logs/probe-erase-1-8-server-export-run.txt`와 `logs/probe-erase-1-8-delayed-receive-run.txt`.
