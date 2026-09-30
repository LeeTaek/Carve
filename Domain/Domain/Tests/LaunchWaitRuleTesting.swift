//
//  LaunchWaitRuleTesting.swift
//  DomainTest
//
//  시작 화면의 선택형 대기 — 초기 복원일 때만 iCloud 를 기다리고, 처음부터 「먼저 시작하기」 를 둔다 (정책 §3 · §3-1,
//  2026-09-21 후속 리뷰 P0-3 · 사용자 결정).
//

@testable import Domain
import Foundation
import Testing

/// 이 파일이 막는 것:
/// - 재설치한 기기가 20초 뒤 **자동으로** 들어가 버리는 것 — 20초 · 60초에는 안내만 바꾸고 기다린다(사용자 결정)
/// - 「먼저 시작하기」 가 20초가 지나야 나타나는 것 — 처음부터 있어야 한다
/// - 로컬이 빈 것만으로 기존 사용자(앞서 들어간 적 있음 · 초기 복원을 마침 · 로컬에 필사가 있음)를 긴 대기로 되돌리는 것
/// - 마이그레이션(V1 전용 컨테이너) · 저장소를 쓸 수 없는 상태에서 「먼저 시작하기」 로 들어가는 것(테스트 계획 MIG-F1)
@Suite("시작 화면 — 선택형 대기")
struct LaunchWaitRuleTesting {
    private typealias State = PersistentCloudKitContainer.CloudSyncState

    @Test("초기 복원은 이 설치에서 처음이고 로컬이 빌 때만이다 — 앞서 들어갔거나 복원을 마쳤거나 로컬에 필사가 있으면 일반 실행")
    func modeTable() {
        #expect(LaunchWaitRule.mode(outcome: nil, hasEnteredBefore: false, hasLocalDrawings: false) == .initialRestore)
        // 로컬을 읽지 못했으면 기다리는 쪽 — 처음부터 「먼저 시작하기」 가 있다.
        #expect(LaunchWaitRule.mode(outcome: nil, hasEnteredBefore: false, hasLocalDrawings: nil) == .initialRestore)

        #expect(LaunchWaitRule.mode(outcome: nil, hasEnteredBefore: false, hasLocalDrawings: true) == .normal)
        #expect(LaunchWaitRule.mode(outcome: nil, hasEnteredBefore: true, hasLocalDrawings: false) == .normal)
        for outcome in [InitialRestoreOutcome.importSucceeded, .startedFirst, .startedWithoutICloud] {
            #expect(LaunchWaitRule.mode(outcome: outcome, hasEnteredBefore: false, hasLocalDrawings: false) == .normal)
        }
    }

    @Test("초기 복원은 import 가 성공하거나 「먼저 시작하기」 를 누를 때만 들어간다 — 시간이 지나도(stillWaiting) · 실패해도 머문다")
    func initialRestoreWaitsForImportOrChoice() {
        for state in [State.idle, .syncing, .stillWaiting, .failed(.accountUnavailable), .failed(.importFailed)] {
            #expect(LaunchWaitRule.route(state, mode: .initialRestore, startedFirst: false) == .stay)
            #expect(LaunchWaitRule.route(state, mode: .initialRestore, startedFirst: true) == .enterWriting)
        }
        #expect(LaunchWaitRule.route(.syncCompleted, mode: .initialRestore, startedFirst: false) == .enterWriting)
    }

    @Test("일반 실행은 로컬이 준비되면 곧바로 들어간다 — import 를 기다리지 않는다")
    func normalLaunchEntersWithoutWaiting() {
        for state in [State.idle, .syncing, .stillWaiting, .syncCompleted, .failed(.accountCheckFailed)] {
            #expect(LaunchWaitRule.route(state, mode: .normal, startedFirst: false) == .enterWriting)
        }
        // 대기 방식을 아직 모르면(로컬을 세는 중) 머문다.
        #expect(LaunchWaitRule.route(.syncCompleted, mode: nil, startedFirst: false) == .stay)
    }

    @Test("마이그레이션 · 저장소를 쓸 수 없는 상태는 어느 방식에서도 · 먼저 시작해도 들어가지 않는다 — 「먼저 시작하기」 도 보이지 않는다")
    func blockedStatesNeverEnter() {
        for mode in [LaunchWaitMode.normal, .initialRestore] {
            for startedFirst in [false, true] {
                #expect(LaunchWaitRule.route(.migration, mode: mode, startedFirst: startedFirst) == .stay)
                #expect(LaunchWaitRule.route(.migrationCompleted, mode: mode, startedFirst: startedFirst) == .restartRequired)
                #expect(LaunchWaitRule.route(.migrationEndedWithoutImport(nil), mode: mode, startedFirst: startedFirst) == .restartRequired)
                #expect(LaunchWaitRule.route(.storeUnavailable(.openFailed), mode: mode, startedFirst: startedFirst) == .blocked(.openFailed))
            }
            for state in [State.migration, .migrationCompleted, .migrationEndedWithoutImport(nil), .storeUnavailable(.unreadable)] {
                #expect(!LaunchWaitRule.offersStartFirst(state, mode: mode))
            }
        }
    }

    @Test("「먼저 시작하기」 는 초기 복원의 **처음부터** 있다 — 일반 실행 · import 성공 뒤에는 없다")
    func startFirstIsOfferedFromTheBeginning() {
        for state in [State.idle, .syncing, .stillWaiting, .failed(.accountUnavailable)] {
            #expect(LaunchWaitRule.offersStartFirst(state, mode: .initialRestore))
            #expect(!LaunchWaitRule.offersStartFirst(state, mode: .normal))
            #expect(!LaunchWaitRule.offersStartFirst(state, mode: nil))
        }
        #expect(!LaunchWaitRule.offersStartFirst(.syncCompleted, mode: .initialRestore))
    }

    @Test("들어갈 때 초기 복원이 어떻게 끝났는지 남긴다 — import 성공 · 먼저 시작 · iCloud 없이 시작을 가른다")
    func outcomeOnEntering() {
        #expect(LaunchWaitRule.outcome(entering: .syncCompleted, mode: .initialRestore, startedFirst: false) == .importSucceeded)
        #expect(LaunchWaitRule.outcome(entering: .syncing, mode: .initialRestore, startedFirst: true) == .startedFirst)
        #expect(LaunchWaitRule.outcome(entering: .stillWaiting, mode: .initialRestore, startedFirst: true) == .startedFirst)
        #expect(LaunchWaitRule.outcome(entering: .failed(.accountUnavailable), mode: .initialRestore, startedFirst: true) == .startedWithoutICloud)
        // 들어가지 않거나 일반 실행이면 남기지 않는다.
        #expect(LaunchWaitRule.outcome(entering: .syncing, mode: .initialRestore, startedFirst: false) == nil)
        #expect(LaunchWaitRule.outcome(entering: .syncCompleted, mode: .normal, startedFirst: false) == nil)
    }

    @Test("20초 · 60초는 안내 단계일 뿐이다 — 단계가 올라도 들어가는지는 바뀌지 않는다")
    func stagesDoNotChangeTheRoute() {
        #expect(LaunchWaitRule.slowAfter == .seconds(20))
        #expect(LaunchWaitRule.verySlowAfter == .seconds(60))
        #expect(LaunchWaitStage.checking < .slow && LaunchWaitStage.slow < .verySlow)
        // route 는 단계를 입력으로 받지 않는다 — 기다림을 끝내는 것은 import 성공과 사용자의 선택뿐이다.
        #expect(LaunchWaitRule.route(.stillWaiting, mode: .initialRestore, startedFirst: false) == .stay)
    }
}
