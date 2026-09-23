# 다음 컴퓨터에서 이어 할 작업 프롬프트

아래 내용을 새 Codex 작업에 붙여 넣는다.

```text
Carve 2.0.0의 iCloud 동기화 출시 차단을 이어서 해결해 줘.

저장소는 /Users/leetaek/Documents/Area/Carve/Carve, 작업 브랜치는 codex/2-0-0-migration-sync-release다. 먼저 이 브랜치의 현재 status와 최근 commit을 확인하고, 인계 문서 docs/release-2.0.0-migration-sync-handoff.md와 docs/release-2.0.0-migration-sync-continuation-prompt.md, 그리고 docs/release-2.0.0-migration-sync-scope.md 및 docs/icloud-sync-compatibility-test-plan.md를 읽어.

현재 상태는 handoff 문서의 검증 기록을 기준으로 삼아. strict metadata-profile 변경 뒤 iOS 18.6 DomainTest build-for-testing은 성공했으나 test-without-building이 실패했다. 실패 뒤 test assertion과 reader version 기대값을 일부 수정했으므로, 다섯 집중 suite를 새로 build-for-testing하고 성공한 동일 산출물로 test-without-building하는 일부터 해. fixture metadata profile 실패 원인을 고치되, PFCloudKitMetadataModelMigratorMigrationBeganCommitKey의 의미가 확인되기 전에는 이를 허용하거나 ownership을 주장하지 마.

필수 제약:
- 다른 worktree, 특히 .claude/worktrees/gallant-noyce-d0589a를 수정하지 마.
- 커밋·푸시는 별도 요청이 없으면 하지 말고, reset·강제 푸시·파괴 명령은 금지한다.
- iPad simulator만 사용하고 Xcode 26.3을 우선한다. 현재 확인된 runtime은 iOS 16.4, 18.3.1, 18.6, 26.2이며 iOS 17 및 19~25는 없다.
- Carve-ACC-dut와 Carve-ACC-B는 같은 sandbox 계정으로 로그인돼 있다. 계정을 전환하거나 로그아웃하지 않는다. Genesis 1:1·1:2의 기존 필사 표본을 삭제·수정하지 말고, 계정 식별 원문·이메일·인증정보를 출력하거나 저장하지 마.
- Carve-Ownership-iOS18-6에는 iOS 18.6 1.3.0 V3 저장소와 합성 Genesis 1:3 행이 있다. 현재 로그인 상태는 계정 없음이다. 이 simulator 상태를 보존하고, 확인되지 않은 marker를 안전하다고 가정해 로그인 왕복하지 마.
- 소유는 계정 확인만으로 주지 않는다. 알 수 없음·계정 불일치·불완전 metadata·migration 진행/요청·서버 조회 실패는 fail-closed다. 기존 저장소 보존, migration 실패 차단, 계정 변경 차단, server-work 표, 삭제 기준점 K, SyncedWriteBlock, 무계정 신규 로컬 초안의 자동 업로드 금지를 유지한다.
- 실기기 대신 simulator에서 수행한 드래그를 Apple Pencil 압력·기울기 검증으로 주장하지 않는다.

iOS 18.6 reader / ownership / snapshot / edit environment / migration-release 집중 suite를 먼저 통과시켜. 그 다음 iOS 26.2에서 최신 strict-profile 변경을 좁게 검증하고, 필요 시 기존 simulator snapshot과 probe.sh를 이용하되 각 실행 전후 저장소·서버 상태와 기존 표본 보존을 기록해. strict profile 뒤 live ownership proof가 안전하게 통과하는지 따로 판단하고, 계정 재로그인은 하지 마.

iOS 17 runtime이 없으면 설치 가능한 Xcode 26.3 호환 iPadOS 17 runtime 또는 iOS 17 iPad가 필요하다고 정확히 기록하고, 최소 지원 OS 검증을 완료한 척하지 마. iOS 19~25도 runtime이 없어 미검증으로 남긴다. 위젯 보관·이력 복원·N-Canvas의 실제 CloudKit 왕복과 로그인 상태 1.3.0 업데이트 분기도 미검증이다. C14 F44~F57은 실험 기록으로 남기고 출시 통과 근거로 바꾸지 마.

검증을 못한 명령과 이유, OS별 결과, 미검증 범위, 남은 출시 위험, go/no-go 판정을 두 release 문서에 갱신해. 안전하게 허용 범위를 넓힐 증거가 없으면 차단을 우회하지 말고 NO-GO를 유지해.
```
