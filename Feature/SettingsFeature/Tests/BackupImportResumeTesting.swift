//
//  BackupImportResumeTesting.swift
//  SettingsFeatureTest
//
//  「백업 불러오기」 의 멈춘 작업 — 같은 계정 이어 하기 · 다른 계정 작업은 처음부터 · 버리기 · 이어 하는 사이 계정 바뀜
//  (설계 docs/backup-import-design.md §6-3).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - A 계정에서 일부 넣은 작업을 B 계정 저장소에 잇는 것(다른 계정 작업의 「이어서 불러오기」)
/// - 이어 하기가 암호를 다시 받지 않는 것(평문 · 암호를 기기에 남기지 않는다)
/// - 지금 연결되지 않은 실행의 멈춘 작업을 「다른 계정」 이라고 단정하는 것
/// - 버리기가 멈춘 작업을 다시 보지 않아 낡은 화면이 남는 것
@Suite("설정 — 필사 백업 · 멈춘 불러오기")
@MainActor
struct BackupImportResumeTesting {
    /// 문구를 꺼내는 언어 — 시험 언어(스킴 ko-KR)와 같은 한국어라 기대 문구는 한국어 원문 그대로다.
    private static let koreanLocale = Locale(identifier: "ko_KR")
    private typealias Feature = BackupImportFeature

    @Test("같은 계정의 멈춘 작업은 「이어서 불러오기」 — 암호를 다시 받아 끝난 장을 든 검사 결과로 미리보기, 처음부터는 받지 않는다")
    func sameAccountJobResumesWithPasswordAgain() async {
        let log = LockIsolated<[ImportEvent]>([])
        let job = ImportFixture.job(canResume: true)
        let resumed = Feature.Inspection(ImportFixture.inspection(doneChapters: [ImportFixture.genesis1]))
        let importer = StubBackupImporter(log: log, pending: job, inspection: .success(resumed.value))
        let store = makeImportStore(importer: importer, log: log)
        let pending = Feature.PendingJob(job)

        await store.send(.view(.onAppear))
        await store.receive(.pendingJobLoaded(pending)) {
            $0.step = .pendingJob(pending)
        }
        #expect(BackupCopy.pendingJobTitle(job, locale: Self.koreanLocale) == "멈춘 불러오기가 있어요")
        #expect(BackupCopy.pendingJobProgress(job, locale: Self.koreanLocale) == "3장 중 1장까지 넣었어요 · 넣은 필사 3개")
        // 같은 계정의 작업은 처음부터 하지 않는다 — 잇거나 버린다.
        await store.send(.view(.restartTapped))
        await store.send(.view(.resumeTapped)) {
            $0.step = .password(.resume(pending))
        }
        await store.send(.view(.passwordChanged(ImportFixture.password))) {
            $0.password = ImportFixture.password
        }
        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.resume(pending))
        }
        await store.receive(.inspectFinished(.success(resumed))) {
            $0.step = .preview(resumed)
        }
        // 멈춘 작업은 기기 안 암호화 사본을 다시 검사한다 — 고른 파일의 보안 범위 접근은 열지 않는다.
        #expect(log.value == [.pendingJobRead, .resumed(jobID: ImportFixture.jobID, password: ImportFixture.password)])
    }

    @Test("다른 계정에서 시작한 작업은 잇지 않는다 — 「버리기」 · 「이 계정으로 처음부터」 만, 처음부터는 사본으로 새로 검사한다")
    func otherAccountJobOnlyRestartsOrDiscards() async {
        let log = LockIsolated<[ImportEvent]>([])
        let job = ImportFixture.job(canResume: false)
        let fresh = Feature.Inspection(ImportFixture.inspection(jobID: ImportFixture.otherJobID))
        let importer = StubBackupImporter(log: log, pending: job, inspection: .success(fresh.value))
        let pending = Feature.PendingJob(job)
        let store = makeImportStore(.at(.pendingJob(pending)), importer: importer, log: log)

        #expect(BackupCopy.pendingJobTitle(job, locale: Self.koreanLocale) == "다른 iCloud 계정에서 시작한 불러오기예요")
        #expect(BackupCopy.pendingJobGuidance(job, locale: Self.koreanLocale) == "지금 계정의 필사에는 이어서 넣지 않아요. 이미 넣은 필사는 그대로 있어요.")
        // 다른 계정의 작업은 이어 하지 않는다 — 상태가 바뀌면 TestStore 가 실패한다.
        await store.send(.view(.resumeTapped))
        await store.send(.view(.restartTapped)) {
            $0.step = .password(.restart(pending))
        }
        await store.send(.view(.passwordChanged(ImportFixture.password))) {
            $0.password = ImportFixture.password
        }
        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.restart(pending))
        }
        await store.receive(.inspectFinished(.success(fresh))) {
            $0.step = .preview(fresh)
        }
        #expect(log.value == [.restarted(jobID: ImportFixture.jobID, password: ImportFixture.password)])
    }

    @Test("지금 연결되지 않은 실행의 멈춘 작업은 다른 계정이라 하지 않고, 지금 잇지 못하는 까닭을 보인다")
    func unconnectedJobExplainsBlockInsteadOfOtherAccount() {
        let job = ImportFixture.job(canResume: false, writeBlock: .signedOut)

        #expect(BackupCopy.pendingJobTitle(job, locale: Self.koreanLocale) == "멈춘 불러오기를 지금은 이어서 할 수 없어요")
        #expect(BackupCopy.pendingJobGuidance(job, locale: Self.koreanLocale) == "iCloud 에 로그인한 뒤 앱을 다시 열면 불러올 수 있어요. 이미 넣은 필사는 그대로 있어요.")
    }

    @Test("「버리기」 는 작업 기록과 사본만 지우고 멈춘 작업을 다시 본다 — 없으면 파일 고르기", arguments: [true, false])
    func discardingJobReloads(canResume: Bool) async {
        let log = LockIsolated<[ImportEvent]>([])
        let job = ImportFixture.job(canResume: canResume)
        let importer = StubBackupImporter(log: log, pending: job, afterDiscard: nil)
        let store = makeImportStore(.at(.pendingJob(Feature.PendingJob(job))), importer: importer, log: log)

        await store.send(.view(.discardJobTapped)) {
            $0.step = .loading
        }
        await store.receive(.pendingJobLoaded(nil)) {
            $0.step = .chooseFile
        }
        #expect(log.value == [.jobDiscarded(jobID: ImportFixture.jobID), .pendingJobRead])
    }

    @Test("이어 하는 사이 계정이 바뀌어 잇지 못하면 안내하고, 암호를 다시 받지 않으며, 돌아가면 멈춘 작업을 다시 읽는다")
    func resumeRejectedForOtherAccountGoesBack() async {
        let log = LockIsolated<[ImportEvent]>([])
        let job = Feature.PendingJob(ImportFixture.job(canResume: true))
        // 다시 읽으면 지금 계정과 대상 계정이 달라 이어 할 수 없는 작업이다.
        let reread = Feature.PendingJob(ImportFixture.job(canResume: false))
        let importer = StubBackupImporter(log: log, pending: reread.value, inspection: .failure(.jobFromOtherAccount))
        let store = makeImportStore(.at(.password(.resume(job)), password: ImportFixture.password), importer: importer, log: log)

        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.resume(job))
        }
        await store.receive(.inspectFinished(.failure(.jobFromOtherAccount))) {
            $0.step = .inspectFailed(.jobFromOtherAccount, .resume(job))
        }
        #expect(BackupCopy.inspectFailed(.jobFromOtherAccount, locale: Self.koreanLocale).hasPrefix("다른 iCloud 계정에서 시작한 불러오기예요."))
        // 다른 계정의 작업은 암호를 다시 넣어도 잇지 않는다. 파일 고르기도 이 단계의 길이 아니다.
        await store.send(.view(.retryTapped))
        await store.send(.view(.chooseFileTapped))
        await store.send(.view(.backToPendingJobTapped)) {
            $0.step = .loading
        }
        await store.receive(.pendingJobLoaded(reread)) {
            $0.step = .pendingJob(reread)
        }
        #expect(log.value == [.resumed(jobID: ImportFixture.jobID, password: ImportFixture.password), .pendingJobRead])
    }

    @Test("이어 하기에서 암호가 틀리면 같은 작업으로 암호를 다시 받는다")
    func resumeWithWrongPasswordAsksAgain() async {
        let log = LockIsolated<[ImportEvent]>([])
        let job = Feature.PendingJob(ImportFixture.job(canResume: true))
        let importer = StubBackupImporter(log: log, pending: job.value, inspection: .failure(.wrongPasswordOrDamaged))
        let store = makeImportStore(.at(.password(.resume(job)), password: "wrong-password"), importer: importer, log: log)

        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.resume(job))
        }
        await store.receive(.inspectFinished(.failure(.wrongPasswordOrDamaged))) {
            $0.step = .inspectFailed(.wrongPasswordOrDamaged, .resume(job))
        }
        #expect(BackupCopy.retryTitle(.wrongPasswordOrDamaged, locale: Self.koreanLocale) == "암호 다시 입력")
        await store.send(.view(.retryTapped)) {
            $0.step = .password(.resume(job))
        }
        #expect(log.value == [.resumed(jobID: ImportFixture.jobID, password: "wrong-password")])
    }
}
